#include "bridge.h"
#include "main/connection.h"
#include "main/database.h"
#include "main/query_result.h"
#include "parser/parser.h"
#include "parser/explain_statement.h"
#include "processor/result/flat_tuple.h"
#include "common/types/value/nested.h"
#include "common/json_utils.h"
#include "transaction/transaction_context.h"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <stdexcept>
#include <thread>
#include <vector>
#include <unordered_map>
#include <cmath>

struct aphid_params {
    std::unordered_map<std::string, std::unique_ptr<lbug::common::Value>> values;
};

namespace {
std::atomic<uint32_t> live_databases{0}, live_workers{0};
#ifdef APHID_TEST_FAULTS
std::atomic<bool> fail_worker{false};
#endif
void report(aphid_error* out, int32_t code, const char* message) noexcept {
    if (!out) return;
    out->code = code;
    size_t length = 0;
    while (length < sizeof(out->message) - 1 && message[length]) ++length;
    std::memcpy(out->message, message, length);
    out->message[length] = 0;
    out->length = length;
}
struct Job {
    uint64_t id;
    std::string query;
    void* context;
    aphid_completion complete;
    aphid_cancelled cancelled;
    std::unique_ptr<aphid_params> params;
    uint32_t control = 0;
};
void validate_query(const std::string& query) {
    const auto statements = lbug::parser::Parser::parseQuery(query);
    if (statements.size() != 1) throw std::invalid_argument{"exactly one statement is required"};
    const auto* statement = statements.front().get();
    while (statement->getStatementType() == lbug::common::StatementType::EXPLAIN) {
        statement = static_cast<const lbug::parser::ExplainStatement*>(statement)->getStatementToExplain();
    }
    if (statement->getStatementType() == lbug::common::StatementType::TRANSACTION) {
        throw std::invalid_argument{"manual transaction control is not allowed; use Aphid.transaction"};
    }
}
struct Session {
    std::mutex mutex;
    std::condition_variable wake;
    std::unique_ptr<lbug::main::Connection> connection;
    std::unique_ptr<lbug::main::PreparedStatement> statement;
    std::unique_ptr<lbug::main::QueryResult> result;
    std::shared_ptr<lbug::processor::FlatTuple> unread_row;
    uint64_t rows_read = 0;
    std::optional<Job> pending;
    std::thread worker;
    uint64_t id = 0;
    uint64_t lease = 0;
    bool lease_abandoned = false, lease_failed = false;
    bool busy = false, ready = false, stop = false, cancel = false, discard = false, fetching = false;
    std::atomic<bool> exited{false};
    aphid_error error{};

    explicit Session(lbug::main::Database* db) : connection{std::make_unique<lbug::main::Connection>(db)} {}

    void interrupt() noexcept {
        try {
            std::lock_guard lock{mutex};
            if (connection && busy && !ready && (cancel || stop)) connection->interrupt();
        } catch (...) {} // Cancellation remains requested and the controller retries.
    }

    void run() noexcept {
        ++live_workers;
        try {
            for (;;) {
                std::optional<Job> job;
                std::unique_ptr<lbug::main::PreparedStatement> old_statement;
                std::unique_ptr<lbug::main::QueryResult> garbage;
                std::shared_ptr<lbug::processor::FlatTuple> old_row;
                bool should_stop, was_cancelled, release_lease;
                {
                    std::unique_lock lock{mutex};
                    wake.wait(lock, [&] { return !fetching && (stop || pending.has_value() || discard || lease_abandoned); });
#ifdef APHID_TEST_FAULTS
                    if (fail_worker.exchange(false)) throw std::runtime_error{"injected worker failure"};
#endif
                    should_stop = stop;
                    was_cancelled = cancel || stop;
                    release_lease = lease_abandoned;
                    if (pending) {
                        job = std::move(pending);
                        pending.reset();
                    } else {
                        old_row = std::move(unread_row);
                        garbage = std::move(result);
                        old_statement = std::move(statement);
                    }
                }
                if (!job) {
                    old_row.reset();
                    garbage.reset(); // Potentially large destruction outside control lock.
                    old_statement.reset();
                    if (release_lease) {
                        auto* transaction = lbug::transaction::TransactionContext::Get(*connection->getClientContext());
                        if (transaction->hasActiveTransaction()) transaction->rollback();
                    }
                    {
                        std::lock_guard lock{mutex};
                        busy = ready = discard = cancel = false;
                        id = 0;
                        if (release_lease) {
                            lease = 0;
                            lease_abandoned = lease_failed = false;
                        }
                    }
                    if (should_stop) break;
                    continue;
                }
                aphid_error outcome{};
                std::unique_ptr<lbug::main::PreparedStatement> prepared;
                std::unique_ptr<lbug::main::QueryResult> value;
                try {
                    if (was_cancelled || job->cancelled(job->context)) {
                        report(&outcome, 4, "operation cancelled before execution");
                    } else {
                        auto* transaction = lbug::transaction::TransactionContext::Get(*connection->getClientContext());
                        if (job->control) {
                            if (job->control == 1) transaction->beginWriteTransaction();
                            else if (job->control == 2) {
                                if (!transaction->hasActiveTransaction())
                                    throw std::runtime_error{"transaction is no longer active"};
                                transaction->commit();
                            } else if (transaction->hasActiveTransaction()) transaction->rollback();
                        } else {
                            if (lease && !transaction->hasActiveTransaction())
                                throw std::runtime_error{"transaction is no longer active"};
                            validate_query(job->query);
                            if (!job->params || job->params->values.empty()) {
                                // query() handles engine-internal expansion (e.g. CREATE_FTS_INDEX).
                                // Raw input was already classified as exactly one user statement.
                                value = connection->query(job->query);
                            } else {
                                prepared = connection->prepareWithParams(job->query, std::move(job->params->values));
                                if (!prepared->isSuccess()) report(&outcome, 3, prepared->getErrorMessage().c_str());
                                else value = connection->executeWithParams(prepared.get(), {});
                            }
                            if (value && !value->isSuccess()) report(&outcome, 3, value->getErrorMessage().c_str());
                        }
                    }
                } catch (const std::exception& exception) {
                    report(&outcome, 3, exception.what());
                } catch (...) {
                    report(&outcome, 3, "unknown engine exception");
                }
                {
                    std::lock_guard lock{mutex};
                    result = std::move(value);
                    rows_read = 0;
                    statement = std::move(prepared);
                    error = outcome;
                    if (lease && outcome.code) lease_failed = true;
                    ready = true;
                }
                int32_t delivered = 0;
                try { delivered = job->complete(job->context, outcome.code); } catch (...) {}
                {
                    std::lock_guard lock{mutex};
                    if (!delivered) discard = true;
                }
                wake.notify_one();
            }
        } catch (...) {
            // Thread infrastructure failure is terminal; never reuse the connection.
            std::optional<Job> failed;
            {
                std::lock_guard lock{mutex};
                stop = true;
                ready = true;
                report(&error, 3, "native worker terminated");
                failed = std::move(pending);
                pending.reset();
            }
            if (failed) {
                try { failed->complete(failed->context, 3); } catch (...) {}
            }
        }
        // A service failure after completion must also respect an existing fetch.
        {
            std::unique_lock lock{mutex};
            wake.wait(lock, [&] { return !fetching; });
        }
        unread_row.reset();
        result.reset();
        statement.reset();
        std::unique_ptr<lbug::main::Connection> retired_connection;
        {
            std::lock_guard lock{mutex};
            retired_connection = std::move(connection);
        }
        retired_connection.reset();
        --live_workers;
        exited.store(true, std::memory_order_release);
    }
};
struct Runtime;
Runtime& runtime();
} // namespace

struct aphid_db {
    std::atomic<uint32_t> refs{1};
    std::atomic<int32_t> state{0}; // opening, ready, retiring, closed
    std::atomic<uint64_t> next{1};
    std::string path;
    std::unique_ptr<lbug::main::Database> engine;
    std::vector<std::unique_ptr<Session>> sessions;
    aphid_db* retirement_next = nullptr;
};

struct aphid_cursor {
    aphid_db* database;
    Session* session;
    std::vector<std::string> names;
    std::vector<lbug::common::LogicalType> types;
    std::shared_ptr<lbug::processor::FlatTuple> row;
    uint64_t rows = 0;
    std::string field_name;
};

namespace {
void unref(aphid_db* db) noexcept {
    if (db->refs.fetch_sub(1, std::memory_order_acq_rel) == 1) delete db;
}

struct Runtime {
    std::mutex mutex;
    std::condition_variable wake;
    std::vector<aphid_db*> databases;
    aphid_db* first = nullptr;
    aphid_db* last = nullptr;
    std::thread cleaner, canceller;
    std::atomic<bool> startup_failed{false};
    std::atomic<bool> healthy{true};

    Runtime() {
        databases.reserve(64);
        cleaner = std::thread{[this] { clean(); }};
        try { canceller = std::thread{[this] { control(); }}; }
        catch (...) {
            startup_failed = true;
            wake.notify_one();
            cleaner.join();
            throw;
        }
    }

    int32_t reserve(aphid_db* db) {
        std::lock_guard lock{mutex};
        for (auto* existing : databases) {
            if (!db->path.empty() && existing->path == db->path)
                return existing->state.load(std::memory_order_acquire) == 2 ? 6 : 2;
        }
        if (databases.size() == 64) return 2;
        databases.push_back(db);
        ++db->refs; // Runtime owns the database through completed retirement.
        ++live_databases;
        return 0;
    }

    void retire(aphid_db* db) {
        int32_t expected = 1;
        if (!db->state.compare_exchange_strong(expected, 2)) return;
        for (auto& session : db->sessions) {
            {
                std::lock_guard lock{session->mutex};
                session->stop = session->cancel = session->discard = true;
            }
            session->wake.notify_one();
        }
        {
            std::lock_guard lock{mutex};
            if (last) last->retirement_next = db;
            else first = db;
            last = db;
        }
        wake.notify_one();
    }

    void control() noexcept try {
        for (;;) {
            {
                std::lock_guard lock{mutex};
                for (auto* db : databases) {
                    const auto state = db->state.load(std::memory_order_acquire);
                    if (state == 1 || state == 2) {
                        for (auto& session : db->sessions) session->interrupt();
                    }
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds{1});
        }
    } catch (...) { healthy = false; }

    void clean() noexcept try {
        for (;;) {
            aphid_db* db;
            {
                std::unique_lock lock{mutex};
                wake.wait(lock, [&] { return first != nullptr || startup_failed.load(); });
                if (startup_failed) return;
                db = first;
                first = db->retirement_next;
                if (!first) last = nullptr;
            }
            bool joined = true;
            for (auto& session : db->sessions) {
                try { if (session->worker.joinable()) session->worker.join(); }
                catch (...) { joined = false; }
            }
            if (!joined) continue; // Quarantine permanently rather than free a live worker.
            for (auto& session : db->sessions) {
                // Also covers open failure before a session's thread was started.
                std::unique_ptr<lbug::main::Connection> connection;
                {
                    std::lock_guard lock{session->mutex};
                    connection = std::move(session->connection);
                }
                connection.reset();
            }
            db->engine.reset();
            {
                std::lock_guard lock{mutex};
                // The session array stays stable until the last resource reference.
                for (auto it = databases.begin(); it != databases.end(); ++it) {
                    if (*it == db) { databases.erase(it); break; }
                }
            }
            --live_databases;
            db->state.store(3, std::memory_order_release);
            unref(db);
        }
    } catch (...) { healthy = false; } // Retained owners remain quarantined.
};

Runtime& runtime() {
    // Fixed VM-lifetime service. NIF anchor pins its code; no threads are detached.
    static auto* service = new Runtime;
    return *service;
}

Session* session_for(aphid_db* db, uint32_t index) noexcept {
    if (!db || db->state.load(std::memory_order_acquire) != 1 || index >= db->sessions.size()) return nullptr;
    return db->sessions[index].get();
}
} // namespace

extern "C" uint32_t aphid_bridge_version(void) try { return 1; } catch (...) { return 0; }

extern "C" aphid_db* aphid_open(const uint8_t* bytes, size_t length, uint32_t count,
    uint32_t threads, aphid_error* error) {
    return aphid_open_configured(bytes, length, count, threads, 64 * 1024 * 1024, error);
}

extern "C" aphid_db* aphid_open_configured(const uint8_t* bytes, size_t length, uint32_t count,
    uint32_t threads, uint64_t buffer_pool_bytes, aphid_error* error) {
    aphid_db* db = nullptr;
    bool registered = false;
    try {
        report(error, 0, "");
        if (length > 4096 || count < 1 || count > 64 || threads < 1 || threads > 64 ||
            buffer_pool_bytes < 64 * 1024 * 1024 || buffer_pool_bytes > 1024ULL * 1024 * 1024)
            throw std::invalid_argument{"invalid native open limits"};
        std::string path{reinterpret_cast<const char*>(bytes), length};
        if (path.find('\0') != std::string::npos) throw std::invalid_argument{"NUL in database path"};
        if (!path.empty()) path = std::filesystem::weakly_canonical(std::filesystem::absolute(path)).string();
        auto owned = std::make_unique<aphid_db>();
        owned->path = path;
        auto& service = runtime();
        if (!service.healthy) { report(error, 3, "native runtime failed; VM restart required"); return nullptr; }
        if (const auto status = service.reserve(owned.get())) {
            report(error, status, status == 6 ? "previous native owner is still retiring" :
                "path reserved or native database capacity reached");
            return nullptr;
        }
        db = owned.release();
        registered = true;
        lbug::main::SystemConfig config{buffer_pool_bytes, threads};
#if defined(APHID_TEST_FAULTS) && defined(APHID_TEST_MAX_DB_SIZE)
        config.maxDBSize = APHID_TEST_MAX_DB_SIZE; // TSan host address-space constraint; test executable only.
#endif
        config.throwOnWalReplayFailure = true;
        db->engine = std::make_unique<lbug::main::Database>(path, config);
        db->sessions.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            auto session = std::make_unique<Session>(db->engine.get());
            auto* pointer = session.get();
            db->sessions.push_back(std::move(session));
            pointer->worker = std::thread{[pointer] { pointer->run(); }};
        }
        db->state.store(1, std::memory_order_release);
        return db;
    } catch (const std::exception& exception) {
        report(error, 1, exception.what());
    } catch (...) { report(error, 1, "unknown native open failure"); }
    if (registered) {
        db->state.store(1, std::memory_order_release);
        aphid_retire(db);
        unref(db);
    }
    return nullptr;
}

extern "C" void aphid_retire(aphid_db* db) try { if (db) runtime().retire(db); } catch (...) {  }
extern "C" void aphid_release(aphid_db* db) try { if (db) { runtime().retire(db); unref(db); } } catch (...) {  }
extern "C" int32_t aphid_closed(aphid_db* db) try { return !db || db->state.load(std::memory_order_acquire) == 3; } catch (...) { return 0; }
extern "C" uint64_t aphid_next_id(aphid_db* db) try { return db->next.fetch_add(1); } catch (...) { return 0; }

extern "C" int32_t aphid_submit(aphid_db* db, uint32_t index, uint64_t id,
    const uint8_t* query, size_t length, void* context, aphid_completion complete,
    aphid_cancelled cancelled, aphid_error* error) {
    auto status = aphid_reserve(db, index, id, error);
    if (status) return status;
    return aphid_submit_params(db, index, id, query, length, nullptr, context, complete, cancelled, error);
}
extern "C" int32_t aphid_reserve(aphid_db* db, uint32_t index, uint64_t id, aphid_error* error) {
    return aphid_reserve_lease(db, index, id, 0, error);
}
extern "C" int32_t aphid_lease_acquire(aphid_db* db, uint32_t index, uint64_t lease, aphid_error* error) try {
    if (!runtime().healthy) { report(error, 3, "native runtime failed; VM restart required"); return 3; }
    auto* session = session_for(db, index);
    if (!session || !lease) { report(error, 2, "invalid transaction lease"); return 2; }
    std::lock_guard lock{session->mutex};
    if (session->busy || session->stop || session->lease) { report(error, 2, "session unavailable"); return 2; }
    session->lease = lease;
    return 0;
} catch (...) { report(error, 3, "native lease acquisition failed"); return 3; }

extern "C" int32_t aphid_lease_release(aphid_db* db, uint32_t index, uint64_t lease) try {
    auto* session = session_for(db, index);
    if (!session || !lease) return 0;
    std::lock_guard lock{session->mutex};
    if (session->lease != lease) return 0;
    session->lease_abandoned = session->cancel = session->discard = true;
    session->wake.notify_one();
    return 1;
} catch (...) { return 0; }

extern "C" int32_t aphid_reserve_lease(aphid_db* db, uint32_t index, uint64_t id,
    uint64_t lease, aphid_error* error) try {
    if (!runtime().healthy) { report(error, 3, "native runtime failed; VM restart required"); return 3; }
    auto* session = session_for(db, index);
    if (!session) { report(error, 2, "database retiring or invalid session"); return 2; }
    std::lock_guard lock{session->mutex};
    if (session->busy || session->stop || session->lease != lease || session->lease_abandoned || session->lease_failed) {
        report(error, 2, "session unavailable or transaction lease stale/failed"); return 2;
    }
    session->busy = true;
    session->id = id;
    return 0;
} catch (...) { report(error, 3, "native reservation failed"); return 3; }

extern "C" int32_t aphid_transaction_control(aphid_db* db, uint32_t index, uint64_t id,
    uint64_t lease, uint32_t control, void* context, aphid_completion complete,
    aphid_cancelled cancelled, aphid_error* error) {
    try {
        if (!lease || control < 1 || control > 3 || !complete || !cancelled) {
            report(error, 1, "invalid transaction control"); return 1;
        }
        auto status = aphid_reserve_lease(db, index, id, lease, error);
        if (status) return status;
        auto* session = session_for(db, index);
        if (!session) { report(error, 2, "database retiring"); return 2; }
        {
            std::lock_guard lock{session->mutex};
            if (session->id != id || session->stop || session->cancel || session->lease_abandoned) {
                report(error, 2, "transaction control cancelled");
                // Release/retirement already requested cleanup of this reservation.
                return 2;
            }
            session->pending = Job{id, {}, context, complete, cancelled, nullptr, control};
        }
        session->wake.notify_one();
        return 0;
    } catch (...) {
        aphid_cancel(db, index, id, 1);
        report(error, 3, "native transaction submission failed"); return 3;
    }
}
extern "C" int32_t aphid_submit_params(aphid_db* db, uint32_t index, uint64_t id,
    const uint8_t* query, size_t length, aphid_params* params, void* context, aphid_completion complete,
    aphid_cancelled cancelled, aphid_error* error) {
    std::unique_ptr<aphid_params> owned{params};
    struct Abandon {
        aphid_db* db; uint32_t session; uint64_t id; bool accepted = false;
        ~Abandon() { if (!accepted) aphid_cancel(db, session, id, 1); }
    } reservation{db, index, id};
    try {
        if (!runtime().healthy) { report(error, 3, "native runtime failed; VM restart required"); return 3; }
        if (length > 1024 * 1024 || !complete || !cancelled) { report(error, 1, "invalid native submission"); return 1; }
        auto* session = session_for(db, index);
        if (!session) { report(error, 2, "database retiring or invalid session"); return 2; }
        Job job{id, std::string{reinterpret_cast<const char*>(query), length}, context, complete, cancelled, std::move(owned)};
        {
            std::lock_guard lock{session->mutex};
            if (!session->busy || session->id != id || session->stop || session->cancel ||
                session->discard || session->pending || session->ready) {
                report(error, 2, "reservation cancelled, stale or unavailable"); return 2;
            }
            session->pending = std::move(job);
            session->id = id;
            session->busy = true;
            session->cancel = cancelled(context) != 0;
            reservation.accepted = true;
        }
        session->wake.notify_one();
        return 0;
    } catch (const std::exception& exception) { report(error, 1, exception.what()); }
    catch (...) { report(error, 1, "unknown native submission failure"); }
    return 1;
}

extern "C" int32_t aphid_cancel(aphid_db* db, uint32_t index, uint64_t id, int32_t abandon) try {
    auto* session = session_for(db, index);
    if (!session) return 0;
    std::lock_guard lock{session->mutex};
    if (!session->busy || session->id != id) return 0;
    session->cancel = true;
    if (abandon) session->discard = true;
    session->wake.notify_one();
    return 1;
} catch (...) { return 0; }

extern "C" int32_t aphid_finish(aphid_db* db, uint32_t index, uint64_t id) try {
    auto* session = session_for(db, index);
    if (!session) return 0;
    std::lock_guard lock{session->mutex};
    if (!session->busy || session->id != id || !session->ready) return 0;
    session->discard = true;
    session->wake.notify_one();
    return 1;
} catch (...) { return 0; }

extern "C" int32_t aphid_session_state(aphid_db* db, uint32_t index) try {
    auto* session = session_for(db, index);
    if (!session) return 3;
    std::lock_guard lock{session->mutex};
    return session->stop ? 3 : session->ready ? 2 : session->busy ? 1 : session->lease ? 4 : 0;
} catch (...) { return 3; }

extern "C" int32_t aphid_operation_error(aphid_db* db, uint32_t index, uint64_t id, aphid_error* error) try {
    auto* session = session_for(db, index);
    if (!session) return 0;
    std::lock_guard lock{session->mutex};
    if (session->id != id || !session->ready) return 0;
    *error = session->error;
    return 1;
} catch (...) { return 0; }
extern "C" int32_t aphid_transferring(aphid_db* db, uint32_t index, uint64_t id) try {
    auto* session = session_for(db, index);
    if (!session) return 0;
    std::lock_guard lock{session->mutex};
    return session->id == id && session->fetching;
} catch (...) { return 0; }
extern "C" uint32_t aphid_live_databases(void) try { return live_databases.load(); } catch (...) { return 0; }
extern "C" uint32_t aphid_live_workers(void) try { return live_workers.load(); } catch (...) { return 0; }

extern "C" aphid_cursor* aphid_fetch_begin(aphid_db* db, uint32_t index, uint64_t id,
    aphid_error* error) {
    aphid_cursor* cursor = nullptr;
    try {
        auto* session = session_for(db, index);
        if (!session) { report(error, 2, "database retiring or invalid session"); return nullptr; }
        auto owned = std::make_unique<aphid_cursor>();
        owned->database = db;
        owned->session = session;
        {
            std::lock_guard lock{session->mutex};
            if (session->id != id || !session->ready || session->stop || session->discard ||
                session->fetching || session->error.code || !session->result) {
                report(error, 2, "result unavailable or already being fetched");
                return nullptr;
            }
            session->fetching = true;
            db->refs.fetch_add(1, std::memory_order_relaxed);
        }
        cursor = owned.release();
        // Only metadata is copied; rows and values remain owned by the engine.
        if (session->result->getNumColumns() > 4096) throw std::length_error{"column limit exceeded"};
        cursor->names = session->result->getColumnNames();
        cursor->types = session->result->getColumnDataTypes();
        cursor->rows = session->result->getNumTuples();
        return cursor;
    } catch (const std::exception& exception) { report(error, 3, exception.what()); }
    catch (...) { report(error, 3, "unknown result acquisition failure"); }
    aphid_fetch_end(cursor);
    return nullptr;
}

extern "C" void aphid_fetch_end(aphid_cursor* cursor) try {
    if (!cursor) return;
    auto* session = cursor->session;
    auto* db = cursor->database;
    delete cursor; // Release row/metadata before permitting result destruction.
    {
        std::lock_guard lock{session->mutex};
        session->fetching = false;
    }
    session->wake.notify_one();
    unref(db);
} catch (...) { /* If control synchronization fails, retain/quarantine the owner. */ }

extern "C" uint64_t aphid_fetch_columns(const aphid_cursor* cursor) try {
    return cursor->names.size();
} catch (...) { return 0; }
extern "C" uint64_t aphid_fetch_rows(const aphid_cursor* cursor) try {
    return cursor->rows;
} catch (...) { return 0; }
extern "C" uint64_t aphid_fetch_position(const aphid_cursor* cursor) try {
    return cursor->session->rows_read;
} catch (...) { return 0; }
extern "C" int32_t aphid_fetch_unread(aphid_cursor* cursor) try {
    if (!cursor->row || cursor->session->unread_row || !cursor->session->rows_read) return 0;
    cursor->session->unread_row = std::move(cursor->row);
    --cursor->session->rows_read;
    return 1;
} catch (...) { return 0; }
extern "C" int32_t aphid_fetch_column(const aphid_cursor* cursor, uint64_t index,
    aphid_bytes* name, const aphid_type** type) try {
    if (index >= cursor->names.size() || index >= cursor->types.size()) return 0;
    const auto& text = cursor->names[index];
    *name = {reinterpret_cast<const uint8_t*>(text.data()), text.size()};
    *type = reinterpret_cast<const aphid_type*>(&cursor->types[index]);
    return 1;
} catch (...) { return 0; }
extern "C" int32_t aphid_fetch_next(aphid_cursor* cursor, aphid_error* error) {
    try {
        cursor->row.reset();
        if (cursor->session->unread_row) {
            cursor->row = std::move(cursor->session->unread_row);
        } else {
            if (!cursor->session->result->hasNext()) return 0;
            cursor->row = cursor->session->result->getNext();
        }
        ++cursor->session->rows_read;
        return 1;
    } catch (const std::exception& exception) { report(error, 3, exception.what()); }
    catch (...) { report(error, 3, "unknown result fetch failure"); }
    return -1;
}
extern "C" const aphid_value* aphid_fetch_value(const aphid_cursor* cursor, uint64_t index) try {
    if (!cursor->row || index >= cursor->row->len()) return nullptr;
    return reinterpret_cast<const aphid_value*>(cursor->row->getValue(index));
} catch (...) { return nullptr; }

extern "C" int32_t aphid_type_inspect(const aphid_type* opaque, aphid_type_info* out,
    aphid_error* error) {
    try {
        using namespace lbug::common;
        const auto& type = *reinterpret_cast<const LogicalType*>(opaque);
        *out = {static_cast<uint32_t>(type.getLogicalTypeID()), 0, 0, 0};
        switch (type.getLogicalTypeID()) {
        case LogicalTypeID::DECIMAL:
            out->aux1 = DecimalType::getPrecision(type); out->aux2 = DecimalType::getScale(type); break;
        case LogicalTypeID::ARRAY:
            out->aux1 = ArrayType::getNumElements(type); out->children = 1; break;
        case LogicalTypeID::LIST: out->children = 1; break;
        case LogicalTypeID::MAP: out->children = 2; break;
        case LogicalTypeID::STRUCT: case LogicalTypeID::NODE: case LogicalTypeID::REL:
        case LogicalTypeID::RECURSIVE_REL: out->children = StructType::getNumFields(type); break;
        case LogicalTypeID::ANY: case LogicalTypeID::UNION: case LogicalTypeID::POINTER:
            report(error, 5, "unsupported logical type"); return 5;
        default: break; // Zig rejects unknown tags against its static type table.
        }
        return 0;
    } catch (const std::exception& exception) { report(error, 3, exception.what()); }
    catch (...) { report(error, 3, "unknown type inspection failure"); }
    return 3;
}

extern "C" int32_t aphid_type_child(aphid_cursor* cursor, const aphid_type* opaque, uint64_t index,
    const aphid_type** child, aphid_bytes* name, aphid_error* error) {
    try {
        using namespace lbug::common;
        const auto& type = *reinterpret_cast<const LogicalType*>(opaque);
        aphid_type_info info{};
        auto status = aphid_type_inspect(opaque, &info, error);
        if (status) return status;
        if (index >= info.children) { report(error, 1, "type child out of range"); return 1; }
        const LogicalType* value = nullptr;
        if (cursor) cursor->field_name.clear();
        switch (type.getLogicalTypeID()) {
        case LogicalTypeID::LIST: value = &ListType::getChildType(type); break;
        case LogicalTypeID::ARRAY: value = &ArrayType::getChildType(type); break;
        case LogicalTypeID::MAP: value = index == 0 ? &MapType::getKeyType(type) : &MapType::getValueType(type); break;
        default:
            value = &StructType::getFieldType(type, index);
            if (cursor) cursor->field_name = StructType::getField(type, index).getName();
        }
        *child = reinterpret_cast<const aphid_type*>(value);
        *name = cursor ? aphid_bytes{reinterpret_cast<const uint8_t*>(cursor->field_name.data()), cursor->field_name.size()} : aphid_bytes{};
        return 0;
    } catch (const std::exception& exception) { report(error, 3, exception.what()); }
    catch (...) { report(error, 3, "unknown type child failure"); }
    return 3;
}

extern "C" int32_t aphid_value_inspect(const aphid_value* opaque, aphid_value_info* out,
    aphid_error* error) {
    try {
        using namespace lbug::common;
        const auto& value = *reinterpret_cast<const Value*>(opaque);
        *out = {};
        out->type = reinterpret_cast<const aphid_type*>(&value.getDataType());
        aphid_type_info type{};
        auto status = aphid_type_inspect(out->type, &type, error);
        if (status) return status;
        out->is_null = value.isNull();
        if (out->is_null) return 0;
        switch (value.getDataType().getLogicalTypeID()) {
        case LogicalTypeID::STRING: case LogicalTypeID::BLOB: case LogicalTypeID::JSON: case LogicalTypeID::UUID:
            // strVal is a public engine byte buffer. Its use stays entirely in C++.
            out->bytes = {reinterpret_cast<const uint8_t*>(value.strVal.data()), value.strVal.size()};
            return 0;
        default: break;
        }
        auto signed_bits = [&](int64_t number) {
            out->low = static_cast<uint64_t>(number); out->high = number < 0 ? UINT64_MAX : 0;
        };
        switch (value.getDataType().getPhysicalType()) {
        case PhysicalTypeID::BOOL: out->low = value.getValue<bool>(); break;
        case PhysicalTypeID::INT8: signed_bits(value.getValue<int8_t>()); break;
        case PhysicalTypeID::INT16: signed_bits(value.getValue<int16_t>()); break;
        case PhysicalTypeID::INT32: signed_bits(value.getValue<int32_t>()); break;
        case PhysicalTypeID::INT64: signed_bits(value.getValue<int64_t>()); break;
        case PhysicalTypeID::INT128: {
            auto number = value.getValue<int128_t>();
            out->low = number.low; out->high = static_cast<uint64_t>(number.high); break;
        }
        case PhysicalTypeID::UINT8: out->low = value.getValue<uint8_t>(); break;
        case PhysicalTypeID::UINT16: out->low = value.getValue<uint16_t>(); break;
        case PhysicalTypeID::UINT32: out->low = value.getValue<uint32_t>(); break;
        case PhysicalTypeID::UINT64: out->low = value.getValue<uint64_t>(); break;
        case PhysicalTypeID::UINT128: {
            auto number = value.getValue<uint128_t>(); out->low = number.low; out->high = number.high; break;
        }
        case PhysicalTypeID::FLOAT: out->real = value.getValue<float>(); break;
        case PhysicalTypeID::DOUBLE: out->real = value.getValue<double>(); break;
        case PhysicalTypeID::INTERVAL: {
            auto interval = value.getValue<interval_t>();
            out->months = interval.months; out->days = interval.days; signed_bits(interval.micros); break;
        }
        case PhysicalTypeID::INTERNAL_ID: {
            auto id = value.getValue<internalID_t>(); out->low = id.offset; out->high = id.tableID; break;
        }
        case PhysicalTypeID::LIST: case PhysicalTypeID::ARRAY: case PhysicalTypeID::STRUCT:
            out->children = NestedVal::getChildrenSize(&value); break;
        default: report(error, 5, "unsupported physical value type"); return 5;
        }
        return 0;
    } catch (const std::exception& exception) { report(error, 3, exception.what()); }
    catch (...) { report(error, 3, "unknown value inspection failure"); }
    return 3;
}
extern "C" const aphid_value* aphid_value_child(const aphid_value* opaque, uint64_t index) try {
    const auto* value = reinterpret_cast<const lbug::common::Value*>(opaque);
    if (value->isNull() || index >= lbug::common::NestedVal::getChildrenSize(value)) return nullptr;
    return reinterpret_cast<const aphid_value*>(lbug::common::NestedVal::getChildVal(value, index));
} catch (...) { return nullptr; }

extern "C" aphid_type* aphid_type_make(uint32_t tag, uint64_t aux1, uint64_t aux2,
    const aphid_type* const* children, const aphid_bytes* names, size_t count, aphid_error* error) {
    try {
        using namespace lbug::common;
        if (count > 131072) throw std::invalid_argument{"too many type children"};
        auto child = [&](size_t i) -> const LogicalType& {
            if (i >= count || !children || !children[i]) throw std::invalid_argument{"missing child type"};
            return *reinterpret_cast<const LogicalType*>(children[i]);
        };
        LogicalType type;
        switch (tag) {
        case 41:
            if (count || aux1 < 1 || aux1 > 38 || aux2 > aux1) throw std::invalid_argument{"invalid decimal precision/scale"};
            type = LogicalType::DECIMAL(aux1, aux2); break;
        case 52:
            if (count != 1) throw std::invalid_argument{"list requires one child type"};
            type = LogicalType::LIST(child(0).copy()); break;
        case 53:
            if (count != 1 || aux1 == 0 || aux1 > 131072) throw std::invalid_argument{"invalid array length"};
            type = LogicalType::ARRAY(child(0).copy(), aux1); break;
        case 55:
            if (count != 2) throw std::invalid_argument{"map requires key/value types"};
            type = LogicalType::MAP(child(0).copy(), child(1).copy()); break;
        case 54: {
            std::vector<StructField> fields;
            std::unordered_set<std::string> seen;
            fields.reserve(count);
            for (size_t i = 0; i < count; ++i) {
                if (!names) throw std::invalid_argument{"missing struct names"};
                std::string name{reinterpret_cast<const char*>(names[i].data), names[i].length};
                if (!seen.insert(name).second) throw std::invalid_argument{"duplicate struct field"};
                fields.emplace_back(std::move(name), child(i).copy());
            }
            type = LogicalType::STRUCT(std::move(fields)); break;
        }
        default:
            if (count || !((tag >= 22 && tag <= 40) || tag == 43 || tag == 50 || tag == 51 || tag == 59 || tag == 60))
                throw std::invalid_argument{"unsupported input type"};
            type = LogicalType{static_cast<LogicalTypeID>(tag)};
        }
        return reinterpret_cast<aphid_type*>(new LogicalType(std::move(type)));
    } catch (const std::exception& exception) { report(error, 1, exception.what()); }
    catch (...) { report(error, 1, "unknown input type failure"); }
    return nullptr;
}
extern "C" void aphid_type_free(aphid_type* type) try {
    delete reinterpret_cast<lbug::common::LogicalType*>(type);
} catch (...) {}
extern "C" void aphid_value_free(aphid_value* value) try {
    delete reinterpret_cast<lbug::common::Value*>(value);
} catch (...) {}

namespace {
struct KeyHash {
    size_t operator()(const lbug::common::Value* value) const {
        aphid_value_info info{};
        aphid_error error{};
        if (aphid_value_inspect(reinterpret_cast<const aphid_value*>(value), &info, &error))
            throw std::invalid_argument{"unsupported map key"};
        if (info.is_null) return 0;
        size_t hash = 0;
        auto combine = [&](size_t part) { hash ^= part + 0x9e3779b9 + (hash << 6) + (hash >> 2); };
        combine(std::hash<uint64_t>{}(info.low)); combine(std::hash<uint64_t>{}(info.high));
        combine(std::hash<int32_t>{}(info.months)); combine(std::hash<int32_t>{}(info.days));
        combine(std::hash<double>{}(info.real));
        if (info.bytes.length) combine(std::hash<std::string_view>{}({reinterpret_cast<const char*>(info.bytes.data), info.bytes.length}));
        for (uint64_t i = 0; i < info.children; ++i) combine((*this)(lbug::common::NestedVal::getChildVal(value, i)));
        return hash;
    }
};
struct KeyEqual {
    bool operator()(const lbug::common::Value* left, const lbug::common::Value* right) const {
        if (left->getDataType() != right->getDataType()) return false;
        // The engine's operator== reads scalar storage even for two typed nulls.
        if (left->isNull() || right->isNull()) return left->isNull() == right->isNull();
        auto size = lbug::common::NestedVal::getChildrenSize(left);
        if (size != lbug::common::NestedVal::getChildrenSize(right)) return false;
        if (!size) return *left == *right;
        for (uint32_t i = 0; i < size; ++i)
            if (!(*this)(lbug::common::NestedVal::getChildVal(left, i), lbug::common::NestedVal::getChildVal(right, i))) return false;
        return true;
    }
};
}

extern "C" aphid_value* aphid_value_make(const aphid_type* opaque, const aphid_value_info* scalar,
    aphid_value** children, size_t count, aphid_error* error) {
    struct Consume {
        aphid_value** children; size_t count;
        ~Consume() { for (size_t i = 0; i < count; ++i) { aphid_value_free(children[i]); children[i] = nullptr; } }
    } consume{children, count};
    try {
        using namespace lbug::common;
        const auto& type = *reinterpret_cast<const LogicalType*>(opaque);
        if (count > 131072) throw std::invalid_argument{"too many value children"};
        if (scalar->is_null) {
            if (count) throw std::invalid_argument{"null value has children"};
            return reinterpret_cast<aphid_value*>(new Value(Value::createNullValue(type)));
        }
        auto tag = type.getLogicalTypeID();
        if (tag == LogicalTypeID::LIST || tag == LogicalTypeID::ARRAY || tag == LogicalTypeID::STRUCT || tag == LogicalTypeID::MAP) {
            if (tag == LogicalTypeID::ARRAY && count != ArrayType::getNumElements(type)) throw std::invalid_argument{"array length mismatch"};
            if (tag == LogicalTypeID::STRUCT && count != StructType::getNumFields(type)) throw std::invalid_argument{"struct width mismatch"};
            std::vector<std::unique_ptr<Value>> values;
            std::unordered_set<const Value*, KeyHash, KeyEqual> keys;
            values.reserve(count);
            if (tag == LogicalTypeID::MAP) {
                if (count % 2) throw std::invalid_argument{"map requires key/value pairs"};
                for (size_t i = 0; i < count; i += 2) {
                    auto* key = reinterpret_cast<Value*>(children[i]);
                    auto* item = reinterpret_cast<Value*>(children[i + 1]);
                    if (!key || key->isNull() || key->getDataType() != MapType::getKeyType(type) ||
                        !item || item->getDataType() != MapType::getValueType(type)) throw std::invalid_argument{"invalid map key/value type"};
                    if (!keys.insert(key).second) throw std::invalid_argument{"duplicate map key"};
                    std::vector<std::unique_ptr<Value>> pair;
                    pair.reserve(2);
                    pair.emplace_back(key); children[i] = nullptr;
                    pair.emplace_back(item); children[i + 1] = nullptr;
                    values.push_back(std::make_unique<Value>(ListType::getChildType(type).copy(), std::move(pair)));
                }
                return reinterpret_cast<aphid_value*>(new Value(type.copy(), std::move(values)));
            }
            for (size_t i = 0; i < count; ++i) {
                auto* value = reinterpret_cast<Value*>(children[i]);
                const auto& expected = tag == LogicalTypeID::STRUCT ? StructType::getFieldType(type, i) :
                    tag == LogicalTypeID::ARRAY ? ArrayType::getChildType(type) : ListType::getChildType(type);
                if (!value || value->getDataType() != expected) throw std::invalid_argument{"child type mismatch"};
                values.emplace_back(value);
                children[i] = nullptr;
            }
            return reinterpret_cast<aphid_value*>(new Value(type.copy(), std::move(values)));
        }
        if (count) throw std::invalid_argument{"scalar value has children"};
        auto value = std::make_unique<Value>(Value::createDefaultValue(type));
        auto signed_number = [&]() -> int64_t {
            const auto number = static_cast<int64_t>(scalar->low);
            if (scalar->high != (number < 0 ? UINT64_MAX : 0)) throw std::invalid_argument{"integer overflow"};
            return number;
        };
        auto check_signed = [&](unsigned bits) -> int64_t {
            auto number = signed_number();
            if (bits < 64 && (number < -(int64_t{1} << (bits - 1)) || number >= (int64_t{1} << (bits - 1))))
                throw std::invalid_argument{"signed integer overflow"};
            return number;
        };
        auto check_unsigned = [&](unsigned bits) -> uint64_t {
            if (scalar->high || (bits < 64 && scalar->low >= (uint64_t{1} << bits))) throw std::invalid_argument{"unsigned integer overflow"};
            return scalar->low;
        };
        if (tag == LogicalTypeID::UUID) {
            *value = Value(uuid{UUID::fromCString(reinterpret_cast<const char*>(scalar->bytes.data), scalar->bytes.length)});
        } else if (tag == LogicalTypeID::STRING || tag == LogicalTypeID::BLOB || tag == LogicalTypeID::JSON) {
            value->strVal.assign(reinterpret_cast<const char*>(scalar->bytes.data), scalar->bytes.length);
            if (tag == LogicalTypeID::JSON) { auto checked = lbug::json_extension::stringToJson(value->strVal); }
        } else {
            if (tag == LogicalTypeID::DECIMAL) {
                // Compare unsigned magnitude directly, including INT128 minimum.
                unsigned __int128 bits = (static_cast<unsigned __int128>(scalar->high) << 64) | scalar->low;
                auto magnitude = scalar->high >> 63 ? (~bits) + 1 : bits;
                unsigned __int128 limit = 1;
                for (uint32_t i = 0; i < DecimalType::getPrecision(type); ++i) limit *= 10;
                if (magnitude >= limit) throw std::invalid_argument{"decimal coefficient exceeds precision"};
            }
            switch (type.getPhysicalType()) {
            case PhysicalTypeID::BOOL:
                if (scalar->high || scalar->low > 1) throw std::invalid_argument{"invalid boolean"};
                value->val.booleanVal = scalar->low; break;
            case PhysicalTypeID::INT8: value->val.int8Val = check_signed(8); break;
            case PhysicalTypeID::INT16: value->val.int16Val = check_signed(16); break;
            case PhysicalTypeID::INT32: value->val.int32Val = check_signed(32); break;
            case PhysicalTypeID::INT64: value->val.int64Val = check_signed(64); break;
            case PhysicalTypeID::INT128: value->val.int128Val = int128_t{scalar->low, static_cast<int64_t>(scalar->high)}; break;
            case PhysicalTypeID::UINT8: value->val.uint8Val = check_unsigned(8); break;
            case PhysicalTypeID::UINT16: value->val.uint16Val = check_unsigned(16); break;
            case PhysicalTypeID::UINT32: value->val.uint32Val = check_unsigned(32); break;
            case PhysicalTypeID::UINT64: value->val.uint64Val = check_unsigned(64); break;
            case PhysicalTypeID::UINT128: value->val.uint128Val = uint128_t{scalar->low, scalar->high}; break;
            case PhysicalTypeID::FLOAT:
                value->val.floatVal = static_cast<float>(scalar->real);
                if (!std::isfinite(value->val.floatVal)) throw std::invalid_argument{"nonfinite FLOAT"};
                break;
            case PhysicalTypeID::DOUBLE:
                if (!std::isfinite(scalar->real)) throw std::invalid_argument{"nonfinite DOUBLE"};
                value->val.doubleVal = scalar->real; break;
            case PhysicalTypeID::INTERVAL:
                value->val.intervalVal = interval_t{scalar->months, scalar->days, signed_number()}; break;
            default: throw std::invalid_argument{"unsupported input value"};
            }
        }
        return reinterpret_cast<aphid_value*>(value.release());
    } catch (const std::exception& exception) { report(error, 1, exception.what()); }
    catch (...) { report(error, 1, "unknown input value failure"); }
    return nullptr;
}
extern "C" aphid_params* aphid_params_new(aphid_error* error) {
    try { return new aphid_params; }
    catch (...) { report(error, 1, "parameter allocation failed"); return nullptr; }
}
extern "C" int32_t aphid_params_add(aphid_params* params, aphid_bytes name,
    aphid_value* opaque, aphid_error* error) {
    std::unique_ptr<lbug::common::Value> value{reinterpret_cast<lbug::common::Value*>(opaque)};
    try {
        if (!value || name.length == 0 || name.length > 1024 * 1024 || name.data[0] == '$' || params->values.size() >= 131072)
            throw std::invalid_argument{"invalid parameter name/count/value"};
        std::string key{reinterpret_cast<const char*>(name.data), name.length};
        if (!params->values.emplace(std::move(key), std::move(value)).second) throw std::invalid_argument{"duplicate parameter name"};
        return 0;
    } catch (const std::exception& exception) { report(error, 1, exception.what()); }
    catch (...) { report(error, 1, "unknown parameter insertion failure"); }
    return 1;
}
extern "C" void aphid_params_free(aphid_params* params) try { delete params; } catch (...) {}
