#include <windows.h>
#include <winhttp.h>

#include <cstdint>
#include <string>

#include "keynako_submission_config.h"

namespace {

constexpr std::size_t kMaximumPayloadBytes = 64 * 1024;

bool read_payload(std::string *payload) {
    if (!payload) return false;
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    if (!input || input == INVALID_HANDLE_VALUE) return false;
    char buffer[4096];
    DWORD read = 0;
    while (ReadFile(input, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
        if (payload->size() + read > kMaximumPayloadBytes) return false;
        payload->append(buffer, read);
    }
    return !payload->empty();
}

void close_http_handle(HINTERNET handle) {
    if (handle) WinHttpCloseHandle(handle);
}

bool post_payload(const std::wstring &endpoint, const std::string &payload) {
    if (endpoint.rfind(L"https://", 0) != 0) return false;
    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(endpoint.c_str(), 0, 0, &components) ||
        components.nScheme != INTERNET_SCHEME_HTTPS ||
        !components.lpszHostName || components.dwHostNameLength == 0) {
        return false;
    }

    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    std::wstring path = components.dwUrlPathLength > 0
                            ? std::wstring(components.lpszUrlPath,
                                           components.dwUrlPathLength)
                            : L"/";
    if (components.dwExtraInfoLength > 0) {
        path.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    }

    HINTERNET session = WinHttpOpen(L"Keynako/3.0.1",
                                    WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                    WINHTTP_NO_PROXY_NAME,
                                    WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) return false;
    WinHttpSetTimeouts(session, 10000, 10000, 15000, 30000);
    HINTERNET connection = WinHttpConnect(session, host.c_str(),
                                          components.nPort, 0);
    if (!connection) {
        close_http_handle(session);
        return false;
    }
    HINTERNET request = WinHttpOpenRequest(
        connection, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!request) {
        close_http_handle(connection);
        close_http_handle(session);
        return false;
    }

    const wchar_t headers[] =
        L"Content-Type: application/json\r\nAccept: application/json\r\n";
    const BOOL sent = WinHttpSendRequest(
        request, headers, static_cast<DWORD>(-1L),
        const_cast<char *>(payload.data()), static_cast<DWORD>(payload.size()),
        static_cast<DWORD>(payload.size()), 0);
    const BOOL received = sent && WinHttpReceiveResponse(request, nullptr);
    DWORD status = 0;
    DWORD status_size = sizeof(status);
    const BOOL queried = received && WinHttpQueryHeaders(
        request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
        WINHTTP_NO_HEADER_INDEX);

    close_http_handle(request);
    close_http_handle(connection);
    close_http_handle(session);
    return queried && status >= 200 && status < 300;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t *, int) {
    std::string payload;
    if (!read_payload(&payload)) return 2;
    return post_payload(keynako::windows::kDictionarySubmissionUrl, payload) ? 0 : 1;
}
