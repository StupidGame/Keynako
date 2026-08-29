#include <algorithm>
#include <cctype>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "llama.h"

namespace {

std::vector<llama_token> tokenize(const llama_vocab *vocab, const std::string &text) {
    std::vector<llama_token> tokens(std::max<std::size_t>(text.size() + 8, 32));
    int32_t count = llama_tokenize(
        vocab,
        text.data(),
        static_cast<int32_t>(text.size()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        false,
        false);
    if (count < 0) {
        tokens.resize(static_cast<std::size_t>(-count));
        count = llama_tokenize(
            vocab,
            text.data(),
            static_cast<int32_t>(text.size()),
            tokens.data(),
            static_cast<int32_t>(tokens.size()),
            false,
            false);
    }
    if (count <= 0) return {};
    tokens.resize(static_cast<std::size_t>(count));
    return tokens;
}

std::string token_piece(const llama_vocab *vocab, llama_token token) {
    std::vector<char> bytes(16);
    int32_t count = llama_token_to_piece(
        vocab, token, bytes.data(), static_cast<int32_t>(bytes.size()), 0, false);
    if (count < 0) {
        bytes.resize(static_cast<std::size_t>(-count));
        count = llama_token_to_piece(
            vocab, token, bytes.data(), static_cast<int32_t>(bytes.size()), 0, false);
    }
    return count > 0 ? std::string(bytes.data(), static_cast<std::size_t>(count)) : std::string();
}

int hex_value(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    value = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

bool hex_decode(const std::string &encoded, std::string &decoded) {
    if (encoded.size() % 2 != 0) return false;
    decoded.clear();
    decoded.reserve(encoded.size() / 2);
    for (std::size_t index = 0; index < encoded.size(); index += 2) {
        const int high = hex_value(encoded[index]);
        const int low = hex_value(encoded[index + 1]);
        if (high < 0 || low < 0) return false;
        decoded.push_back(static_cast<char>((high << 4) | low));
    }
    return true;
}

std::string hex_encode(const std::string &value) {
    static constexpr char digits[] = "0123456789abcdef";
    std::string result;
    result.reserve(value.size() * 2);
    for (const unsigned char byte : value) {
        result.push_back(digits[byte >> 4]);
        result.push_back(digits[byte & 0x0f]);
    }
    return result;
}

class Runtime {
public:
    ~Runtime() {
        if (context_) llama_free(context_);
        if (model_) llama_model_free(model_);
        llama_backend_free();
    }

    bool initialize(const char *model_path) {
        llama_backend_init();
        auto model_params = llama_model_default_params();
        model_params.n_gpu_layers = 0;
        model_params.use_mmap = true;
        model_ = llama_model_load_from_file(model_path, model_params);
        if (!model_) return false;
        vocab_ = llama_model_get_vocab(model_);
        if (!vocab_) return false;

        auto context_params = llama_context_default_params();
        context_params.n_ctx = 512;
        context_params.n_batch = 512;
        context_params.n_ubatch = 64;
        const auto hardware_threads = std::max(1u, std::thread::hardware_concurrency());
        const int threads = static_cast<int>(std::min(hardware_threads, 8u));
        context_params.n_threads = threads;
        context_params.n_threads_batch = threads;
        context_params.offload_kqv = false;
        context_params.flash_attn = true;
        context_params.no_perf = true;
        context_ = llama_init_from_model(model_, context_params);
        return context_ != nullptr;
    }

    std::string generate(const std::string &prompt, int max_tokens) {
        if (!context_ || !vocab_) return {};
        llama_kv_cache_clear(context_);
        auto tokens = tokenize(vocab_, prompt);
        if (tokens.empty()) return {};
        auto batch = llama_batch_get_one(tokens.data(), static_cast<int32_t>(tokens.size()));
        if (llama_decode(context_, batch) != 0) return {};

        std::string result;
        const auto eos = llama_vocab_eos(vocab_);
        const auto vocabulary_size = llama_vocab_n_tokens(vocab_);
        for (int index = 0; index < max_tokens; ++index) {
            const float *logits = llama_get_logits_ith(context_, -1);
            if (!logits) break;
            llama_token next = 0;
            for (llama_token token = 1; token < vocabulary_size; ++token) {
                if (logits[token] > logits[next]) next = token;
            }
            if (next == eos) break;
            if (!llama_vocab_is_control(vocab_, next)) result += token_piece(vocab_, next);
            auto next_batch = llama_batch_get_one(&next, 1);
            if (llama_decode(context_, next_batch) != 0) break;
        }
        return result;
    }

private:
    llama_model *model_ = nullptr;
    const llama_vocab *vocab_ = nullptr;
    llama_context *context_ = nullptr;
};

}  // namespace

int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "usage: keynako_zenzai <model.gguf>\n";
        return 64;
    }

    Runtime runtime;
    if (!runtime.initialize(argv[1])) {
        std::cerr << "failed to load Zenzai model\n";
        return 1;
    }
    std::cout << "READY" << std::endl;

    std::string line;
    while (std::getline(std::cin, line)) {
        if (line == "QUIT") break;
        const auto separator = line.find('\t');
        if (separator == std::string::npos) {
            std::cout << "ERROR\tinvalid request" << std::endl;
            continue;
        }
        int max_tokens = 24;
        try {
            max_tokens = std::clamp(std::stoi(line.substr(0, separator)), 1, 128);
        } catch (...) {
            std::cout << "ERROR\tinvalid token limit" << std::endl;
            continue;
        }
        std::string prompt;
        if (!hex_decode(line.substr(separator + 1), prompt)) {
            std::cout << "ERROR\tinvalid prompt" << std::endl;
            continue;
        }
        std::cout << hex_encode(runtime.generate(prompt, max_tokens)) << std::endl;
    }
    return 0;
}
