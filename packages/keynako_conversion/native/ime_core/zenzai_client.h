#pragma once

#include <chrono>
#include <memory>
#include <string>

namespace keynako {

// Synchronous facade over the persistent llama.cpp helper. Adapters call this
// on explicit conversion (Space); live base conversion never waits for a model.
class ZenzaiClient {
public:
    ZenzaiClient(std::string executable_path, std::string model_path,
                 std::chrono::milliseconds timeout = std::chrono::seconds(15));
    ~ZenzaiClient();
    ZenzaiClient(const ZenzaiClient &) = delete;
    ZenzaiClient &operator=(const ZenzaiClient &) = delete;

    bool available() const;
    std::string generate(const std::string &reading,
                         const std::string &left_context = "",
                         int max_tokens = 24);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace keynako
