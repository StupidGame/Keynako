#include "zenzai_client.h"

#include <cassert>
#include <chrono>
#include <iostream>
#include <string>

using namespace std::chrono_literals;

int main(int argc, char **argv) {
    if (argc > 1) {
        const std::string mode = argv[1];
        std::string request;
        if (mode == "ready-stall") {
            while (std::getline(std::cin, request)) {}
            return 0;
        }
        std::cout << "READY\n" << std::flush;
        while (std::getline(std::cin, request)) {
            if (request == "QUIT") break;
            if (mode == "response-stall") continue;
            std::cout << (mode == "malformed" ? "not-hex\n" : "41\n") << std::flush;
        }
        return 0;
    }

    const std::string executable = argv[0];
    {
        const auto started = std::chrono::steady_clock::now();
        keynako::ZenzaiClient client(executable, "ready-stall", 200ms);
        assert(!client.available());
        assert(std::chrono::steady_clock::now() - started < 3s);
    }
    {
        keynako::ZenzaiClient client(executable, "response-stall", 2s);
        assert(client.available());
        const auto started = std::chrono::steady_clock::now();
        assert(client.generate("あ").empty());
        assert(!client.available());
        assert(std::chrono::steady_clock::now() - started < 5s);
    }
    {
        keynako::ZenzaiClient client(executable, "malformed", 2s);
        assert(client.available());
        assert(client.generate("あ").empty());
        assert(!client.available());
    }
    {
        keynako::ZenzaiClient client(executable, "valid", 2s);
        assert(client.available());
        assert(client.generate("あ") == "A");
    }
}
