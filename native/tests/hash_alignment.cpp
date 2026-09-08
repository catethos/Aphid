#include "function/hash/hash_functions.h"
#include <array>
#include <cstring>
#include <iostream>

int main() {
    alignas(8) std::array<char, 80> original{};
    alignas(8) std::array<char, 88> shifted{};
    for (size_t i = 0; i < original.size(); ++i) {
        original[i] = static_cast<char>(i * 71 + 129);
    }
    for (size_t length = 0; length <= original.size(); ++length) {
        lbug::common::hash_t expected;
        lbug::function::Hash::operation(std::string_view(original.data(), length), expected);
        for (size_t offset = 1; offset < 8; ++offset) {
            std::memcpy(shifted.data() + offset, original.data(), length);
            lbug::common::hash_t actual;
            lbug::function::Hash::operation(
                std::string_view(shifted.data() + offset, length), actual);
            if (actual != expected) {
                std::cerr << "hash changed at length " << length << " offset " << offset << '\n';
                return 1;
            }
        }
    }
    std::cout << "string hash is invariant across all byte alignments and lengths 0..80\n";
}
