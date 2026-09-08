#include "common/types/int128_t.h"
#include <array>
#include <bit>
#include <iostream>
#include <stdexcept>

int main() {
    try {
        using lbug::common::int128_t;
        const std::array<int64_t, 7> highs{INT64_MIN, INT64_MIN + 1, -1, 0, 1,
            INT64_MAX - 1, INT64_MAX};
        const std::array<uint64_t, 3> lows{0, 1, UINT64_MAX};
        auto wide = [](int128_t value) {
            return std::bit_cast<__int128>((static_cast<__uint128_t>(value.high) << 64) |
                                         value.low);
        };
        unsigned additions = 0, negations = 0;
        for (auto high : highs) for (auto low : lows) {
            int128_t value;
            value.high = high;
            value.low = low;
            auto negated = value;
            const bool minimum = high == INT64_MIN && low == 0;
            bool rejected = false;
            try { negated = -value; }
            catch (const lbug::common::OverflowException&) { rejected = true; }
            if (rejected != minimum || (!minimum && wide(negated) != -wide(value)))
                throw std::runtime_error("INT128 negation boundary mismatch");
            ++negations;
            for (auto other_high : highs) for (auto other_low : lows) {
                int128_t other;
                other.high = other_high;
                other.low = other_low;
                __int128 expected;
                const bool overflow = __builtin_add_overflow(wide(value), wide(other), &expected);
                auto actual = value;
                bool accepted = true;
                try { actual = value + other; }
                catch (const lbug::common::OverflowException&) { accepted = false; }
                if (accepted == overflow || (accepted && wide(actual) != expected))
                    throw std::runtime_error("INT128 addition boundary mismatch");
                ++additions;
            }
        }
        std::cout << additions << " checked INT128 additions and " << negations
                  << " negations agree with compiler wide-integer arithmetic\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
