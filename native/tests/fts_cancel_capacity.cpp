#include "main/database.h"
#include "main/connection.h"
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

int main(int argc, char** argv) {
    try {
        if (argc != 2) throw std::runtime_error("usage: fts_cancel_capacity database-path");
        Database database{argv[1], SystemConfig{1024ULL * 1024 * 1024, 2}};
        Connection connection{&database};
        query(connection, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))");
        for (int batch = 0; batch < 10; ++batch) {
            query(connection, "UNWIND range(" + std::to_string(batch * 30000 + 1) + "," +
                std::to_string((batch + 1) * 30000) + ") AS i CREATE (:Document {id:i, body:'nectar garden café ocean coral forest'})");
        }
        connection.setQueryTimeOut(100);
        auto cancelled = connection.query("CALL CREATE_FTS_INDEX('Document','words',['body'])");
        if (cancelled->isSuccess() || cancelled->getErrorMessage().find("Interrupt") == std::string::npos)
            throw std::runtime_error("expected interrupted FTS build: " + cancelled->getErrorMessage());
        connection.setQueryTimeOut(60000);
        query(connection, "CALL CREATE_FTS_INDEX('Document','words',['body'])");
        auto result = query(connection, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)");
        if (result->getNext()->getValue(0)->getValue<int64_t>() != 300000)
            throw std::runtime_error("rebuilt FTS index count differs");
        query(connection, "CALL DROP_FTS_INDEX('Document','words')");
        std::cout << "1024 MiB FTS cancellation, same-name rebuild, 300000 hits and drop passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
