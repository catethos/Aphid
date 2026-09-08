#include "main/connection.h"
#include "main/database.h"
#include "main/query_result.h"
#include "processor/result/flat_tuple.h"
#include "processor/result/factorized_table_schema.h"
#include <iostream>
#include <stdexcept>

int main() {
    try {
        using namespace lbug::processor;
        FactorizedTableSchema schema;
        schema.appendColumn(ColumnSchema{false, 0, 1});
        schema.appendColumn(ColumnSchema{false, 0, 16}, 8);
        schema.appendColumn(ColumnSchema{false, 0, 8});
        auto copied = schema.copy();
        if (schema.getColOffset(1) != 8 || schema.getColOffset(2) != 24 ||
            schema.getNullMapOffset() != 32 || schema.getNumBytesPerTuple() != 40 ||
            copied != schema || copied.getColOffset(1) != 8) {
            throw std::runtime_error("aggregate layout or schema copy lost alignment");
        }
        copied.appendColumn(ColumnSchema{false, 0, 1});
        if (copied.getColOffset(3) != 32 || copied.getNumBytesPerTuple() != 40) {
            throw std::runtime_error("schema append lost alignment");
        }
        lbug::main::Database db{"", lbug::main::SystemConfig{67108864, 2}};
        lbug::main::Connection connection{&db};
        auto result = connection.query(
            "UNWIND range(1,100) AS i RETURN (i % 2 = 1) AS k, count(*), sum(i) ORDER BY k");
        if (!result->isSuccess()) throw std::runtime_error(result->getErrorMessage());
        for (int group = 0; group < 2; ++group) {
            if (!result->hasNext()) throw std::runtime_error("missing aggregate group");
            auto row = result->getNext();
            if (row->getValue(0)->getValue<bool>() != (group == 1) ||
                row->getValue(1)->getValue<int64_t>() != 50 ||
                row->getValue(2)->toString() != (group == 0 ? "2550" : "2500")) {
                throw std::runtime_error("aggregate result differs");
            }
        }
        if (result->hasNext()) throw std::runtime_error("unexpected aggregate group");
        std::cout << "byte-sized grouping key, multiple aggregate states and rows passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
