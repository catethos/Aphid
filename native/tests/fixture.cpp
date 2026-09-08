#include "duckdb.hpp"
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        if (argc != 2 && argc != 3) throw std::runtime_error("usage: fixture duckdb-path [hold]");
        duckdb::DuckDB database{argv[1]};
        duckdb::Connection connection{database};
        if (argc == 3 && std::string{argv[2]} == "slow") {
            auto result = connection.Query("CREATE VIEW slow_values AS SELECT sum(sin(i::DOUBLE)) AS total FROM range(100000000) AS r(i); CHECKPOINT");
            for (duckdb::QueryResult* current = result.get(); current; current = current->next.get()) {
                if (current->HasError()) throw std::runtime_error(current->GetError());
            }
            return 0;
        }
        if (argc == 3) {
            if (std::string{argv[2]} != "hold") throw std::runtime_error("unknown fixture mode");
            std::cout << "locked" << std::endl;
            std::string release;
            std::getline(std::cin, release);
            return 0;
        }
        auto result = connection.Query(R"SQL(
            CREATE TABLE records(id BIGINT, title VARCHAR);
            INSERT INTO records VALUES (19, 'café'), (23, NULL);
            CREATE TABLE rel_notes AS SELECT 7::BIGINT AS id;
            CREATE TABLE csr_rel_notes AS SELECT 8::BIGINT AS id;
            CREATE TABLE Document AS SELECT 9::BIGINT AS id;
            CREATE TABLE exact_values(id BIGINT, amount DECIMAL(20,4), stamp TIMESTAMP, bytes BLOB, title VARCHAR);
            INSERT INTO exact_values VALUES
                (9223372036854775807, 1234567890123456.7890,
                 TIMESTAMP '2000-01-01 00:00:00.123456', from_hex('00FF4142'), '蜜蜂 café'),
                (-9223372036854775808, -0.0001,
                 TIMESTAMP '1969-12-31 23:59:59.999999', from_hex(''), NULL),
                (0, NULL, NULL, NULL, '');
            CHECKPOINT
        )SQL");
        for (duckdb::QueryResult* current = result.get(); current; current = current->next.get()) {
            if (current->HasError()) throw std::runtime_error(current->GetError());
        }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
    } catch (...) {
        std::cerr << "unknown fixture failure\n";
    }
    return 1;
}
