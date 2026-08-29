#include "zenzai_client.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <sstream>
#include <utility>

#ifdef _WIN32
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace keynako {
namespace {

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

int hex_value(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    value = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
    return value >= 'a' && value <= 'f' ? value - 'a' + 10 : -1;
}

std::string hex_decode(const std::string &value) {
    if (value.size() % 2 != 0) return {};
    std::string result;
    result.reserve(value.size() / 2);
    for (std::size_t index = 0; index < value.size(); index += 2) {
        const int high = hex_value(value[index]);
        const int low = hex_value(value[index + 1]);
        if (high < 0 || low < 0) return {};
        result.push_back(static_cast<char>((high << 4) | low));
    }
    return result;
}

std::string prompt(const std::string &reading, const std::string &left_context) {
    // Zenzai v3.2 control tags: left-context, reading-start, reading-end.
    return (left_context.empty() ? std::string() : std::string("\xee\xb8\x82") + left_context) +
           "\xee\xb8\x80" + reading + "\xee\xb8\x81";
}

std::string sanitize(std::string value) {
    const std::string marker_prefix = "\xee\xb8";
    const auto marker = value.find(marker_prefix);
    if (marker != std::string::npos) value.resize(marker);
    while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) value.pop_back();
    std::size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) ++start;
    return value.substr(start);
}

}  // namespace

class ZenzaiClient::Impl {
public:
    Impl(std::string executable, std::string model) {
        if (!executable.empty() && !model.empty()) start(std::move(executable), std::move(model));
    }
    ~Impl() { stop(); }
    bool available() const { return ready_; }

    std::string generate(const std::string &reading, const std::string &left_context, int max_tokens) {
        if (!ready_ || reading.empty()) return {};
        std::ostringstream request;
        request << std::clamp(max_tokens, 1, 128) << '\t'
                << hex_encode(prompt(reading, left_context)) << '\n';
        if (!write_all(request.str())) { stop(); return {}; }
        const auto response = read_line();
        if (response.empty() || response.rfind("ERROR", 0) == 0) return {};
        return sanitize(hex_decode(response));
    }

private:
#ifdef _WIN32
    HANDLE process_ = nullptr;
    HANDLE input_ = nullptr;
    HANDLE output_ = nullptr;
#else
    pid_t process_ = -1;
    int input_ = -1;
    int output_ = -1;
#endif
    bool ready_ = false;

    void start(std::string executable, std::string model) {
#ifdef _WIN32
        SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
        HANDLE child_stdin_read = nullptr;
        HANDLE child_stdout_write = nullptr;
        if (!CreatePipe(&child_stdin_read, &input_, &security, 0) ||
            !CreatePipe(&output_, &child_stdout_write, &security, 0)) return;
        SetHandleInformation(input_, HANDLE_FLAG_INHERIT, 0);
        SetHandleInformation(output_, HANDLE_FLAG_INHERIT, 0);
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdInput = child_stdin_read;
        startup.hStdOutput = child_stdout_write;
        HANDLE error_output = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                           &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        startup.hStdError = error_output;
        PROCESS_INFORMATION process{};
        const auto utf8_to_wide = [](const std::string &value) {
            const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
            std::wstring wide(static_cast<std::size_t>(std::max(0, size)), L'\0');
            if (size > 0) MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), wide.data(), size);
            return wide;
        };
        std::wstring command = L"\"" + utf8_to_wide(executable) + L"\" \"" + utf8_to_wide(model) + L"\"";
        if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE,
                           CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
            process_ = process.hProcess;
            CloseHandle(process.hThread);
        }
        CloseHandle(child_stdin_read);
        CloseHandle(child_stdout_write);
        if (error_output != INVALID_HANDLE_VALUE) CloseHandle(error_output);
#else
        int stdin_pipe[2];
        int stdout_pipe[2];
        if (pipe(stdin_pipe) != 0 || pipe(stdout_pipe) != 0) return;
        process_ = fork();
        if (process_ == 0) {
            dup2(stdin_pipe[0], STDIN_FILENO);
            dup2(stdout_pipe[1], STDOUT_FILENO);
            close(stdin_pipe[0]); close(stdin_pipe[1]);
            close(stdout_pipe[0]); close(stdout_pipe[1]);
            execl(executable.c_str(), executable.c_str(), model.c_str(), static_cast<char *>(nullptr));
            _exit(127);
        }
        close(stdin_pipe[0]); close(stdout_pipe[1]);
        input_ = stdin_pipe[1]; output_ = stdout_pipe[0];
#endif
        ready_ = process_valid() && read_line() == "READY";
        if (!ready_) stop();
    }

    bool process_valid() const {
#ifdef _WIN32
        return process_ != nullptr;
#else
        return process_ > 0;
#endif
    }

    bool write_all(const std::string &value) {
#ifdef _WIN32
        DWORD written = 0;
        return input_ && WriteFile(input_, value.data(), static_cast<DWORD>(value.size()), &written, nullptr) && written == value.size();
#else
        std::size_t offset = 0;
        while (offset < value.size()) {
            const auto written = write(input_, value.data() + offset, value.size() - offset);
            if (written <= 0) return false;
            offset += static_cast<std::size_t>(written);
        }
        return true;
#endif
    }

    std::string read_line() {
        std::string line;
        char value = 0;
        while (line.size() < 1024 * 1024) {
#ifdef _WIN32
            DWORD read_count = 0;
            if (!output_ || !ReadFile(output_, &value, 1, &read_count, nullptr) || read_count != 1) return {};
#else
            if (output_ < 0 || read(output_, &value, 1) != 1) return {};
#endif
            if (value == '\n') break;
            if (value != '\r') line.push_back(value);
        }
        return line;
    }

    void stop() {
        if (ready_) write_all("QUIT\n");
        ready_ = false;
#ifdef _WIN32
        if (input_) { CloseHandle(input_); input_ = nullptr; }
        if (output_) { CloseHandle(output_); output_ = nullptr; }
        if (process_) {
            if (WaitForSingleObject(process_, 1500) == WAIT_TIMEOUT) TerminateProcess(process_, 1);
            CloseHandle(process_); process_ = nullptr;
        }
#else
        if (input_ >= 0) { close(input_); input_ = -1; }
        if (output_ >= 0) { close(output_); output_ = -1; }
        if (process_ > 0) {
            int status = 0;
            for (int attempt = 0; attempt < 15 && waitpid(process_, &status, WNOHANG) == 0; ++attempt) usleep(100000);
            if (waitpid(process_, &status, WNOHANG) == 0) { kill(process_, SIGTERM); waitpid(process_, &status, 0); }
            process_ = -1;
        }
#endif
    }
};

ZenzaiClient::ZenzaiClient(std::string executable_path, std::string model_path)
    : impl_(std::make_unique<Impl>(std::move(executable_path), std::move(model_path))) {}
ZenzaiClient::~ZenzaiClient() = default;
bool ZenzaiClient::available() const { return impl_->available(); }
std::string ZenzaiClient::generate(const std::string &reading, const std::string &left_context, int max_tokens) {
    return impl_->generate(reading, left_context, max_tokens);
}

}  // namespace keynako
