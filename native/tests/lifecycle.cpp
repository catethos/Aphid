// Compile the same bridge with a test-only fault hook; no hook is exported by the library.
#define APHID_TEST_FAULTS
#include "../bridge.cpp"
#include <iostream>
#include <source_location>

struct Completion {
    std::atomic<int> status{-1};
    bool deliver = true;
    bool throws = false;
};
static int32_t completed(void* context, int32_t status) {
    auto& completion = *static_cast<Completion*>(context);
    completion.status = status;
    if (completion.throws) throw std::runtime_error{"injected callback failure"};
    return completion.deliver;
}
static int32_t cancelled(void*) { return 0; }
static void require(bool value, std::source_location location = std::source_location::current()) {
    if (!value) throw std::runtime_error{"native lifecycle assertion at line " + std::to_string(location.line())};
}
template<class F> static void eventually(F check) {
    for (int i = 0; i < 1000; ++i) {
        if (check()) return;
        std::this_thread::sleep_for(std::chrono::milliseconds{2});
    }
    throw std::runtime_error{"native lifecycle deadline"};
}

static void parameter_cases(aphid_db* db) {
    aphid_error error{};
    for (uint32_t tag : {22u, 23u, 24u, 25u, 26u, 27u, 28u, 29u, 30u, 31u, 32u, 33u,
                        34u, 35u, 36u, 37u, 38u, 39u, 40u, 41u, 43u, 50u, 51u, 59u, 60u}) {
        auto* type = aphid_type_make(tag, tag == 41 ? 38 : 0, tag == 41 ? 4 : 0, nullptr, nullptr, 0, &error);
        require(type != nullptr);
        aphid_value_info input{};
        input.low = tag == 22 ? 1 : tag == 38 ? 123456789 : 123;
        input.real = 0.125;
        input.months = 2; input.days = 3;
        std::string bytes = tag == 59 ? "550e8400-e29b-41d4-a716-446655440000" :
            tag == 60 ? "{\"n\":12345678901234567890}" : std::string{"a\0b", 3};
        input.bytes = {reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()};
        auto* value = aphid_value_make(type, &input, nullptr, 0, &error);
        require(value != nullptr);
        auto* params = aphid_params_new(&error);
        require(params && aphid_params_add(params, {reinterpret_cast<const uint8_t*>("n"), 1}, value, &error) == 0);
        aphid_type_free(type);
        Completion completion;
        auto id = aphid_next_id(db);
        const std::string query = "RETURN $n AS n";
        require(aphid_reserve(db, 0, id, &error) == 0);
        require(aphid_submit_params(db, 0, id, reinterpret_cast<const uint8_t*>(query.data()), query.size(),
            params, &completion, completed, cancelled, &error) == 0);
        eventually([&] { return completion.status.load() >= 0; });
        if (completion.status != 0) {
            aphid_operation_error(db, 0, id, &error);
            throw std::runtime_error{"parameter tag " + std::to_string(tag) + ": " + error.message};
        }
        auto* cursor = aphid_fetch_begin(db, 0, id, &error);
        require(cursor && aphid_fetch_next(cursor, &error) == 1);
        aphid_value_info output{};
        require(aphid_value_inspect(aphid_fetch_value(cursor, 0), &output, &error) == 0);
        aphid_type_info metadata{};
        require(aphid_type_inspect(output.type, &metadata, &error) == 0 && metadata.tag == tag);
        if (tag == 50 || tag == 51 || tag == 59 || tag == 60) {
            require(std::string(reinterpret_cast<const char*>(output.bytes.data), output.bytes.length) == bytes);
        } else if (tag == 32 || tag == 33) {
            require(output.real == input.real);
        } else {
            require(output.low == input.low && output.high == input.high);
            if (tag == 40) require(output.months == 2 && output.days == 3);
        }
        aphid_fetch_end(cursor);
        require(aphid_finish(db, 0, id));
        eventually([&] { return aphid_session_state(db, 0) == 0; });
    }
    auto* tiny = aphid_type_make(26, 0, 0, nullptr, nullptr, 0, &error);
    aphid_value_info too_large{};
    too_large.low = 128;
    require(!aphid_value_make(tiny, &too_large, nullptr, 0, &error));
    aphid_type_free(tiny);
    auto* json = aphid_type_make(60, 0, 0, nullptr, nullptr, 0, &error);
    aphid_value_info invalid_json{};
    invalid_json.bytes = {reinterpret_cast<const uint8_t*>("{"), 1};
    require(!aphid_value_make(json, &invalid_json, nullptr, 0, &error));
    aphid_type_free(json);

    auto* number = aphid_type_make(32, 0, 0, nullptr, nullptr, 0, &error);
    const aphid_type* members[] = {number, number};
    auto* map = aphid_type_make(55, 0, 0, members, nullptr, 2, &error);
    require(number && map);
    aphid_value_info zero{};
    aphid_value_info minus_zero{}; minus_zero.real = -0.0;
    aphid_value* pairs[] = {
        aphid_value_make(number, &zero, nullptr, 0, &error),
        aphid_value_make(number, &zero, nullptr, 0, &error),
        aphid_value_make(number, &minus_zero, nullptr, 0, &error),
        aphid_value_make(number, &zero, nullptr, 0, &error)
    };
    require(!aphid_value_make(map, &zero, pairs, 4, &error));
    for (auto* consumed : pairs) require(consumed == nullptr);
    require(std::string{error.message} == "duplicate map key");
    aphid_type_free(map); aphid_type_free(number);
    auto roundtrip = [&](aphid_value* input) {
        require(input != nullptr);
        auto expected = reinterpret_cast<lbug::common::Value*>(input)->copy();
        auto* params = aphid_params_new(&error);
        require(params && aphid_params_add(params, {reinterpret_cast<const uint8_t*>("n"), 1}, input, &error) == 0);
        Completion completion;
        auto id = aphid_next_id(db);
        const std::string query = "RETURN $n";
        require(aphid_reserve(db, 0, id, &error) == 0);
        require(aphid_submit_params(db, 0, id, reinterpret_cast<const uint8_t*>(query.data()), query.size(),
            params, &completion, completed, cancelled, &error) == 0);
        eventually([&] { return completion.status.load() >= 0; });
        if (completion.status != 0) {
            aphid_operation_error(db, 0, id, &error);
            throw std::runtime_error{error.message};
        }
        auto* cursor = aphid_fetch_begin(db, 0, id, &error);
        require(cursor && aphid_fetch_next(cursor, &error) == 1);
        require(KeyEqual{}(expected.get(), reinterpret_cast<const lbug::common::Value*>(aphid_fetch_value(cursor, 0))));
        aphid_fetch_end(cursor);
        require(aphid_finish(db, 0, id));
        eventually([&] { return aphid_session_state(db, 0) == 0; });
    };
    auto* integer = aphid_type_make(23, 0, 0, nullptr, nullptr, 0, &error);
    const aphid_type* integer_children[] = {integer, integer};
    auto* list = aphid_type_make(52, 0, 0, integer_children, nullptr, 1, &error);
    auto* array = aphid_type_make(53, 2, 0, integer_children, nullptr, 1, &error);
    auto* integer_map = aphid_type_make(55, 0, 0, integer_children, nullptr, 2, &error);
    aphid_value_info null{}; null.is_null = 1;
    aphid_value_info one{}; one.low = 1;
    for (auto* type : {list, array}) {
        require(type != nullptr);
        aphid_value* items[] = {aphid_value_make(integer, &null, nullptr, 0, &error),
                               aphid_value_make(integer, &one, nullptr, 0, &error)};
        roundtrip(aphid_value_make(type, &zero, items, 2, &error));
        require(!items[0] && !items[1]);
    }
    roundtrip(aphid_value_make(list, &zero, nullptr, 0, &error));
    aphid_value* entry[] = {aphid_value_make(integer, &one, nullptr, 0, &error),
                           aphid_value_make(integer, &null, nullptr, 0, &error)};
    roundtrip(aphid_value_make(integer_map, &zero, entry, 2, &error));
    const aphid_type* fields[] = {integer, list};
    const aphid_bytes names[] = {{reinterpret_cast<const uint8_t*>("id"), 2},
                                 {reinterpret_cast<const uint8_t*>("nested"), 6}};
    auto* structure = aphid_type_make(54, 0, 0, fields, names, 2, &error);
    aphid_value* field_values[] = {aphid_value_make(integer, &null, nullptr, 0, &error),
                                  aphid_value_make(list, &zero, nullptr, 0, &error)};
    roundtrip(aphid_value_make(structure, &zero, field_values, 2, &error));
    for (auto* type : {integer, list, array, integer_map, structure}) aphid_type_free(type);
    std::cout << "prepared parameter scalar types, raw timestamp units, bytes and integer overflow passed\n";
    std::cout << "typed empty/null nested parameters, JSON validation and duplicate map keys passed\n";
}

static void transaction_engine_cases(aphid_db* db) {
    lbug::main::Connection writer{db->engine.get()}, reader{db->engine.get()};
    auto query = [](auto& connection, const char* text) {
        auto result = connection.query(text);
        if (!result->isSuccess()) throw std::runtime_error{result->getErrorMessage()};
        return result;
    };
    auto count = [&] {
        auto result = query(reader, "MATCH (n:TransactionProbe) RETURN count(*)");
        return result->getNext()->getValue(0)->template getValue<int64_t>();
    };
    query(writer, "CREATE NODE TABLE TransactionProbe(id INT64, PRIMARY KEY(id))");
    query(writer, "BEGIN TRANSACTION");
    query(writer, "CREATE (:TransactionProbe {id: 1})");
    require(count() == 0);
    query(writer, "ROLLBACK");
    require(count() == 0);
    query(writer, "BEGIN TRANSACTION");
    query(writer, "CREATE (:TransactionProbe {id: 1})");
    query(writer, "COMMIT");
    require(count() == 1);
    {
        lbug::main::Connection abandoned{db->engine.get()};
        query(abandoned, "BEGIN TRANSACTION");
        query(abandoned, "CREATE (:TransactionProbe {id: 2})");
    }
    require(count() == 1); // Connection destruction rolls back the active transaction.
    query(writer, "BEGIN TRANSACTION");
    query(writer, "CREATE (:TransactionProbe {id: 3})");
    auto failed = writer.query("CREATE (:TransactionProbe {id: 1})");
    require(!failed->isSuccess());
    failed.reset();
    require(count() == 1); // Execution error already rolled back id 3.
    require(!writer.query("COMMIT")->isSuccess());
    query(writer, "CREATE (:TransactionProbe {id: 4})");
    require(count() == 2); // Without a lease failure guard, the next query autocommits.
    std::cout << "engine transaction visibility, commit, rollback, destructor rollback and failure/autocommit semantics passed\n";
}

static void transaction_lease_cases(aphid_db* db) {
    aphid_error error{};
    lbug::main::Connection reader{db->engine.get()};
    require(reader.query("CREATE NODE TABLE LeaseProbe(id INT64, PRIMARY KEY(id))")->isSuccess());
    auto count = [&] {
        auto result = reader.query("MATCH (n:LeaseProbe) RETURN count(*)");
        require(result->isSuccess());
        return result->getNext()->getValue(0)->getValue<int64_t>();
    };
    auto acquire = [&] {
        auto lease = aphid_next_id(db);
        require(aphid_lease_acquire(db, 0, lease, &error) == 0);
        require(aphid_session_state(db, 0) == 4);
        require(aphid_reserve(db, 0, aphid_next_id(db), &error) == 2);
        return lease;
    };
    auto finish = [&](uint64_t id, Completion& completion) {
        eventually([&] { return completion.status.load() >= 0; });
        auto status = completion.status.load();
        require(aphid_finish(db, 0, id));
        eventually([&] { return aphid_session_state(db, 0) == 4; });
        return status;
    };
    auto control = [&](uint64_t lease, uint32_t action) {
        Completion completion;
        auto id = aphid_next_id(db);
        require(aphid_transaction_control(db, 0, id, lease, action,
            &completion, completed, cancelled, &error) == 0);
        return finish(id, completion);
    };
    auto query = [&](uint64_t lease, const char* text) {
        Completion completion;
        auto id = aphid_next_id(db);
        require(aphid_reserve_lease(db, 0, id, lease, &error) == 0);
        require(aphid_submit_params(db, 0, id, reinterpret_cast<const uint8_t*>(text),
            std::strlen(text), nullptr, &completion, completed, cancelled, &error) == 0);
        return finish(id, completion);
    };
    auto release = [&](uint64_t lease) {
        require(aphid_lease_release(db, 0, lease));
        eventually([&] { return aphid_session_state(db, 0) == 0; });
    };
    auto lease = acquire();
    require(aphid_reserve_lease(db, 0, aphid_next_id(db), lease + 100, &error) == 2);
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 1})") == 0);
    require(count() == 0);
    release(lease); // Abandonment rolls back on the owning native worker.
    require(count() == 0);
    auto previous = lease;
    lease = acquire();
    require(!aphid_lease_release(db, 0, previous));
    require(aphid_session_state(db, 0) == 4);
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 2})") == 0);
    require(control(lease, 2) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 99})") != 0); // No work after commit.
    release(lease);
    require(count() == 1);
    lease = acquire();
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 3})") == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 2})") != 0);
    require(aphid_reserve_lease(db, 0, aphid_next_id(db), lease, &error) == 2);
    release(lease);
    require(count() == 1);
    lease = acquire();
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 4})") == 0);
    require(control(lease, 3) == 0);
    release(lease);
    require(count() == 1);
    lease = acquire();
    require(control(lease, 1) == 0);
    require(control(lease, 1) != 0); // Nested begin fails and poisons the lease.
    release(lease);
    lease = acquire();
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 5})") == 0);
    Completion running;
    auto id = aphid_next_id(db);
    const char* long_query = "UNWIND range(1,100000) AS x UNWIND range(1,100000) AS y RETURN sum(sin(x)+cos(y))";
    require(aphid_reserve_lease(db, 0, id, lease, &error) == 0);
    require(aphid_submit_params(db, 0, id, reinterpret_cast<const uint8_t*>(long_query),
        std::strlen(long_query), nullptr, &running, completed, cancelled, &error) == 0);
    std::this_thread::sleep_for(std::chrono::milliseconds{10});
    require(running.status.load() == -1);
    release(lease); // Interrupt execution and roll back id 5 before reuse.
    require(running.status.load() != -1 && count() == 1);
    lease = acquire();
    require(control(lease, 1) == 0);
    require(query(lease, "CREATE (:LeaseProbe {id: 6})") == 0);
    Completion reading;
    id = aphid_next_id(db);
    require(aphid_reserve_lease(db, 0, id, lease, &error) == 0);
    require(aphid_submit_params(db, 0, id, reinterpret_cast<const uint8_t*>("RETURN 7"),
        8, nullptr, &reading, completed, cancelled, &error) == 0);
    eventually([&] { return reading.status.load() == 0; });
    auto* cursor = aphid_fetch_begin(db, 0, id, &error);
    require(cursor != nullptr);
    require(aphid_lease_release(db, 0, lease));
    std::this_thread::sleep_for(std::chrono::milliseconds{10});
    require(aphid_session_state(db, 0) == 2);
    require(aphid_lease_acquire(db, 0, aphid_next_id(db), &error) == 2);
    require(aphid_fetch_next(cursor, &error) == 1);
    aphid_fetch_end(cursor);
    eventually([&] { return aphid_session_state(db, 0) == 0; });
    require(count() == 1);
    std::cout << "native transaction leases, stale/foreign rejection, commit, rollback, abandonment and failure guard passed\n";
    std::cout << "transaction abandonment during execution/fetch rolls back before reuse passed\n";
}

static void concurrent_control_cases(aphid_db* db) {
    aphid_error error{};
    for (int iteration = 0; iteration < 30; ++iteration) {
        Completion old;
        auto stale = aphid_next_id(db);
        require(aphid_submit(db, 0, stale, reinterpret_cast<const uint8_t*>("RETURN 1"),
            8, &old, completed, cancelled, &error) == 0);
        eventually([&] { return old.status.load() == 0; });
        require(aphid_finish(db, 0, stale));
        eventually([&] { return aphid_session_state(db, 0) == 0; });

        // Hold the successor at its worker callback while a separate thread
        // targets the previous generation. No sleep determines this overlap.
        struct Gated : Completion {
            std::atomic<int> calls{0};
            std::atomic<bool> entered{false}, proceed{false};
        } current;
        auto gate = [](void* context) -> int32_t {
            auto& state = *static_cast<Gated*>(static_cast<Completion*>(context));
            if (state.calls.fetch_add(1) == 0) return 0; // Submission also checks cancellation.
            state.entered = true;
            while (!state.proceed.load()) std::this_thread::yield();
            return 0;
        };
        auto id = aphid_next_id(db);
        require(aphid_submit(db, 0, id, reinterpret_cast<const uint8_t*>("RETURN 7"),
            8, static_cast<Completion*>(&current), completed, gate, &error) == 0);
        eventually([&] { return current.entered.load(); });
        bool rejected = true;
        std::thread canceller([&] {
            for (int i = 0; i < 100; ++i) rejected &= !aphid_cancel(db, 0, stale, 1);
        });
        canceller.join();
        current.proceed = true;
        require(rejected);
        eventually([&] { return current.status.load() == 0; });
        auto* cursor = aphid_fetch_begin(db, 0, id, &error);
        require(cursor && aphid_fetch_next(cursor, &error) == 1);
        require(reinterpret_cast<const lbug::common::Value*>(aphid_fetch_value(cursor, 0))->getValue<int64_t>() == 7);
        aphid_fetch_end(cursor);
        require(aphid_finish(db, 0, id));
        eventually([&] { return aphid_session_state(db, 0) == 0; });

        std::atomic<int> waiting{0};
        std::atomic<bool> start{false};
        uint64_t leases[] = {aphid_next_id(db), aphid_next_id(db)};
        int results[2] = {-1, -1};
        auto contend = [&](int index) {
            aphid_error local{};
            ++waiting;
            while (!start.load()) std::this_thread::yield();
            results[index] = aphid_lease_acquire(db, 0, leases[index], &local);
        };
        std::thread first(contend, 0), second(contend, 1);
        eventually([&] { return waiting == 2; });
        start = true;
        first.join();
        second.join();
        require((results[0] == 0 && results[1] == 2) || (results[0] == 2 && results[1] == 0));
        require(aphid_lease_release(db, 0, leases[results[0] == 0 ? 0 : 1]));
        eventually([&] { return aphid_session_state(db, 0) == 0; });
    }
    std::cout << "30 gated stale-cancel/reuse and simultaneous lease contention iterations passed\n";
}

int main() {
    try {
        aphid_error error{};
        auto* db = aphid_open(reinterpret_cast<const uint8_t*>(""), 0, 1, 2, &error);
        if (!db) throw std::runtime_error{error.message};
        transaction_engine_cases(db);
        transaction_lease_cases(db);
        concurrent_control_cases(db);
        parameter_cases(db);
        {
            auto stale = aphid_next_id(db);
            require(aphid_reserve(db, 0, stale, &error) == 0);
            require(aphid_reserve(db, 0, aphid_next_id(db), &error) != 0);
            require(aphid_cancel(db, 0, stale, 1));
            eventually([&] { return aphid_session_state(db, 0) == 0; });
            Completion current, abandoned;
            auto next = aphid_next_id(db);
            require(aphid_submit(db, 0, next, reinterpret_cast<const uint8_t*>("RETURN 1"), 8,
                &current, completed, cancelled, &error) == 0);
            require(aphid_submit_params(db, 0, stale, reinterpret_cast<const uint8_t*>("RETURN 2"), 8,
                nullptr, &abandoned, completed, cancelled, &error) != 0);
            eventually([&] { return current.status.load() == 0; });
            require(abandoned.status == -1 && !aphid_cancel(db, 0, stale, 0));
            require(aphid_finish(db, 0, next));
            eventually([&] { return aphid_session_state(db, 0) == 0; });
            std::cout << "bounded conversion reservations and stale conversion rejection passed\n";
        }
        for (bool throws : {false, true}) {
            Completion completion;
            completion.deliver = false;
            completion.throws = throws;
            auto id = aphid_next_id(db);
            require(aphid_submit(db, 0, id, reinterpret_cast<const uint8_t*>("RETURN 1"), 8,
                &completion, completed, cancelled, &error) == 0);
            eventually([&] { return completion.status.load() == 0 && aphid_session_state(db, 0) == 0; });
            require(aphid_cancel(db, 0, id, 0) == 0);
        }
        {
            Completion completion;
            const std::string query = "UNWIND [41, 42] AS n RETURN n, CAST(NULL AS INT128) AS empty";
            auto id = aphid_next_id(db);
            require(aphid_submit(db, 0, id, reinterpret_cast<const uint8_t*>(query.data()), query.size(),
                &completion, completed, cancelled, &error) == 0);
            eventually([&] { return completion.status.load() == 0; });
            auto* cursor = aphid_fetch_begin(db, 0, id, &error);
            require(cursor && aphid_fetch_columns(cursor) == 2 && aphid_fetch_rows(cursor) == 2);
            require(!aphid_fetch_begin(db, 0, id, &error));
            require(!aphid_fetch_begin(db, 0, id + 1, &error));
            aphid_bytes name{};
            const aphid_type* type = nullptr;
            require(aphid_fetch_column(cursor, 1, &name, &type));
            require(std::string(reinterpret_cast<const char*>(name.data), name.length) == "empty");
            require(reinterpret_cast<const lbug::common::LogicalType*>(type)->getLogicalTypeID() ==
                lbug::common::LogicalTypeID::INT128);
            require(aphid_fetch_next(cursor, &error) == 1);
            auto* first = reinterpret_cast<const lbug::common::Value*>(aphid_fetch_value(cursor, 0));
            require(first && first->getValue<int64_t>() == 41);
            require(aphid_finish(db, 0, id));
            std::this_thread::sleep_for(std::chrono::milliseconds{10});
            require(aphid_session_state(db, 0) == 2 && first->getValue<int64_t>() == 41);
            require(aphid_fetch_next(cursor, &error) == 1);
            require(reinterpret_cast<const lbug::common::Value*>(aphid_fetch_value(cursor, 0))->getValue<int64_t>() == 42);
            require(aphid_fetch_next(cursor, &error) == 0);
            aphid_fetch_end(cursor);
            eventually([&] { return aphid_session_state(db, 0) == 0; });
        }
        Completion completion;
        fail_worker = true;
        require(aphid_submit(db, 0, aphid_next_id(db), reinterpret_cast<const uint8_t*>("RETURN 1"), 8,
            &completion, completed, cancelled, &error) == 0);
        eventually([&] { return completion.status.load() == 3 && aphid_session_state(db, 0) == 3; });
        require(aphid_submit(db, 0, aphid_next_id(db), reinterpret_cast<const uint8_t*>("RETURN 1"), 8,
            &completion, completed, cancelled, &error) != 0);
        aphid_retire(db);
        eventually([&] { return aphid_closed(db); });
        aphid_release(db);
        require(aphid_live_databases() == 0 && aphid_live_workers() == 0);
        const auto root = std::filesystem::temp_directory_path() /
            ("aphid-restart-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        std::filesystem::create_directories(root);
        const auto path = (root / "graph").string();
        db = aphid_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(), 1, 2, &error);
        require(db != nullptr);
        require(aphid_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(), 1, 2, &error) == nullptr);
        require(error.code == 2);
        Completion reading;
        auto id = aphid_next_id(db);
        require(aphid_submit(db, 0, id, reinterpret_cast<const uint8_t*>("RETURN 7"), 8,
            &reading, completed, cancelled, &error) == 0);
        eventually([&] { return reading.status.load() == 0; });
        auto* cursor = aphid_fetch_begin(db, 0, id, &error);
        require(cursor != nullptr);
        aphid_release(db); // The fetch itself retains the parent, without an external reference.
        std::this_thread::sleep_for(std::chrono::milliseconds{10});
        require(aphid_live_databases() == 1 && aphid_live_workers() == 1);
        const auto alias = (root / "." / "graph").string();
        require(aphid_open(reinterpret_cast<const uint8_t*>(alias.data()), alias.size(), 1, 2, &error) == nullptr);
        require(error.code == 6); // Fetch deterministically holds retirement open.
        require(aphid_fetch_next(cursor, &error) == 1);
        require(reinterpret_cast<const lbug::common::Value*>(aphid_fetch_value(cursor, 0))->getValue<int64_t>() == 7);
        aphid_fetch_end(cursor);
        eventually([&] { return aphid_live_databases() == 0 && aphid_live_workers() == 0; });
        db = aphid_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(), 1, 2, &error);
        require(db != nullptr);
        aphid_release(db);
        eventually([&] { return aphid_live_databases() == 0 && aphid_live_workers() == 0; });
        std::filesystem::remove_all(root);
        std::cout << "failed delivery, throwing callback, worker failure and joined cleanup passed\n";
        std::cout << "exclusive fetch, stale fetch, metadata, finish/close during fetch and parent retention passed\n";
        std::cout << "active/retiring path distinction, alias reservation and reopen after fetch release passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; }
    catch (...) { std::cerr << "unknown lifecycle test failure\n"; }
    return 1;
}
