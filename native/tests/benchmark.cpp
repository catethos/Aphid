#include "main/database.h"
#include "main/connection.h"
#include "main/query_result.h"
#include "processor/result/flat_tuple.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace lbug::main;
using Clock = std::chrono::steady_clock;

int main(int argc, char** argv) {
    try {
        if (argc != 3) throw std::runtime_error("usage: benchmark setup.cypher cases.tsv");
        SystemConfig config{64 * 1024 * 1024, 2};
        config.throwOnWalReplayFailure = true;
        Database database{"", config};
        Connection connection{&database};
        auto query = [&](const std::string& text) {
            auto result = connection.query(text);
            if (!result->isSuccess()) throw std::runtime_error(result->getErrorMessage());
            // Retain owned typed values, including nested children, until collection ends.
            std::vector<std::unique_ptr<lbug::common::Value>> values;
            while (result->hasNext()) {
                auto row = result->getNext();
                for (uint64_t column = 0; column < result->getNumColumns(); ++column)
                    values.push_back(row->getValue(column)->copy());
            }
            return result->getNumTuples();
        };
        std::ifstream setup{argv[1]};
        std::ifstream cases{argv[2]};
        if (!setup || !cases) throw std::runtime_error("cannot read benchmark inputs");
        std::string line;
        while (std::getline(setup, line)) query(line);
        while (std::getline(cases, line)) {
            const auto first = line.find('\t'), second = line.find('\t', first + 1);
            const auto name = line.substr(0, first), text = line.substr(second + 1);
            const auto expected = std::stoull(line.substr(first + 1, second - first - 1));
            for (int i = 0; i < 20; ++i)
                if (query(text) != expected) throw std::runtime_error("warmup row mismatch");
            std::cout << "{\"implementation\":\"cpp\",\"case\":\"" << name << "\",\"samples_us\":[";
            for (int i = 0; i < 100; ++i) {
                auto started = Clock::now();
                const auto rows = query(text);
                auto elapsed = std::chrono::duration<double, std::micro>(Clock::now() - started).count();
                if (rows != expected) throw std::runtime_error("measured row mismatch");
                if (i) std::cout << ',';
                std::cout << elapsed;
            }
            std::cout << "]}" << std::endl;
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
