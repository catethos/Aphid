// Runtime discovery only: the "race" mode deliberately contains a data race.
#include <atomic>
#include <cstdio>
#include <cerrno>
#include <cstring>
#include <sys/mman.h>
#include <thread>

int main(int argc, char** argv) {
    std::puts("TSan main reached");
    std::fflush(stdout);
    if (argc > 1 && std::strcmp(argv[1], "mapping") == 0) {
        int failures = 0;
        for (size_t size : {size_t{1} << 30, size_t{1} << 43}) {
            auto* region = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (region == MAP_FAILED) {
                std::printf("mmap %zu failed: %s\n", size, std::strerror(errno));
                ++failures;
            } else {
                std::printf("mmap %zu passed\n", size);
                munmap(region, size);
            }
        }
        return failures;
    }
    if (argc > 1) {
        int value = 0;
        std::thread first([&] { value = 1; });
        std::thread second([&] { value = 2; });
        first.join();
        second.join();
        std::printf("intentional race value: %d\n", value);
    } else {
        std::atomic<int> value{0};
        std::thread first([&] { ++value; });
        std::thread second([&] { ++value; });
        first.join();
        second.join();
        if (value != 2) return 1;
        std::puts("clean threaded probe passed");
    }
}
