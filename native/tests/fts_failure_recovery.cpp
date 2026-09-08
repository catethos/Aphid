#include "main/connection.h"
#include "main/database.h"
#include "main/query_result.h"
#include "processor/result/flat_tuple.h"
#include <iostream>
#include <stdexcept>

using namespace lbug::main;

static std::unique_ptr<QueryResult> query(Connection& connection, const std::string& text) {
    auto result = connection.query(text);
    if (!result->isSuccess()) throw std::runtime_error(result->getErrorMessage());
    return result;
}

static int64_t count(Connection& connection, const std::string& text) {
    return query(connection, text)->getNext()->getValue(0)->getValue<int64_t>();
}

static void seed(Connection& connection, int batches, int batchSize) {
    query(connection, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))");
    for (int batch = 0; batch < batches; ++batch) {
        query(connection, "UNWIND range(" + std::to_string(batch * batchSize + 1) + "," +
            std::to_string((batch + 1) * batchSize) +
            ") AS i CREATE (:Document {id:i, body:'nectar garden café ocean coral forest'})");
    }
}

static void expectFailure(Connection& connection, const std::string& message) {
    auto result = connection.query("CALL CREATE_FTS_INDEX('Document','words',['body'])");
    if (result->isSuccess() || result->getErrorMessage().find(message) == std::string::npos)
        throw std::runtime_error("unexpected FTS result: " + result->getErrorMessage());
}

int main(int argc, char** argv) {
    try {
        if (argc != 3)
            throw std::runtime_error("usage: fts_failure_recovery late-create|late-verify|oom database-path");
        const std::string mode = argv[1];
        const uint64_t pool = mode == "oom" ? 64ULL * 1024 * 1024 : 1024ULL * 1024 * 1024;
        Database database{argv[2], SystemConfig{pool, 2}};
        Connection connection{&database};

        if (mode == "late-verify") {
            if (count(connection, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)") != 1001)
                throw std::runtime_error("reopened FTS index count differs");
            query(connection, "CALL DROP_FTS_INDEX('Document','words')");
        } else if (mode == "late-create") {
            seed(connection, 1, 1000);
            expectFailure(connection, "aphid injected late FTS failure");
            if (count(connection, "MATCH (n:Document) RETURN count(n)") != 1000)
                throw std::runtime_error("source row count differs after late failure");
            query(connection, "CREATE (:Document {id:1001, body:'nectar'})");
            query(connection, "CALL CREATE_FTS_INDEX('Document','words',['body'])");
            if (count(connection, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)") != 1001)
                throw std::runtime_error("rebuilt FTS index count differs");
            if (std::string{argv[2]}.empty())
                query(connection, "CALL DROP_FTS_INDEX('Document','words')");
        } else if (mode == "oom") {
            seed(connection, 10, 30000);
            expectFailure(connection, "buffer pool is full");
            if (count(connection, "MATCH (n:Document) RETURN count(n)") != 300000)
                throw std::runtime_error("source row count differs after buffer exhaustion");
            query(connection, "MATCH (n:Document) WHERE n.id > 1000 DELETE n");
            query(connection, "CALL CREATE_FTS_INDEX('Document','words',['body'])");
            if (count(connection, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)") != 1000)
                throw std::runtime_error("smaller rebuilt FTS index count differs");
            query(connection, "CALL DROP_FTS_INDEX('Document','words')");
        } else {
            throw std::runtime_error("unknown mode: " + mode);
        }
        std::cout << "FTS " << mode << " recovery passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
