#include "main/database.h"
#include "main/connection.h"
#include "main/query_result.h"
#include "processor/result/flat_tuple.h"
#include <array>
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <thread>

using namespace lbug::main;

static std::unique_ptr<QueryResult> query(Connection& connection, const std::string& text) {
    auto result = connection.query(text);
    if (!result->isSuccess()) throw std::runtime_error(result->getErrorMessage());
    return result;
}

int main(int argc, char** argv) {
    try {
        if (argc != 2) throw std::runtime_error("usage: extension_concurrency fixture.duckdb");
        const std::string fixture{argv[1]};
        if (fixture.find('\'') != std::string::npos) throw std::runtime_error("quote in fixture path");
        SystemConfig config{64 * 1024 * 1024, 2};
#ifdef APHID_TEST_MAX_DB_SIZE
        config.maxDBSize = APHID_TEST_MAX_DB_SIZE;
#endif
        Database database{"", config};
        Connection setup{&database};
        query(setup, "CREATE NODE TABLE Document(id INT64, body STRING, vec FLOAT[3], PRIMARY KEY(id))");
        query(setup, "UNWIND range(1,100) AS i CREATE (:Document {id:i, body:'aphid nectar', vec:CAST([i,i,i],'FLOAT[3]')})");
        query(setup, "CALL CREATE_FTS_INDEX('Document','words',['body'],stemmer := 'none')");
        query(setup, "CALL CREATE_VECTOR_INDEX('Document','neighbors','vec',metric := 'l2',efc := 200)");
        query(setup, "ATTACH '" + fixture + "' AS source (dbtype duckdb)");
        const std::array<std::string, 3> queries{
            "CALL QUERY_FTS_INDEX('Document','words','aphid') RETURN count(*)",
            "CALL QUERY_VECTOR_INDEX('Document','neighbors',CAST([1,1,1],'FLOAT[3]'),1,efs := 200) RETURN node.id",
            "LOAD FROM source.records RETURN sum(id)"};
        const std::array<int64_t, 3> expected{100, 1, 42};
        std::array<std::exception_ptr, 3> failures{};
        std::array<std::thread, 3> workers;
        std::atomic<unsigned> ready{0};
        std::atomic<bool> go{false};
        for (size_t i = 0; i < workers.size(); ++i) {
            workers[i] = std::thread([&, i] {
                ready.fetch_add(1);
                while (!go.load()) std::this_thread::yield();
                try {
                    Connection connection{&database};
                    for (unsigned round = 0; round < 100; ++round) {
                        auto result = query(connection, queries[i]);
                        if (result->getNumTuples() != 1 ||
                            result->getNext()->getValue(0)->getValue<int64_t>() != expected[i])
                            throw std::runtime_error("extension result mismatch");
                    }
                } catch (...) { failures[i] = std::current_exception(); }
            });
        }
        while (ready.load() != workers.size()) std::this_thread::yield();
        go.store(true);
        for (auto& worker : workers) worker.join();
        for (auto& failure : failures) if (failure) std::rethrow_exception(failure);
        query(setup, "DETACH source");
        std::cout << "gated concurrent FTS/vector/DuckDB: 100 queries each; joined shutdown passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
