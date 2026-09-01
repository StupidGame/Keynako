#include "keynako_improvement_submission.h"

#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#endif

#include <algorithm>
#include <cctype>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace keynako::windows {
namespace {

#ifdef _WIN32
constexpr std::size_t kMaximumResponseBytes = 64 * 1024;

class InternetHandle {
public:
    explicit InternetHandle(HINTERNET handle = nullptr) : handle_(handle) {}
    ~InternetHandle() {
        if (handle_) WinHttpCloseHandle(handle_);
    }

    InternetHandle(const InternetHandle &) = delete;
    InternetHandle &operator=(const InternetHandle &) = delete;

    HINTERNET get() const { return handle_; }
    explicit operator bool() const { return handle_ != nullptr; }

private:
    HINTERNET handle_;
};
#endif

std::string escape_json(const std::string &value) {
    constexpr char kHex[] = "0123456789abcdef";
    std::string escaped;
    escaped.reserve(value.size());
    for (const unsigned char character : value) {
        switch (character) {
            case '"': escaped += "\\\""; break;
            case '\\': escaped += "\\\\"; break;
            case '\b': escaped += "\\b"; break;
            case '\f': escaped += "\\f"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:
                if (character < 0x20) {
                    escaped += "\\u00";
                    escaped.push_back(kHex[(character >> 4) & 0x0f]);
                    escaped.push_back(kHex[character & 0x0f]);
                } else {
                    escaped.push_back(static_cast<char>(character));
                }
        }
    }
    return escaped;
}

#ifdef _WIN32
bool response_accepts_submission(const std::string &body) {
    const auto first = std::find_if_not(body.begin(), body.end(), [](unsigned char character) {
        return std::isspace(character) != 0;
    });
    if (first == body.end()) return true;
    const auto last = std::find_if_not(body.rbegin(), body.rend(), [](unsigned char character) {
        return std::isspace(character) != 0;
    }).base();
    if (*first != '{' || last == first || *(last - 1) != '}') return false;

    const auto ok = body.find("\"ok\"", static_cast<std::size_t>(first - body.begin()));
    if (ok == std::string::npos || ok >= static_cast<std::size_t>(last - body.begin())) return true;
    const auto colon = body.find(':', ok + 4);
    if (colon == std::string::npos || colon >= static_cast<std::size_t>(last - body.begin())) return false;
    const auto value = body.find_first_not_of(" \t\r\n", colon + 1);
    return value != std::string::npos && body.compare(value, 4, "true") == 0;
}
#endif

}  // namespace

std::string build_improvement_payload(const ImprovementSubmission &submission,
                                      const std::string &app_version) {
    std::ostringstream payload;
    payload << "{\"word\":\"" << escape_json(submission.word)
            << "\",\"ruby\":\"" << escape_json(submission.reading)
            << "\",\"importance\":3,\"categories\":[],\"note\":\"IME候補改善: 第"
            << (submission.selected_index + 1)
            << "候補を選択\",\"source\":\"Keynako IME\",\"app_version\":\""
            << escape_json(app_version) << "\"}";
    return payload.str();
}

bool submit_improvement_https(const std::wstring &endpoint,
                              const std::string &payload) {
#ifdef _WIN32
    if (endpoint.empty() || endpoint.size() > std::numeric_limits<DWORD>::max() ||
        payload.size() > std::numeric_limits<DWORD>::max()) {
        return false;
    }

    URL_COMPONENTSW components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(endpoint.c_str(), static_cast<DWORD>(endpoint.size()), 0,
                         &components) ||
        components.nScheme != INTERNET_SCHEME_HTTPS ||
        components.dwHostNameLength == 0) {
        return false;
    }

    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    std::wstring path;
    if (components.dwUrlPathLength > 0) {
        path.assign(components.lpszUrlPath, components.dwUrlPathLength);
    }
    if (components.dwExtraInfoLength > 0) {
        path.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    }
    if (path.empty()) path = L"/";

    const InternetHandle session(WinHttpOpen(
        L"Keynako Windows IME", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session) return false;
    WinHttpSetTimeouts(session.get(), 15000, 15000, 15000, 30000);

    const InternetHandle connection(
        WinHttpConnect(session.get(), host.c_str(), components.nPort, 0));
    if (!connection) return false;

    const wchar_t *accepted_types[] = {L"application/json", nullptr};
    const InternetHandle request(WinHttpOpenRequest(
        connection.get(), L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
        accepted_types, WINHTTP_FLAG_SECURE));
    if (!request) return false;

    constexpr wchar_t kHeaders[] =
        L"Content-Type: application/json; charset=utf-8\r\nAccept: application/json\r\n";
    const DWORD payload_size = static_cast<DWORD>(payload.size());
    if (!WinHttpSendRequest(
            request.get(), kHeaders, static_cast<DWORD>(-1),
            const_cast<char *>(payload.data()), payload_size, payload_size, 0) ||
        !WinHttpReceiveResponse(request.get(), nullptr)) {
        return false;
    }

    DWORD status = 0;
    DWORD status_size = sizeof(status);
    if (!WinHttpQueryHeaders(request.get(),
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
                             WINHTTP_NO_HEADER_INDEX) ||
        status < 200 || status > 299) {
        return false;
    }

    std::string response;
    for (;;) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.get(), &available)) return false;
        if (available == 0) break;
        if (response.size() + available > kMaximumResponseBytes) return false;
        std::vector<char> chunk(available);
        DWORD read = 0;
        if (!WinHttpReadData(request.get(), chunk.data(), available, &read)) return false;
        if (read == 0) return false;
        response.append(chunk.data(), read);
    }
    return response_accepts_submission(response);
#else
    static_cast<void>(endpoint);
    static_cast<void>(payload);
    return false;
#endif
}

}  // namespace keynako::windows
