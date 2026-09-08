#include "main/database.h"
#include "main/connection.h"
#include "main/query_result.h"
#include "processor/result/flat_tuple.h"
#include <iostream>
#include <stdexcept>
#include "features.h"

using namespace lbug::main;

static std::unique_ptr<QueryResult> query(Connection& connection, const std::string& text) {
    auto result = connection.query(text);
    if (!result->isSuccess()) throw std::runtime_error(text + ": " + result->getErrorMessage());
    return result;
}

static void expect(Connection& connection, const std::string& text, int64_t expected) {
    auto result = query(connection, text);
    if (result->getNumTuples() != 1 ||
        result->getNext()->getValue(0)->getValue<int64_t>() != expected)
        throw std::runtime_error("unexpected result: " + text);
}

static int check_features(int argc, const char** argv) {
    try {
        if (argc != 4) throw std::runtime_error("usage: features create|reopen graph-path duckdb-path");
        SystemConfig config{64 * 1024 * 1024, 2};
        config.throwOnWalReplayFailure = true;
        Database database{argv[2], config};
        Connection connection{&database};
        expect(connection, "CALL SHOW_LOADED_EXTENSIONS() RETURN count(*)", 3);
        if (std::string(argv[1]) == "create") {
            query(connection, "CREATE NODE TABLE Document(id INT64, title STRING, body STRING, vec FLOAT[3], PRIMARY KEY(id))");
            query(connection, "CREATE (:Document {id: 1, title: 'orchard', body: 'aphid nectar café', vec: [1.0,0.0,0.0]})");
            query(connection, "CREATE (:Document {id: 2, title: 'sea', body: 'ocean coral', vec: [0.0,1.0,0.0]})");
            query(connection, "CREATE (:Document {id: 3, title: '', body: '', vec: [0.0,0.0,1.0]})");
            query(connection, "CALL CREATE_FTS_INDEX('Document', 'words', ['title', 'body'])");
            query(connection, "CALL CREATE_VECTOR_INDEX('Document', 'neighbors', 'vec', metric := 'l2')");
            query(connection, "CREATE NODE TABLE EmptyDoc(id INT64, body STRING, PRIMARY KEY(id))");
            query(connection, "CALL CREATE_FTS_INDEX('EmptyDoc', 'empty_words', ['body'])");
        } else if (std::string(argv[1]) != "reopen") {
            throw std::runtime_error("unknown mode");
        }
        expect(connection, "CALL QUERY_FTS_INDEX('Document', 'words', 'aphid') RETURN node.id", 1);
        expect(connection, "CALL QUERY_VECTOR_INDEX('Document', 'neighbors', CAST([1.0,0.0,0.0], 'FLOAT[3]'), 1) RETURN node.id", 1);
        expect(connection, "CALL QUERY_FTS_INDEX('EmptyDoc', 'empty_words', 'aphid') RETURN count(*)", 0);
        // Fixture paths come only from our test runner; reject quotes rather than interpolate them.
        const std::string fixture{argv[3]};
        if (fixture.find('\'') != std::string::npos) throw std::runtime_error("quote in fixture path");
        query(connection, "ATTACH '" + fixture + "' AS localduck (dbtype duckdb)");
        expect(connection, "LOAD FROM localduck.records RETURN sum(id)", 42);
        expect(connection, "LOAD FROM localduck.rel_notes RETURN id", 7);
        expect(connection, "LOAD FROM localduck.csr_rel_notes RETURN id", 8);
        expect(connection, "LOAD FROM localduck.Document RETURN id", 9);
        if (std::string(argv[1]) == "create") {
            query(connection, "CREATE NODE TABLE Imported(id INT64, title STRING, PRIMARY KEY(id))");
            query(connection, "COPY Imported FROM localduck.records");
        }
        expect(connection, "MATCH (n:Imported) RETURN sum(n.id)", 42);
        query(connection, "DETACH localduck");
        query(connection, "ATTACH '" + fixture + "' AS localduck (dbtype duckdb)");
        expect(connection, "LOAD FROM localduck.records RETURN sum(id)", 42);
        query(connection, "DETACH localduck");
        std::cout << "FTS, indexed vector, empty FTS, DuckDB attach/read/import/detach passed: " << argv[1] << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
    } catch (...) {
        std::cerr << "unknown native failure\n";
    }
    return 1;
}

extern "C" int32_t aphid_features(uint8_t reopen, const uint8_t* graph, size_t graph_len,
    const uint8_t* fixture, size_t fixture_len) {
    try {
        if (graph_len > 4096 || fixture_len > 4096) return 1;
        std::string graph_path{reinterpret_cast<const char*>(graph), graph_len};
        std::string fixture_path{reinterpret_cast<const char*>(fixture), fixture_len};
        if (graph_path.find('\0') != std::string::npos || fixture_path.find('\0') != std::string::npos) return 1;
        const char* args[]{"features", reopen ? "reopen" : "create", graph_path.c_str(), fixture_path.c_str()};
        return check_features(4, args);
    } catch (...) {
        return 1;
    }
}

#ifndef APHID_NIF_PROOF
int main(int argc, const char** argv) { return check_features(argc, argv); }
#endif
