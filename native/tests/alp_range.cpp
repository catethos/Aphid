#include "alp/encode.hpp"
#include <iostream>
#include <limits>

template<typename T>
bool check() {
    using Encoder = alp::AlpEncode<T>;
    using Integer = alp::FloatingToEncodedType<T>;
    const T upper = -static_cast<T>(std::numeric_limits<Integer>::lowest());
    for (T value : {upper, -upper * 2, std::numeric_limits<T>::max(),
             std::numeric_limits<T>::infinity(), std::numeric_limits<T>::quiet_NaN()}) {
        if (Encoder::encode_value(value, 0, 0) != std::numeric_limits<Integer>::max() ||
            Encoder::template encode_value<false>(value, 0, 0) != std::numeric_limits<Integer>::max()) {
            return false;
        }
    }
    for (T value : {T{0}, T{1}, T{-1}, T{42}}) {
        if (Encoder::encode_value(value, 0, 0) != static_cast<Integer>(value) ||
            Encoder::template encode_value<false>(value, 0, 0) != static_cast<Integer>(value)) {
            return false;
        }
    }
    return true;
}

int main() {
    if (!check<float>() || !check<double>()) return 1;
    std::cout << "ALP float/double conversion boundaries and ordinary values passed\n";
}
