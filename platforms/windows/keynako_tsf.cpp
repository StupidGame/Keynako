#include <windows.h>
#include <windowsx.h>
#include <ctfutb.h>
#include <dwmapi.h>
#include <msctf.h>
#include <objbase.h>
#include <oleauto.h>
#include <shellapi.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <new>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_set>
#include <vector>

#include "keynako_improvement_submission.h"
#include "keynako_resources.h"
#include "keynako_ime_core.h"
#include "keynako_shortcut_policy.h"
#include "keynako_submission_payload.h"
#include "zenzai_client.h"

#ifndef KEYNAKO_DICTIONARY_SUBMISSION_URL
#define KEYNAKO_DICTIONARY_SUBMISSION_URL ""
#endif

#ifndef KEYNAKO_APP_VERSION
#define KEYNAKO_APP_VERSION "1.0.0"
#endif

namespace {

// {F7959D5B-0818-43CC-9919-6AFA791730FC}
constexpr CLSID kTextService = {0xf7959d5b, 0x0818, 0x43cc, {0x99, 0x19, 0x6a, 0xfa, 0x79, 0x17, 0x30, 0xfc}};
// {9E061A9A-A339-4AE0-B6DC-A13F21A340C2}
constexpr GUID kLanguageProfile = {0x9e061a9a, 0xa339, 0x4ae0, {0xb6, 0xdc, 0xa1, 0x3f, 0x21, 0xa3, 0x40, 0xc2}};
// {3116A7F8-8F02-4327-BA10-3625B689E948}
constexpr GUID kPreservedToggle = {0x3116a7f8, 0x8f02, 0x4327, {0xba, 0x10, 0x36, 0x25, 0xb6, 0x89, 0xe9, 0x48}};
// {A40D40D9-C3AD-492D-8234-944FAFB7E56E}
constexpr GUID kPreservedConvert = {0xa40d40d9, 0xc3ad, 0x492d, {0x82, 0x34, 0x94, 0x4f, 0xaf, 0xb7, 0xe5, 0x6e}};
// {6A2F2DBD-3E9D-4C08-90A7-415366D1CB19}
constexpr GUID kPreservedCtrlSpace = {0x6a2f2dbd, 0x3e9d, 0x4c08, {0x90, 0xa7, 0x41, 0x53, 0x66, 0xd1, 0xcb, 0x19}};
// {AFE3FF6D-EB6A-4021-BB2A-36BBF7A4C232}
constexpr GUID kPreservedAltGrave = {0xafe3ff6d, 0xeb6a, 0x4021, {0xbb, 0x2a, 0x36, 0xbb, 0xf7, 0xa4, 0xc2, 0x32}};
// GUID_LBI_INPUTMODE is not declared by every supported Windows SDK, even
// though Windows 8 and later require this value for the taskbar mode button.
constexpr GUID kLangBarInputMode = {0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
// The Japanese DBE virtual-key constants are likewise absent from some SDKs.
constexpr WPARAM kVirtualKeyDbeAlphanumeric = 0xf0;
constexpr WPARAM kVirtualKeyDbeHiragana = 0xf2;
// Keep the standard connection-point HRESULT values local because newer
// trimmed Windows SDK headers no longer expose the CONNECT_E_* aliases.
constexpr HRESULT kConnectNoConnection = static_cast<HRESULT>(0x80040200UL);
constexpr HRESULT kConnectAdviseLimit = static_cast<HRESULT>(0x80040201UL);
constexpr HRESULT kConnectCannotConnect = static_cast<HRESULT>(0x80040202UL);
constexpr wchar_t kDescription[] = L"Keynako Japanese IME";

struct PreservedKeyDefinition {
    GUID command;
    UINT virtual_key;
    UINT modifiers;
    const wchar_t *description;
};

constexpr PreservedKeyDefinition kPreservedKeys[] = {
    {kPreservedToggle, VK_KANJI, 0, L"Toggle Keynako input mode"},
    {kPreservedConvert, VK_CONVERT, 0, L"Convert the current Keynako composition"},
    {kPreservedCtrlSpace, VK_SPACE, TF_MOD_CONTROL, L"Toggle Keynako input mode (US keyboard)"},
    {kPreservedAltGrave, VK_OEM_3, TF_MOD_ALT, L"Toggle Keynako input mode (US keyboard)"},
};

constexpr UINT kMenuJapanese = 1;
constexpr UINT kMenuEnglish = 2;
constexpr UINT kMenuLiveConversion = 3;
constexpr UINT kMenuRefreshDictionary = 4;
constexpr UINT kMenuSettings = 5;
constexpr wchar_t kCandidateWindowClass[] = L"KeynakoCandidateWindow";
constexpr UINT kImprovementSubmissionComplete = WM_APP + 0x4b;
constexpr UINT_PTR kImprovementDismissTimer = 1;
constexpr char kDictionarySubmissionUrl[] = KEYNAKO_DICTIONARY_SUBMISSION_URL;
constexpr char kAppVersion[] = KEYNAKO_APP_VERSION;

HINSTANCE g_instance = nullptr;
std::atomic<long> g_objects{0};

std::wstring utf8_to_wide(const std::string &value) {
    if (value.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    std::wstring result(static_cast<std::size_t>(std::max(0, size)), L'\0');
    if (size > 0) MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size);
    return result;
}

std::string wide_to_utf8(const std::wstring &value) {
    if (value.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    std::string result(static_cast<std::size_t>(std::max(0, size)), '\0');
    if (size > 0) WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
    return result;
}

std::filesystem::path module_directory() {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(g_instance, path.data(), static_cast<DWORD>(path.size()));
    path.resize(length);
    return std::filesystem::path(path).parent_path();
}

std::string path_utf8(const std::filesystem::path &path) {
    return wide_to_utf8(path.wstring());
}

std::filesystem::path environment_path(const wchar_t *name) {
    const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required == 0) return {};
    std::wstring value(required, L'\0');
    const DWORD written = GetEnvironmentVariableW(name, value.data(), required);
    if (written == 0 || written >= required) return {};
    value.resize(written);
    return value;
}

struct ImprovementWorkerTask {
    HWND result_window = nullptr;
    UINT_PTR generation = 0;
    HMODULE retained_module = nullptr;
    std::wstring endpoint;
    std::string payload;
};

DWORD WINAPI improvement_worker_proc(void *parameter) {
    std::unique_ptr<ImprovementWorkerTask> task(
        static_cast<ImprovementWorkerTask *>(parameter));
    const bool success = keynako::windows::submit_improvement_https(
        task->endpoint, task->payload);
    PostMessageW(task->result_window, kImprovementSubmissionComplete,
                 success ? TRUE : FALSE,
                 static_cast<LPARAM>(task->generation));
    const HMODULE retained_module = task->retained_module;
    task.reset();
    FreeLibraryAndExitThread(retained_module, 0);
}

enum class ImprovementWindowState { prompt, sending, sent, failed };

class TextService;

class LanguageBarItem final : public ITfLangBarItemButton, public ITfSource {
public:
    explicit LanguageBarItem(TextService *owner);
    ~LanguageBarItem();

    STDMETHODIMP QueryInterface(REFIID iid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG value = --references_;
        if (value == 0) delete this;
        return value;
    }

    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO *info) override;
    STDMETHODIMP GetStatus(DWORD *status) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP GetTooltipString(BSTR *tooltip) override;
    STDMETHODIMP OnClick(TfLBIClick click, POINT point, const RECT *area) override;
    STDMETHODIMP InitMenu(ITfMenu *menu) override;
    STDMETHODIMP OnMenuSelect(UINT id) override;
    STDMETHODIMP GetIcon(HICON *icon) override;
    STDMETHODIMP GetText(BSTR *text) override;
    STDMETHODIMP AdviseSink(REFIID iid, IUnknown *unknown, DWORD *cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

    void detach_owner() { owner_ = nullptr; }
    void notify_mode_changed();

private:
    std::atomic<ULONG> references_{1};
    TextService *owner_;
    ITfLangBarItemSink *sink_ = nullptr;
    DWORD status_ = 0;
};

enum class EditAction { update, commit, cancel };

class EditSession final : public ITfEditSession {
public:
    EditSession(TextService *service, ITfContext *context, EditAction action);
    ~EditSession();
    STDMETHODIMP QueryInterface(REFIID iid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG value = --references_;
        if (value == 0) delete this;
        return value;
    }
    STDMETHODIMP DoEditSession(TfEditCookie edit_cookie) override;

private:
    std::atomic<ULONG> references_{1};
    TextService *service_;
    ITfContext *context_;
    EditAction action_;
};

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfCompositionSink {
public:
    TextService() { ++g_objects; }
    ~TextService() {
        remove_keyboard_hook();
        hide_candidates();
        hide_improvement_prompt();
        remove_language_bar();
        if (composition_) composition_->Release();
        if (thread_manager_) thread_manager_->Release();
        --g_objects;
    }

    STDMETHODIMP QueryInterface(REFIID iid, void **object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor || iid == IID_ITfTextInputProcessorEx) {
            *object = static_cast<ITfTextInputProcessorEx *>(this);
        } else if (iid == IID_ITfKeyEventSink) {
            *object = static_cast<ITfKeyEventSink *>(this);
        } else if (iid == IID_ITfCompositionSink) {
            *object = static_cast<ITfCompositionSink *>(this);
        }
        if (!*object) return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG value = --references_;
        if (value == 0) delete this;
        return value;
    }

    keynako::InputMode input_mode() const { return session_.mode(); }
    bool live_conversion() const { return session_.live_conversion(); }
    void set_input_mode(keynako::InputMode mode, ITfContext *context = nullptr) {
        if (session_.mode() == mode) return;
        if (!session_.raw_input().empty()) {
            // Keep the visible Japanese or English text when changing modes.
            // Canceling the TSF composition here used to erase it.
            const bool committed = context
                ? request_edit(context, EditAction::commit)
                : request_active_edit(EditAction::commit);
            if (!committed) return;
        }
        session_.set_mode(mode);
        sync_input_compartments();
        if (language_bar_) language_bar_->notify_mode_changed();
    }
    void toggle_input_mode(ITfContext *context = nullptr) {
        set_input_mode(session_.mode() == keynako::InputMode::japanese
                           ? keynako::InputMode::english
                           : keynako::InputMode::japanese,
                       context);
    }
    void toggle_live_conversion() {
        session_.set_live_conversion(!session_.live_conversion());
        if (language_bar_) language_bar_->notify_mode_changed();
        if (!session_.raw_input().empty()) request_active_edit(EditAction::update);
    }
    void open_settings() const {
        const auto executable = module_directory().parent_path() / L"Keynako.exe";
        ShellExecuteW(nullptr, L"open", executable.c_str(), nullptr, executable.parent_path().c_str(), SW_SHOWNORMAL);
    }
    void refresh_shared_dictionary(bool force = true) {
        const auto now = std::chrono::steady_clock::now();
        if (!force && last_dictionary_refresh_request_.time_since_epoch().count() != 0 &&
            now - last_dictionary_refresh_request_ < std::chrono::minutes(5)) return;
        if (!force) {
            std::vector<std::filesystem::path> cache_files;
            const auto local_app_data = environment_path(L"LOCALAPPDATA");
            const auto program_data = environment_path(L"ProgramData");
            if (!local_app_data.empty()) {
                cache_files.push_back(local_app_data / L"Keynako" / L"shared_dictionary.tsv");
            }
            if (!program_data.empty()) {
                cache_files.push_back(program_data / L"Keynako" / L"shared_dictionary.tsv");
            }
            std::error_code cache_error;
            for (const auto &cache_file : cache_files) {
                if (!std::filesystem::exists(cache_file, cache_error) || cache_error) {
                    cache_error.clear();
                    continue;
                }
                const auto modified = std::filesystem::last_write_time(cache_file, cache_error);
                if (!cache_error && std::filesystem::file_time_type::clock::now() - modified <
                                        std::chrono::minutes(5)) {
                    last_dictionary_refresh_request_ = now;
                    return;
                }
                break;
            }
        }
        last_dictionary_refresh_request_ = now;

        const auto executable = module_directory().parent_path() / L"Keynako.exe";
        std::error_code executable_error;
        if (!std::filesystem::exists(executable, executable_error) || executable_error) return;
        const wchar_t *argument = force
            ? L"--refresh-shared-dictionary"
            : L"--refresh-shared-dictionary-if-due";
        std::wstring command_line = L"\"" + executable.wstring() + L"\" " + argument;
        const auto working_directory = executable.parent_path().wstring();
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        const BOOL created = CreateProcessW(
            executable.c_str(), command_line.data(), nullptr, nullptr, FALSE,
            CREATE_NO_WINDOW, nullptr, working_directory.c_str(), &startup, &process);
        if (created) {
            CloseHandle(process.hThread);
            CloseHandle(process.hProcess);
        }
        if (force) {
            shared_submission_status_ = created
                ? L"共有辞書を更新中です"
                : L"共有辞書を更新できません";
            if (candidate_window_) InvalidateRect(candidate_window_, nullptr, TRUE);
        }
    }

    STDMETHODIMP Activate(ITfThreadMgr *thread_manager, TfClientId client_id) override {
        return ActivateEx(thread_manager, client_id, 0);
    }
    STDMETHODIMP ActivateEx(ITfThreadMgr *thread_manager, TfClientId client_id, DWORD) override {
        if (!thread_manager) return E_INVALIDARG;
        thread_manager_ = thread_manager;
        thread_manager_->AddRef();
        client_id_ = client_id;
        ITfKeystrokeMgr *keys = nullptr;
        const HRESULT result = thread_manager_->QueryInterface(IID_PPV_ARGS(&keys));
        if (SUCCEEDED(result)) {
            keys->AdviseKeyEventSink(client_id_, this, TRUE);
            for (const auto &definition : kPreservedKeys) {
                const TF_PRESERVEDKEY key{definition.virtual_key, definition.modifiers};
                keys->PreserveKey(client_id_, definition.command, &key,
                                  definition.description,
                                  static_cast<ULONG>(wcslen(definition.description)));
            }
            keys->Release();
        }
        install_keyboard_hook();
        initialize_language_bar();
        sync_input_compartments();
        session_.set_bundled_dictionary_path(path_utf8(
            module_directory() / L"azookey_dictionary" / L"Dictionary"));
        reload_shared_dictionary(true);
        return result;
    }
    STDMETHODIMP Deactivate() override {
        remove_keyboard_hook();
        if (thread_manager_) {
            ITfKeystrokeMgr *keys = nullptr;
            if (SUCCEEDED(thread_manager_->QueryInterface(IID_PPV_ARGS(&keys)))) {
                for (const auto &definition : kPreservedKeys) {
                    const TF_PRESERVEDKEY key{definition.virtual_key, definition.modifiers};
                    keys->UnpreserveKey(definition.command, &key);
                }
                keys->UnadviseKeyEventSink(client_id_);
                keys->Release();
            }
            remove_language_bar();
            thread_manager_->Release();
            thread_manager_ = nullptr;
        }
        session_.clear();
        hide_candidates();
        hide_improvement_prompt();
        return S_OK;
    }

    STDMETHODIMP OnSetFocus(BOOL) override { return S_OK; }
    STDMETHODIMP OnTestKeyDown(ITfContext *, WPARAM key, LPARAM key_data, BOOL *eaten) override {
        if (!eaten) return E_INVALIDARG;
        *eaten = handles_key(key, key_data) ? TRUE : FALSE;
        return S_OK;
    }
    STDMETHODIMP OnKeyDown(ITfContext *context, WPARAM key, LPARAM key_data, BOOL *eaten) override {
        if (!context || !eaten) return E_INVALIDARG;
        *eaten = FALSE;
        hide_improvement_prompt();
        refresh_shared_dictionary(false);
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool alt = (GetKeyState(VK_MENU) & 0x8000) != 0;
        const auto scan_code = static_cast<std::uint32_t>((key_data >> 16) & 0xff);
        const auto shortcut = keynako::windows::shortcut_action(
            static_cast<std::uint32_t>(key), scan_code, control, alt,
            !session_.raw_input().empty(), uses_japanese_keyboard());
        if (shortcut == keynako::windows::ShortcutAction::toggle_input_mode) {
            toggle_input_mode(context);
            *eaten = TRUE;
            return S_OK;
        }
        if (shortcut == keynako::windows::ShortcutAction::convert_or_cycle) {
            convert_or_cycle(context);
            *eaten = TRUE;
            return S_OK;
        }
        if (!handles_key(key, key_data)) return S_OK;

        BYTE keyboard[256]{};
        GetKeyboardState(keyboard);
        const bool shift = (keyboard[VK_SHIFT] & 0x80) != 0 ||
                           (GetKeyState(VK_SHIFT) & 0x8000) != 0 ||
                           (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

        if (key == VK_KANA || key == kVirtualKeyDbeHiragana) {
            set_input_mode(keynako::InputMode::japanese, context);
            *eaten = TRUE;
            return S_OK;
        }
        if (key == kVirtualKeyDbeAlphanumeric) {
            set_input_mode(keynako::InputMode::english, context);
            *eaten = TRUE;
            return S_OK;
        }
        EditAction action = EditAction::update;
        if (keynako::windows::is_candidate_selection_key(
                static_cast<std::uint32_t>(key), shift) &&
            session_.is_converting()) {
            if (!session_.select_candidate(static_cast<std::size_t>(key - '1'))) return S_OK;
            action = EditAction::commit;
        } else if ((key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9') ||
                   keynako::windows::is_oem_text_key(
                       static_cast<std::uint32_t>(key), scan_code)) {
            reload_shared_dictionary();
            WCHAR translated[4]{};
            char value = 0;
            if (keynako::windows::is_slash_text_key(
                    static_cast<std::uint32_t>(key), scan_code)) {
                // The virtual key reported for /? varies between active JIS,
                // US, and remapped layouts. The physical key and Shift state
                // are stable, so do not depend on ToUnicode for this key.
                value = keynako::windows::oem_text_fallback(
                    static_cast<std::uint32_t>(key), shift, scan_code);
            } else {
                const int count = ToUnicode(static_cast<UINT>(key), scan_code,
                                            keyboard, translated, 4, 0);
                if (count > 0 && translated[0] < 128) {
                    value = static_cast<char>(translated[0]);
                }
            }
            if (!value && keynako::windows::is_oem_text_key(
                              static_cast<std::uint32_t>(key), scan_code)) {
                value = keynako::windows::oem_text_fallback(
                    static_cast<std::uint32_t>(key), shift, scan_code);
            }
            if (!value) {
                value = static_cast<char>(
                    std::tolower(static_cast<unsigned char>(key)));
            }
            const bool literal_english =
                session_.mode() == keynako::InputMode::japanese &&
                ((key >= 'A' && key <= 'Z' && shift) ||
                 session_.has_literal_suffix());
            if (literal_english) {
                session_.append_literal_ascii(value);
            } else {
                session_.append_ascii(value);
            }
        } else if (key == VK_BACK) {
            if (session_.raw_input().empty()) return S_OK;
            if (!session_.cancel_conversion()) session_.backspace();
            action = session_.raw_input().empty() ? EditAction::cancel : EditAction::update;
        } else if (key == VK_SPACE && session_.has_literal_suffix()) {
            session_.append_literal_ascii(' ');
            action = EditAction::commit;
        } else if (key == VK_SPACE || key == VK_DOWN ||
                   key == VK_TAB || key == VK_NEXT) {
            if (session_.raw_input().empty()) return S_OK;
            reload_shared_dictionary();
            if (!session_.is_converting()) {
                if (session_.mode() == keynako::InputMode::japanese) add_zenzai_candidate();
                session_.begin_conversion();
            } else {
                session_.select_next();
            }
        } else if (key == VK_UP || key == VK_PRIOR) {
            if (session_.raw_input().empty()) return S_OK;
            if (!session_.is_converting()) session_.begin_conversion();
            session_.select_previous();
        } else if (key == VK_NONCONVERT) {
            if (session_.raw_input().empty()) {
                set_input_mode(keynako::InputMode::english, context);
                *eaten = TRUE;
                return S_OK;
            } else if (session_.select_reading()) {
                action = EditAction::commit;
            }
        } else if (key == VK_RETURN) {
            if (session_.raw_input().empty()) return S_OK;
            action = EditAction::commit;
        } else if (key == VK_ESCAPE) {
            if (session_.raw_input().empty()) return S_OK;
            action = session_.cancel_conversion() ? EditAction::update : EditAction::cancel;
        } else {
            return S_OK;
        }
        *eaten = TRUE;
        request_edit(context, action);
        return S_OK;
    }
    STDMETHODIMP OnTestKeyUp(ITfContext *, WPARAM, LPARAM, BOOL *eaten) override {
        if (!eaten) return E_INVALIDARG;
        *eaten = FALSE;
        return S_OK;
    }
    STDMETHODIMP OnKeyUp(ITfContext *, WPARAM, LPARAM, BOOL *eaten) override {
        if (!eaten) return E_INVALIDARG;
        *eaten = FALSE;
        return S_OK;
    }
    STDMETHODIMP OnPreservedKey(ITfContext *context, REFGUID guid, BOOL *eaten) override {
        if (!context || !eaten) return E_INVALIDARG;
        *eaten = FALSE;
        if (guid == kPreservedConvert) {
            if (!session_.raw_input().empty()) {
                convert_or_cycle(context);
                *eaten = TRUE;
            }
        } else if (guid == kPreservedToggle || guid == kPreservedCtrlSpace ||
                   guid == kPreservedAltGrave) {
            toggle_input_mode(context);
            *eaten = TRUE;
        }
        return S_OK;
    }
    STDMETHODIMP OnCompositionTerminated(TfEditCookie, ITfComposition *composition) override {
        if (composition_ == composition) {
            composition_->Release();
            composition_ = nullptr;
        }
        session_.clear();
        hide_candidates();
        return S_OK;
    }

    HRESULT apply_edit(TfEditCookie edit_cookie, ITfContext *context, EditAction action) {
        if (action == EditAction::cancel) {
            if (composition_) {
                ITfRange *range = nullptr;
                if (SUCCEEDED(composition_->GetRange(&range))) {
                    range->SetText(edit_cookie, 0, L"", 0);
                    range->Release();
                }
                ITfComposition *ending = composition_;
                composition_ = nullptr;
                ending->EndComposition(edit_cookie);
                ending->Release();
            }
            session_.clear();
            hide_candidates();
            return S_OK;
        }

        const auto improvement = action == EditAction::commit
            ? improvement_for_current_selection()
            : std::nullopt;
        const std::wstring text = utf8_to_wide(action == EditAction::commit ? session_.selected_text() : session_.display_text());

        bool inserted_at_selection = false;
        if (!composition_) {
            // Insert through the application's selection API so a non-empty
            // selection is replaced before the composition starts.
            ITfInsertAtSelection *insert_at_selection = nullptr;
            HRESULT result = context->QueryInterface(IID_PPV_ARGS(&insert_at_selection));
            if (FAILED(result)) return result;
            ITfRange *insertion_range = nullptr;
            result = insert_at_selection->InsertTextAtSelection(
                edit_cookie, TF_IAS_NO_DEFAULT_COMPOSITION, text.data(),
                static_cast<LONG>(text.size()), &insertion_range);
            insert_at_selection->Release();
            if (FAILED(result) || !insertion_range) {
                if (insertion_range) insertion_range->Release();
                return FAILED(result) ? result : E_FAIL;
            }
            ITfContextComposition *composition_context = nullptr;
            result = context->QueryInterface(IID_PPV_ARGS(&composition_context));
            if (SUCCEEDED(result)) {
                result = composition_context->StartComposition(
                    edit_cookie, insertion_range, this, &composition_);
                composition_context->Release();
            }
            insertion_range->Release();
            if (FAILED(result)) return result;
            if (!composition_) return E_FAIL;
            inserted_at_selection = true;
        }

        ITfRange *range = nullptr;
        HRESULT result = composition_->GetRange(&range);
        if (FAILED(result)) return result;
        // The first edit was already inserted by InsertTextAtSelection.
        // Subsequent edits replace the active composition range.
        if (!inserted_at_selection) {
            result = range->SetText(edit_cookie, 0, text.data(),
                                    static_cast<LONG>(text.size()));
        }
        if (SUCCEEDED(result) && action == EditAction::commit) {
            range->Collapse(edit_cookie, TF_ANCHOR_END);
            ITfComposition *ending = composition_;
            composition_ = nullptr;
            ending->EndComposition(edit_cookie);
            ending->Release();
            session_.clear();
            hide_candidates();
            if (improvement) show_improvement_prompt(*improvement);
        } else if (SUCCEEDED(result)) {
            if (session_.is_converting()) {
                show_candidates(edit_cookie, context, range);
            } else {
                hide_candidates();
            }
        }
        range->Release();
        return result;
    }

private:
    std::atomic<ULONG> references_{1};
    ITfThreadMgr *thread_manager_ = nullptr;
    TfClientId client_id_ = TF_CLIENTID_NULL;
    ITfComposition *composition_ = nullptr;
    keynako::ImeSession session_;
    std::unique_ptr<keynako::ZenzaiClient> zenzai_;
    HWND candidate_window_ = nullptr;
    HWND improvement_window_ = nullptr;
    HWND candidate_owner_ = nullptr;
    RECT last_candidate_rectangle_{0, 0, 0, 0};
    ImprovementWindowState improvement_window_state_ = ImprovementWindowState::prompt;
    std::optional<keynako::windows::ImprovementSubmission> pending_improvement_;
    std::unordered_set<std::string> reported_improvements_;
    UINT_PTR improvement_generation_ = 0;
    LanguageBarItem *language_bar_ = nullptr;
    std::filesystem::path shared_dictionary_path_;
    std::filesystem::file_time_type shared_dictionary_write_time_{};
    std::chrono::steady_clock::time_point last_dictionary_check_{};
    std::chrono::steady_clock::time_point last_dictionary_refresh_request_{};
    std::wstring shared_submission_status_;
    HHOOK keyboard_hook_ = nullptr;
    bool physical_shortcut_down_ = false;
    inline static thread_local TextService *keyboard_hook_owner_ = nullptr;

    static LRESULT CALLBACK keyboard_hook_proc(int code, WPARAM key, LPARAM key_data) {
        TextService *owner = keyboard_hook_owner_;
        if (!owner || code != HC_ACTION) {
            return CallNextHookEx(owner ? owner->keyboard_hook_ : nullptr, code, key,
                                  key_data);
        }
        return owner->handle_keyboard_hook(key, key_data);
    }

    LRESULT handle_keyboard_hook(WPARAM key, LPARAM key_data) {
        const auto data = static_cast<ULONG_PTR>(key_data);
        const auto scan_code = static_cast<std::uint32_t>((data >> 16) & 0xff);
        const bool japanese_keyboard = uses_japanese_keyboard();
        const bool convert_key = keynako::windows::is_convert_key(
            static_cast<std::uint32_t>(key), scan_code);
        const bool hankaku_zenkaku_key =
            keynako::windows::is_hankaku_zenkaku_key(
                static_cast<std::uint32_t>(key), scan_code,
                japanese_keyboard);
        if (!convert_key && !hankaku_zenkaku_key) {
            return CallNextHookEx(keyboard_hook_, HC_ACTION, key, key_data);
        }

        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool alt = (data & (static_cast<ULONG_PTR>(1) << 29)) != 0;
        if (control || alt) {
            return CallNextHookEx(keyboard_hook_, HC_ACTION, key, key_data);
        }

        const bool released = (data & (static_cast<ULONG_PTR>(1) << 31)) != 0;
        if (released) {
            if (physical_shortcut_down_) {
                physical_shortcut_down_ = false;
                return 1;
            }
            return CallNextHookEx(keyboard_hook_, HC_ACTION, key, key_data);
        }

        const auto action = keynako::windows::shortcut_action(
            static_cast<std::uint32_t>(key), scan_code, false, false,
            !session_.raw_input().empty(), japanese_keyboard);
        if (action == keynako::windows::ShortcutAction::none) {
            return CallNextHookEx(keyboard_hook_, HC_ACTION, key, key_data);
        }

        const bool was_down = (data & (static_cast<ULONG_PTR>(1) << 30)) != 0;
        if (!was_down && !physical_shortcut_down_) {
            if (action == keynako::windows::ShortcutAction::toggle_input_mode) {
                toggle_input_mode();
            } else {
                convert_or_cycle_active();
            }
        }
        physical_shortcut_down_ = true;
        return 1;
    }

    void install_keyboard_hook() {
        if (keyboard_hook_) return;
        if (keyboard_hook_owner_ && keyboard_hook_owner_ != this) {
            keyboard_hook_owner_->remove_keyboard_hook();
        }
        keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD, keyboard_hook_proc, nullptr,
                                           GetCurrentThreadId());
        if (keyboard_hook_) keyboard_hook_owner_ = this;
    }

    void remove_keyboard_hook() {
        if (keyboard_hook_) {
            UnhookWindowsHookEx(keyboard_hook_);
            keyboard_hook_ = nullptr;
        }
        if (keyboard_hook_owner_ == this) keyboard_hook_owner_ = nullptr;
        physical_shortcut_down_ = false;
    }

    void convert_or_cycle(ITfContext *context) {
        if (session_.raw_input().empty()) return;
        reload_shared_dictionary();
        if (!session_.is_converting()) {
            if (session_.mode() == keynako::InputMode::japanese) add_zenzai_candidate();
            session_.begin_conversion();
        } else {
            session_.select_next();
        }
        request_edit(context, EditAction::update);
    }

    void convert_or_cycle_active() {
        if (!thread_manager_) return;
        ITfDocumentMgr *document = nullptr;
        if (FAILED(thread_manager_->GetFocus(&document)) || !document) return;
        ITfContext *context = nullptr;
        if (SUCCEEDED(document->GetTop(&context)) && context) {
            convert_or_cycle(context);
            context->Release();
        }
        document->Release();
    }

    bool handles_key(WPARAM key, LPARAM key_data) const {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool alt = (GetKeyState(VK_MENU) & 0x8000) != 0;
        const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0 ||
                           (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
        const auto scan_code = static_cast<std::uint32_t>((key_data >> 16) & 0xff);
        if (keynako::windows::shortcut_action(static_cast<std::uint32_t>(key), scan_code,
                                              control, alt,
                                              !session_.raw_input().empty(),
                                              uses_japanese_keyboard()) !=
            keynako::windows::ShortcutAction::none) return true;
        if (control || alt) return false;
        if (key == VK_KANJI || key == VK_KANA || key == kVirtualKeyDbeHiragana ||
            key == kVirtualKeyDbeAlphanumeric || key == VK_NONCONVERT) return true;
        const bool japanese = session_.mode() == keynako::InputMode::japanese;
        if (japanese && key >= 'A' && key <= 'Z') return true;
        if (japanese && key >= '0' && key <= '9' &&
            (!session_.is_converting() || shift)) return true;
        if (japanese && keynako::windows::is_oem_text_key(
                            static_cast<std::uint32_t>(key), scan_code)) return true;
        if (session_.raw_input().empty()) return false;
        if (session_.is_converting() &&
            keynako::windows::is_candidate_selection_key(
                static_cast<std::uint32_t>(key), shift)) return true;
        return key == VK_BACK || key == VK_SPACE || key == VK_UP ||
               key == VK_DOWN || key == VK_TAB || key == VK_PRIOR || key == VK_NEXT ||
               key == VK_RETURN || key == VK_ESCAPE;
    }

    static bool uses_japanese_keyboard() {
        // GetKeyboardType(0) returns 7 for a Japanese 106/109-key keyboard.
        // This lets its physical Hankaku/Zenkaku key keep working when the
        // active logical layout is US, without stealing bare Backquote from an
        // actual US 101/102-key keyboard.
        return GetKeyboardType(0) == 0x07;
    }

    bool request_edit(ITfContext *context, EditAction action) {
        if (!context) return false;
        auto *edit = new EditSession(this, context, action);
        HRESULT session_result = E_FAIL;
        const HRESULT request_result = context->RequestEditSession(
            client_id_, edit, TF_ES_SYNC | TF_ES_READWRITE, &session_result);
        edit->Release();
        return SUCCEEDED(request_result) && SUCCEEDED(session_result);
    }

    bool request_active_edit(EditAction action) {
        if (!thread_manager_) return false;
        ITfDocumentMgr *document = nullptr;
        if (FAILED(thread_manager_->GetFocus(&document)) || !document) return false;
        bool edited = false;
        ITfContext *context = nullptr;
        if (SUCCEEDED(document->GetTop(&context)) && context) {
            edited = request_edit(context, action);
            context->Release();
        }
        document->Release();
        return edited;
    }

    void initialize_language_bar() {
        if (!thread_manager_ || language_bar_) return;
        auto *item = new LanguageBarItem(this);
        ITfLangBarItemMgr *manager = nullptr;
        if (SUCCEEDED(thread_manager_->QueryInterface(IID_PPV_ARGS(&manager)))) {
            if (SUCCEEDED(manager->AddItem(item))) language_bar_ = item;
            manager->Release();
        }
        if (!language_bar_) item->Release();
    }

    void remove_language_bar() {
        if (!language_bar_) return;
        if (thread_manager_) {
            ITfLangBarItemMgr *manager = nullptr;
            if (SUCCEEDED(thread_manager_->QueryInterface(IID_PPV_ARGS(&manager)))) {
                manager->RemoveItem(language_bar_);
                manager->Release();
            }
        }
        language_bar_->detach_owner();
        language_bar_->Release();
        language_bar_ = nullptr;
    }

    void set_compartment_value(REFGUID guid, LONG value) {
        if (!thread_manager_) return;
        ITfCompartmentMgr *manager = nullptr;
        if (FAILED(thread_manager_->QueryInterface(IID_PPV_ARGS(&manager)))) return;
        ITfCompartment *compartment = nullptr;
        if (SUCCEEDED(manager->GetCompartment(guid, &compartment))) {
            VARIANT variant;
            VariantInit(&variant);
            variant.vt = VT_I4;
            variant.lVal = value;
            compartment->SetValue(client_id_, &variant);
            compartment->Release();
        }
        manager->Release();
    }

    void sync_input_compartments() {
        const bool japanese = session_.mode() == keynako::InputMode::japanese;
        // Keep the active text service open even in direct English mode. Closing
        // it stops key callbacks, including Hankaku/Zenkaku mode switching.
        set_compartment_value(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, 1);
        set_compartment_value(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,
                              japanese ? TF_CONVERSIONMODE_NATIVE | TF_CONVERSIONMODE_FULLSHAPE |
                                             TF_CONVERSIONMODE_ROMAN
                                       : TF_CONVERSIONMODE_ALPHANUMERIC);
    }

    void reload_shared_dictionary(bool force = false) {
        const auto now = std::chrono::steady_clock::now();
        if (!force && last_dictionary_check_.time_since_epoch().count() != 0 &&
            now - last_dictionary_check_ < std::chrono::seconds(5)) return;
        last_dictionary_check_ = now;

        std::vector<std::filesystem::path> files;
        const auto program_data = environment_path(L"ProgramData");
        const auto local_app_data = environment_path(L"LOCALAPPDATA");
        if (!local_app_data.empty()) files.push_back(local_app_data / L"Keynako" / L"shared_dictionary.tsv");
        if (!program_data.empty()) files.push_back(program_data / L"Keynako" / L"shared_dictionary.tsv");
        files.push_back(module_directory() / L"bundled_shared_dictionary.tsv");

        std::error_code error;
        for (const auto &file : files) {
            if (!std::filesystem::exists(file, error) || error) {
                error.clear();
                continue;
            }
            const auto write_time = std::filesystem::last_write_time(file, error);
            if (error) {
                error.clear();
                continue;
            }
            if (file == shared_dictionary_path_ && write_time == shared_dictionary_write_time_) return;

            std::ifstream stream(file, std::ios::binary);
            if (!stream) continue;
            std::vector<keynako::DictionaryEntry> entries;
            std::string line;
            bool valid_header = false;
            while (std::getline(stream, line)) {
                if (!line.empty() && line.back() == '\r') line.pop_back();
                if (line.rfind("# keynako-shared-dictionary-v1", 0) == 0) {
                    valid_header = true;
                    continue;
                }
                if (line.empty() || line.front() == '#') continue;
                const auto first_tab = line.find('\t');
                const auto second_tab = first_tab == std::string::npos
                    ? std::string::npos
                    : line.find('\t', first_tab + 1);
                if (first_tab == std::string::npos || second_tab == std::string::npos) continue;
                try {
                    const int importance = std::clamp(std::stoi(line.substr(0, first_tab)), 1, 5);
                    std::string reading = line.substr(first_tab + 1, second_tab - first_tab - 1);
                    const auto third_tab = line.find('\t', second_tab + 1);
                    std::string value = third_tab == std::string::npos
                        ? line.substr(second_tab + 1)
                        : line.substr(second_tab + 1, third_tab - second_tab - 1);
                    if (!reading.empty() && !value.empty()) {
                        keynako::DictionaryEntry entry{std::move(reading), std::move(value), importance};
                        if (third_tab != std::string::npos) {
                            const auto fourth_tab = line.find('\t', third_tab + 1);
                            const auto fifth_tab = fourth_tab == std::string::npos
                                ? std::string::npos
                                : line.find('\t', fourth_tab + 1);
                            if (fourth_tab != std::string::npos && fifth_tab != std::string::npos) {
                                entry.word_weight = std::stof(line.substr(third_tab + 1, fourth_tab - third_tab - 1));
                                entry.lcid = std::stoi(line.substr(fourth_tab + 1, fifth_tab - fourth_tab - 1));
                                entry.rcid = std::stoi(line.substr(fifth_tab + 1));
                                entry.has_word_weight = true;
                            }
                        }
                        entries.push_back(std::move(entry));
                    }
                } catch (const std::exception &) {
                    continue;
                }
            }
            if (!valid_header || entries.empty()) continue;
            session_.set_user_dictionary(std::move(entries));
            shared_dictionary_path_ = file;
            shared_dictionary_write_time_ = write_time;
            return;
        }
    }

    bool add_zenzai_candidate() {
        if (!zenzai_) {
            const auto directory = module_directory();
            std::filesystem::path model = directory / L"zenzai" / L"zenz-v3.2-xsmall-gguf" / L"ggml-model-Q5_K_M.gguf";
            wchar_t configured[32768]{};
            const DWORD length = GetEnvironmentVariableW(L"KEYNAKO_ZENZAI_MODEL", configured, 32768);
            if (length > 0 && length < 32768) model = configured;
            zenzai_ = std::make_unique<keynako::ZenzaiClient>(
                path_utf8(directory / L"keynako_zenzai.exe"), path_utf8(model));
        }
        if (!zenzai_->available()) return false;
        const auto generated = zenzai_->generate(session_.reading());
        if (generated.empty()) return false;
        session_.insert_zenzai_candidate(generated);
        return true;
    }

    static const std::wstring &dictionary_submission_endpoint() {
        static const std::wstring endpoint = utf8_to_wide(kDictionarySubmissionUrl);
        return endpoint;
    }

    static bool reportable_reading(const std::string &reading) {
        if (reading.empty()) return false;
        for (const wchar_t character : utf8_to_wide(reading)) {
            const bool hiragana = character >= 0x3041 && character <= 0x3096;
            const bool ascii = (character >= L'a' && character <= L'z') ||
                               (character >= L'A' && character <= L'Z') ||
                               (character >= L'0' && character <= L'9');
            if (!hiragana && !ascii) return false;
        }
        return true;
    }

    static std::string improvement_pair_key(
        const keynako::windows::ImprovementSubmission &submission) {
        return submission.reading + '\x1f' + submission.word;
    }

    std::optional<keynako::windows::ImprovementSubmission>
    improvement_for_current_selection() const {
        const auto &endpoint = dictionary_submission_endpoint();
        if (endpoint.rfind(L"https://", 0) != 0 ||
            session_.mode() != keynako::InputMode::japanese ||
            !session_.is_converting() || session_.selected_index() == 0 ||
            session_.selected_index() >= session_.candidates().size() ||
            !reportable_reading(session_.reading())) {
            return std::nullopt;
        }

        const auto &selected = session_.candidates()[session_.selected_index()];
        if (selected.text.empty() || selected.source == "reading" ||
            selected.source == "katakana" || selected.source == "latin" ||
            selected.source == "shared") {
            return std::nullopt;
        }
        const std::string &suggested = session_.candidates().front().text;
        if (suggested.size() > selected.text.size() &&
            suggested.compare(0, selected.text.size(), selected.text) == 0) {
            return std::nullopt;
        }

        keynako::windows::ImprovementSubmission submission{
            selected.text, session_.reading(), session_.selected_index()};
        if (reported_improvements_.count(improvement_pair_key(submission)) != 0) {
            return std::nullopt;
        }
        return submission;
    }

    void paint_improvement_window(HWND window) {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        FillRect(dc, &client, GetSysColorBrush(COLOR_WINDOW));
        const UINT dpi = GetDpiForWindow(window);
        HFONT title_font = CreateFontW(
            -MulDiv(14, static_cast<int>(dpi), 96), 0, 0, 0, FW_SEMIBOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Yu Gothic UI");
        HFONT detail_font = CreateFontW(
            -MulDiv(12, static_cast<int>(dpi), 96), 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Yu Gothic UI");
        HGDIOBJ old_font = SelectObject(dc, title_font);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));

        const wchar_t *title = L"共有変換辞書へ改善を送信";
        if (improvement_window_state_ == ImprovementWindowState::sending) {
            title = L"改善を送信中…";
        } else if (improvement_window_state_ == ImprovementWindowState::sent) {
            title = L"改善を送信した";
        } else if (improvement_window_state_ == ImprovementWindowState::failed) {
            title = L"送信できなかった・クリックで再試行";
        }
        RECT title_rect{MulDiv(16, static_cast<int>(dpi), 96),
                        MulDiv(8, static_cast<int>(dpi), 96),
                        client.right - MulDiv(48, static_cast<int>(dpi), 96),
                        MulDiv(39, static_cast<int>(dpi), 96)};
        DrawTextW(dc, title, -1, &title_rect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);

        SelectObject(dc, detail_font);
        SetTextColor(dc, GetSysColor(COLOR_GRAYTEXT));
        if (pending_improvement_) {
            const std::wstring detail = L"「" + utf8_to_wide(pending_improvement_->word) +
                L"」（" + utf8_to_wide(pending_improvement_->reading) + L"）・第" +
                std::to_wstring(pending_improvement_->selected_index + 1) + L"候補";
            RECT detail_rect{MulDiv(16, static_cast<int>(dpi), 96),
                             MulDiv(36, static_cast<int>(dpi), 96),
                             client.right - MulDiv(48, static_cast<int>(dpi), 96),
                             client.bottom - MulDiv(7, static_cast<int>(dpi), 96)};
            DrawTextW(dc, detail.c_str(), -1, &detail_rect,
                      DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);
        }

        SelectObject(dc, title_font);
        SetTextColor(dc, GetSysColor(COLOR_GRAYTEXT));
        RECT close_rect{client.right - MulDiv(44, static_cast<int>(dpi), 96),
                        0, client.right, client.bottom};
        DrawTextW(dc, L"×", -1, &close_rect,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, old_font);
        DeleteObject(detail_font);
        DeleteObject(title_font);
        EndPaint(window, &paint);
    }

    void show_improvement_prompt(
        const keynako::windows::ImprovementSubmission &submission) {
        hide_improvement_prompt();
        pending_improvement_ = submission;
        improvement_window_state_ = ImprovementWindowState::prompt;
        ++improvement_generation_;
        if (!ensure_candidate_window_class()) {
            pending_improvement_.reset();
            return;
        }

        HWND owner = IsWindow(candidate_owner_) ? candidate_owner_ : GetFocus();
        improvement_window_ = CreateWindowExW(
            WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
            kCandidateWindowClass, L"Keynako improvement", WS_POPUP,
            0, 0, 440, 78, owner, nullptr, g_instance, this);
        if (!improvement_window_) {
            pending_improvement_.reset();
            return;
        }
        constexpr DWORD kRoundedWindowPreference = 2;
        constexpr auto kWindowCornerPreference = static_cast<DWMWINDOWATTRIBUTE>(33);
        DwmSetWindowAttribute(improvement_window_, kWindowCornerPreference,
                              &kRoundedWindowPreference,
                              sizeof(kRoundedWindowPreference));

        const UINT dpi = GetDpiForWindow(improvement_window_);
        const int width = MulDiv(440, static_cast<int>(dpi), 96);
        const int height = MulDiv(78, static_cast<int>(dpi), 96);
        int left = last_candidate_rectangle_.left;
        int top = last_candidate_rectangle_.top;
        if (last_candidate_rectangle_.right <= last_candidate_rectangle_.left) {
            POINT cursor{};
            GetCursorPos(&cursor);
            left = cursor.x;
            top = cursor.y + MulDiv(4, static_cast<int>(dpi), 96);
        }
        RECT popup{left, top, left + width, top + height};
        MONITORINFO monitor_info{sizeof(monitor_info)};
        if (GetMonitorInfoW(MonitorFromRect(&popup, MONITOR_DEFAULTTONEAREST),
                            &monitor_info)) {
            left = std::clamp(left, static_cast<int>(monitor_info.rcWork.left),
                              std::max(static_cast<int>(monitor_info.rcWork.left),
                                       static_cast<int>(monitor_info.rcWork.right) - width));
            top = std::clamp(top, static_cast<int>(monitor_info.rcWork.top),
                             std::max(static_cast<int>(monitor_info.rcWork.top),
                                      static_cast<int>(monitor_info.rcWork.bottom) - height));
        }
        SetWindowPos(improvement_window_, HWND_TOPMOST, left, top, width, height,
                     SWP_NOACTIVATE | SWP_SHOWWINDOW);
        SetTimer(improvement_window_, kImprovementDismissTimer, 8000, nullptr);
    }

    void hide_improvement_prompt() {
        ++improvement_generation_;
        pending_improvement_.reset();
        if (improvement_window_) {
            const HWND window = improvement_window_;
            KillTimer(window, kImprovementDismissTimer);
            DestroyWindow(window);
            if (improvement_window_ == window) improvement_window_ = nullptr;
        }
    }

    void submit_pending_improvement() {
        if (!improvement_window_ || !pending_improvement_) return;
        KillTimer(improvement_window_, kImprovementDismissTimer);
        improvement_window_state_ = ImprovementWindowState::sending;
        InvalidateRect(improvement_window_, nullptr, TRUE);
        ++improvement_generation_;

        std::wstring module_path(32768, L'\0');
        const DWORD module_path_length = GetModuleFileNameW(
            g_instance, module_path.data(), static_cast<DWORD>(module_path.size()));
        if (module_path_length == 0 ||
            module_path_length >= static_cast<DWORD>(module_path.size())) {
            improvement_window_state_ = ImprovementWindowState::failed;
            InvalidateRect(improvement_window_, nullptr, TRUE);
            SetTimer(improvement_window_, kImprovementDismissTimer, 8000, nullptr);
            return;
        }
        module_path.resize(module_path_length);
        HMODULE retained_module = LoadLibraryW(module_path.c_str());
        if (!retained_module) {
            improvement_window_state_ = ImprovementWindowState::failed;
            InvalidateRect(improvement_window_, nullptr, TRUE);
            SetTimer(improvement_window_, kImprovementDismissTimer, 8000, nullptr);
            return;
        }

        auto *task = new (std::nothrow) ImprovementWorkerTask{
            improvement_window_, improvement_generation_, retained_module,
            dictionary_submission_endpoint(),
            keynako::windows::build_improvement_payload(
                *pending_improvement_, kAppVersion)};
        if (!task) {
            FreeLibrary(retained_module);
            improvement_window_state_ = ImprovementWindowState::failed;
            InvalidateRect(improvement_window_, nullptr, TRUE);
            SetTimer(improvement_window_, kImprovementDismissTimer, 8000, nullptr);
            return;
        }
        HANDLE thread = CreateThread(nullptr, 0, improvement_worker_proc, task, 0, nullptr);
        if (!thread) {
            delete task;
            FreeLibrary(retained_module);
            improvement_window_state_ = ImprovementWindowState::failed;
            InvalidateRect(improvement_window_, nullptr, TRUE);
            SetTimer(improvement_window_, kImprovementDismissTimer, 8000, nullptr);
            return;
        }
        CloseHandle(thread);
    }

    bool submit_candidate_to_shared_storage(std::size_t index) {
        if (index >= session_.candidates().size()) return false;
        const auto helper = module_directory() / L"KeynakoDictionarySubmit.exe";
        std::error_code helper_error;
        if (!std::filesystem::exists(helper, helper_error) || helper_error) return false;
        const std::string payload = keynako::windows::shared_candidate_payload(
            session_.candidates()[index].text, session_.reading());
        if (payload.size() > MAXDWORD) return false;

        SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
        HANDLE input_read = nullptr;
        HANDLE input_write = nullptr;
        if (!CreatePipe(&input_read, &input_write, &security, 0)) return false;
        if (!SetHandleInformation(input_write, HANDLE_FLAG_INHERIT, 0)) {
            CloseHandle(input_read);
            CloseHandle(input_write);
            return false;
        }
        HANDLE null_output = CreateFileW(L"NUL", GENERIC_WRITE,
                                         FILE_SHARE_READ | FILE_SHARE_WRITE,
                                         &security, OPEN_EXISTING,
                                         FILE_ATTRIBUTE_NORMAL, nullptr);
        if (null_output == INVALID_HANDLE_VALUE) {
            CloseHandle(input_read);
            CloseHandle(input_write);
            return false;
        }

        SIZE_T attribute_bytes = 0;
        InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_bytes);
        std::vector<unsigned char> attribute_buffer(attribute_bytes);
        auto *attributes = reinterpret_cast<PPROC_THREAD_ATTRIBUTE_LIST>(
            attribute_buffer.data());
        const bool attributes_initialized = attribute_bytes > 0 &&
            InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_bytes);
        bool attributes_ready = attributes_initialized;
        HANDLE inherited_handles[] = {input_read, null_output};
        if (attributes_ready) {
            attributes_ready = UpdateProcThreadAttribute(
                attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                inherited_handles, sizeof(inherited_handles), nullptr, nullptr);
        }

        STARTUPINFOEXW startup{};
        startup.StartupInfo.cb = sizeof(startup);
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startup.StartupInfo.hStdInput = input_read;
        startup.StartupInfo.hStdOutput = null_output;
        startup.StartupInfo.hStdError = null_output;
        startup.lpAttributeList = attributes_ready ? attributes : nullptr;
        PROCESS_INFORMATION process{};
        std::wstring command_line = L"\"" + helper.wstring() + L"\"";
        const auto working_directory = helper.parent_path().wstring();
        const BOOL created = attributes_ready && CreateProcessW(
            helper.c_str(), command_line.data(), nullptr, nullptr, TRUE,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr,
            working_directory.c_str(), &startup.StartupInfo, &process);

        if (attributes_initialized) DeleteProcThreadAttributeList(attributes);
        CloseHandle(input_read);
        CloseHandle(null_output);
        if (!created) {
            CloseHandle(input_write);
            return false;
        }

        DWORD written = 0;
        const BOOL sent = WriteFile(input_write, payload.data(),
                                    static_cast<DWORD>(payload.size()),
                                    &written, nullptr);
        CloseHandle(input_write);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        return sent && written == static_cast<DWORD>(payload.size());
    }

    static LRESULT CALLBACK candidate_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
        auto *service = reinterpret_cast<TextService *>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
            service = static_cast<TextService *>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(service));
        }
        if (!service) return DefWindowProcW(window, message, wparam, lparam);
        if (window == service->improvement_window_) {
            switch (message) {
                case WM_PAINT:
                    service->paint_improvement_window(window);
                    return 0;
                case WM_ERASEBKGND:
                    return 1;
                case WM_MOUSEACTIVATE:
                    return MA_NOACTIVATE;
                case WM_TIMER:
                    if (wparam == kImprovementDismissTimer) {
                        service->hide_improvement_prompt();
                    }
                    return 0;
                case WM_LBUTTONDOWN: {
                    const UINT dpi = GetDpiForWindow(window);
                    RECT client{};
                    GetClientRect(window, &client);
                    const int close_width = MulDiv(44, static_cast<int>(dpi), 96);
                    if (GET_X_LPARAM(lparam) >= client.right - close_width ||
                        service->improvement_window_state_ == ImprovementWindowState::sent) {
                        service->hide_improvement_prompt();
                    } else if (service->improvement_window_state_ == ImprovementWindowState::prompt ||
                               service->improvement_window_state_ == ImprovementWindowState::failed) {
                        service->submit_pending_improvement();
                    }
                    return 0;
                }
                case kImprovementSubmissionComplete:
                    if (static_cast<UINT_PTR>(lparam) == service->improvement_generation_) {
                        KillTimer(window, kImprovementDismissTimer);
                        service->improvement_window_state_ = wparam != FALSE
                            ? ImprovementWindowState::sent
                            : ImprovementWindowState::failed;
                        if (wparam != FALSE && service->pending_improvement_) {
                            service->reported_improvements_.insert(
                                service->improvement_pair_key(*service->pending_improvement_));
                        }
                        InvalidateRect(window, nullptr, TRUE);
                        SetTimer(window, kImprovementDismissTimer,
                                 wparam != FALSE ? 1600 : 8000, nullptr);
                    }
                    return 0;
                case WM_NCDESTROY:
                    if (service->improvement_window_ == window) {
                        service->improvement_window_ = nullptr;
                    }
                    return DefWindowProcW(window, message, wparam, lparam);
                default:
                    return DefWindowProcW(window, message, wparam, lparam);
            }
        }
        switch (message) {
            case WM_PAINT: service->paint_candidate_window(window); return 0;
            case WM_ERASEBKGND: return 1;
            case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
            case WM_LBUTTONDOWN:
            case WM_LBUTTONDBLCLK:
            case WM_RBUTTONDOWN: {
                const UINT dpi = GetDpiForWindow(window);
                const int row_height = MulDiv(36, static_cast<int>(dpi), 96);
                const int row = GET_Y_LPARAM(lparam) / std::max(1, row_height);
                const std::size_t page_start = (service->session_.selected_index() / 9) * 9;
                const std::size_t index = page_start + static_cast<std::size_t>(std::max(0, row));
                if (index < service->session_.candidates().size() && row < 9) {
                    if (message == WM_RBUTTONDOWN) {
                        const bool started =
                            service->submit_candidate_to_shared_storage(index);
                        service->shared_submission_status_ = started
                            ? L"共有ストレージへ送信を開始しました"
                            : L"共有ストレージへ送信できません";
                        InvalidateRect(window, nullptr, TRUE);
                    } else if (service->session_.select_candidate(index)) {
                        service->request_active_edit(message == WM_LBUTTONDBLCLK
                                                         ? EditAction::commit
                                                         : EditAction::update);
                    }
                }
                return 0;
            }
            case WM_NCDESTROY:
                if (service->candidate_window_ == window) {
                    service->candidate_window_ = nullptr;
                }
                return DefWindowProcW(window, message, wparam, lparam);
            case WM_RBUTTONUP:
            case WM_CONTEXTMENU: return 0;
            default: return DefWindowProcW(window, message, wparam, lparam);
        }
    }

    bool ensure_candidate_window_class() const {
        WNDCLASSEXW existing{};
        existing.cbSize = sizeof(existing);
        if (GetClassInfoExW(g_instance, kCandidateWindowClass, &existing)) return true;
        WNDCLASSEXW window_class{};
        window_class.cbSize = sizeof(window_class);
        window_class.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW;
        window_class.lpfnWndProc = candidate_window_proc;
        window_class.hInstance = g_instance;
        window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        window_class.hbrBackground = static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
        window_class.lpszClassName = kCandidateWindowClass;
        return RegisterClassExW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }

    void paint_candidate_window(HWND window) {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT client{};
        GetClientRect(window, &client);
        FillRect(dc, &client, GetSysColorBrush(COLOR_WINDOW));
        const UINT dpi = GetDpiForWindow(window);
        const int row_height = MulDiv(36, static_cast<int>(dpi), 96);
        const int footer_height = MulDiv(29, static_cast<int>(dpi), 96);
        HFONT font = CreateFontW(-MulDiv(15, static_cast<int>(dpi), 96), 0, 0, 0,
                                 FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH | FF_DONTCARE, L"Yu Gothic UI");
        HGDIOBJ old_font = SelectObject(dc, font);
        SetBkMode(dc, TRANSPARENT);

        const std::size_t page_start = (session_.selected_index() / 9) * 9;
        const std::size_t page_end = std::min(page_start + 9, session_.candidates().size());
        for (std::size_t index = page_start; index < page_end; ++index) {
            RECT row{0, static_cast<LONG>((index - page_start) * row_height),
                     client.right, static_cast<LONG>((index - page_start + 1) * row_height)};
            const bool selected = index == session_.selected_index();
            if (selected) {
                RECT highlight = row;
                InflateRect(&highlight, -MulDiv(5, static_cast<int>(dpi), 96),
                            -MulDiv(3, static_cast<int>(dpi), 96));
                HBRUSH highlight_brush = GetSysColorBrush(COLOR_HIGHLIGHT);
                HGDIOBJ previous_brush = SelectObject(dc, highlight_brush);
                HGDIOBJ previous_pen = SelectObject(dc, GetStockObject(NULL_PEN));
                RoundRect(dc, highlight.left, highlight.top, highlight.right, highlight.bottom,
                          MulDiv(10, static_cast<int>(dpi), 96),
                          MulDiv(10, static_cast<int>(dpi), 96));
                SelectObject(dc, previous_pen);
                SelectObject(dc, previous_brush);
            }
            SetTextColor(dc, GetSysColor(selected ? COLOR_HIGHLIGHTTEXT : COLOR_WINDOWTEXT));

            RECT number = row;
            number.left += MulDiv(12, static_cast<int>(dpi), 96);
            number.right = number.left + MulDiv(28, static_cast<int>(dpi), 96);
            const std::wstring number_text = std::to_wstring(index - page_start + 1);
            DrawTextW(dc, number_text.c_str(), -1, &number,
                      DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

            RECT value = row;
            value.left += MulDiv(48, static_cast<int>(dpi), 96);
            value.right -= MulDiv(72, static_cast<int>(dpi), 96);
            const std::wstring candidate_text = utf8_to_wide(session_.candidates()[index].text);
            DrawTextW(dc, candidate_text.c_str(), -1, &value,
                      DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS);

            const std::string &source = session_.candidates()[index].source;
            const wchar_t *source_text = source == "zenzai" ? L"Zenzai" : source == "shared" ? L"共有" : L"";
            if (*source_text) {
                RECT source_rect = row;
                source_rect.right -= MulDiv(12, static_cast<int>(dpi), 96);
                source_rect.left = source_rect.right - MulDiv(60, static_cast<int>(dpi), 96);
                DrawTextW(dc, source_text, -1, &source_rect,
                          DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
            }
        }

        RECT footer{0, client.bottom - footer_height, client.right, client.bottom};
        FillRect(dc, &footer, GetSysColorBrush(COLOR_BTNFACE));
        HPEN divider = CreatePen(PS_SOLID, 1, GetSysColor(COLOR_3DLIGHT));
        HGDIOBJ old_pen = SelectObject(dc, divider);
        MoveToEx(dc, footer.left, footer.top, nullptr);
        LineTo(dc, footer.right, footer.top);
        SelectObject(dc, old_pen);
        DeleteObject(divider);
        SetTextColor(dc, GetSysColor(COLOR_BTNTEXT));
        footer.left += MulDiv(12, static_cast<int>(dpi), 96);
        footer.right -= MulDiv(12, static_cast<int>(dpi), 96);
        const std::size_t page_count = (session_.candidates().size() + 8) / 9;
        const std::wstring footer_text = shared_submission_status_.empty()
            ? std::to_wstring(page_start / 9 + 1) + L" / " +
                  std::to_wstring(page_count) +
                  L"   ↑↓ 選択   右クリック 共有   Enter 確定"
            : shared_submission_status_;
        DrawTextW(dc, footer_text.c_str(), -1, &footer,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, old_font);
        DeleteObject(font);
        EndPaint(window, &paint);
    }

    void show_candidates(TfEditCookie cookie, ITfContext *context, ITfRange *range) {
        if (session_.candidates().empty()) { hide_candidates(); return; }
        HWND owner = nullptr;
        RECT rectangle{0, 0, 0, 0};
        BOOL clipped = FALSE;
        ITfContextView *view = nullptr;
        if (SUCCEEDED(context->GetActiveView(&view))) {
            view->GetTextExt(cookie, range, &rectangle, &clipped);
            if (FAILED(view->GetWnd(&owner)) || !owner) owner = GetFocus();
            view->Release();
        }
        if (!candidate_window_ && ensure_candidate_window_class()) {
            candidate_window_ = CreateWindowExW(
                WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                kCandidateWindowClass, L"Keynako candidates", WS_POPUP,
                0, 0, 360, 100, owner, nullptr, g_instance, this);
            if (candidate_window_) {
                constexpr DWORD kRoundedWindowPreference = 2;
                constexpr auto kWindowCornerPreference = static_cast<DWMWINDOWATTRIBUTE>(33);
                DwmSetWindowAttribute(candidate_window_, kWindowCornerPreference,
                                      &kRoundedWindowPreference, sizeof(kRoundedWindowPreference));
            }
        }
        if (!candidate_window_) return;
        if (owner) SetWindowLongPtrW(candidate_window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
        const UINT dpi = GetDpiForWindow(candidate_window_);
        const int row_height = MulDiv(36, static_cast<int>(dpi), 96);
        const int footer_height = MulDiv(29, static_cast<int>(dpi), 96);
        const int width = MulDiv(420, static_cast<int>(dpi), 96);
        const int height = static_cast<int>(std::min<std::size_t>(session_.candidates().size(), 9)) * row_height + footer_height;
        int left = rectangle.left;
        int top = rectangle.bottom + MulDiv(2, static_cast<int>(dpi), 96);
        RECT popup{left, top, left + width, top + height};
        MONITORINFO monitor_info{sizeof(monitor_info)};
        if (GetMonitorInfoW(MonitorFromRect(&rectangle, MONITOR_DEFAULTTONEAREST), &monitor_info)) {
            if (popup.right > monitor_info.rcWork.right) left = monitor_info.rcWork.right - width;
            if (popup.bottom > monitor_info.rcWork.bottom) top = rectangle.top - height - 2;
            left = std::max(left, static_cast<int>(monitor_info.rcWork.left));
            top = std::max(top, static_cast<int>(monitor_info.rcWork.top));
        }
        const bool was_visible = IsWindowVisible(candidate_window_) != FALSE;
        SetWindowPos(candidate_window_, HWND_TOPMOST, left, top, width, height,
                     SWP_NOACTIVATE | SWP_SHOWWINDOW);
        candidate_owner_ = owner;
        last_candidate_rectangle_ = {left, top, left + width, top + height};
        InvalidateRect(candidate_window_, nullptr, TRUE);
        NotifyWinEvent(was_visible ? EVENT_OBJECT_IME_CHANGE : EVENT_OBJECT_IME_SHOW,
                       candidate_window_, OBJID_CLIENT, CHILDID_SELF);
    }

    void hide_candidates() {
        shared_submission_status_.clear();
        if (candidate_window_) {
            GetWindowRect(candidate_window_, &last_candidate_rectangle_);
            NotifyWinEvent(EVENT_OBJECT_IME_HIDE, candidate_window_, OBJID_CLIENT, CHILDID_SELF);
            const HWND window = candidate_window_;
            DestroyWindow(window);
            if (candidate_window_ == window) candidate_window_ = nullptr;
        }
    }

    friend class EditSession;
};

HICON create_mode_icon(const wchar_t *glyph) {
    const int width = std::max(16, GetSystemMetrics(SM_CXSMICON));
    const int height = std::max(16, GetSystemMetrics(SM_CYSMICON));
    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;

    HDC screen = GetDC(nullptr);
    void *bitmap_bits = nullptr;
    HBITMAP color = CreateDIBSection(screen, &bitmap_info, DIB_RGB_COLORS, &bitmap_bits, nullptr, 0);
    HBITMAP mask = CreateBitmap(width, height, 1, 1, nullptr);
    HDC memory = CreateCompatibleDC(screen);
    ReleaseDC(nullptr, screen);
    if (!color || !mask || !memory || !bitmap_bits) {
        if (memory) DeleteDC(memory);
        if (color) DeleteObject(color);
        if (mask) DeleteObject(mask);
        return nullptr;
    }

    HGDIOBJ old_bitmap = SelectObject(memory, color);
    RECT rectangle{0, 0, width, height};
    FillRect(memory, &rectangle, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
    HFONT font = CreateFontW(-std::max(12, height - 2), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                             ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Yu Gothic UI");
    HGDIOBJ old_font = SelectObject(memory, font);
    SetBkMode(memory, TRANSPARENT);
    SetTextColor(memory, RGB(0, 0, 0));
    DrawTextW(memory, glyph, -1, &rectangle,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();

    auto *pixels = static_cast<DWORD *>(bitmap_bits);
    for (int index = 0; index < width * height; ++index) {
        const BYTE blue = static_cast<BYTE>(pixels[index] & 0xff);
        const BYTE green = static_cast<BYTE>((pixels[index] >> 8) & 0xff);
        const BYTE red = static_cast<BYTE>((pixels[index] >> 16) & 0xff);
        const BYTE coverage = static_cast<BYTE>(255 - std::min({red, green, blue}));
        pixels[index] = static_cast<DWORD>(coverage) << 24;
    }

    SelectObject(memory, old_font);
    SelectObject(memory, old_bitmap);
    DeleteObject(font);
    DeleteDC(memory);

    ICONINFO icon_info{};
    icon_info.fIcon = TRUE;
    icon_info.hbmMask = mask;
    icon_info.hbmColor = color;
    HICON icon = CreateIconIndirect(&icon_info);
    DeleteObject(mask);
    DeleteObject(color);
    return icon;
}

LanguageBarItem::LanguageBarItem(TextService *owner) : owner_(owner) {}

LanguageBarItem::~LanguageBarItem() {
    if (sink_) sink_->Release();
}

STDMETHODIMP LanguageBarItem::QueryInterface(REFIID iid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfLangBarItem || iid == IID_ITfLangBarItemButton) {
        *object = static_cast<ITfLangBarItemButton *>(this);
    } else if (iid == IID_ITfSource) {
        *object = static_cast<ITfSource *>(this);
    }
    if (!*object) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetInfo(TF_LANGBARITEMINFO *info) {
    if (!info) return E_INVALIDARG;
    *info = {};
    info->clsidService = kTextService;
    info->guidItem = kLangBarInputMode;
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_BTN_MENU |
                    TF_LBI_STYLE_SHOWNINTRAY | TF_LBI_STYLE_TEXTCOLORICON;
    info->ulSort = 0;
    wcsncpy_s(info->szDescription, std::size(info->szDescription), kDescription, _TRUNCATE);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetStatus(DWORD *status) {
    if (!status) return E_INVALIDARG;
    *status = status_;
    return S_OK;
}

STDMETHODIMP LanguageBarItem::Show(BOOL show) {
    const DWORD previous = status_;
    if (show) status_ &= ~TF_LBI_STATUS_HIDDEN;
    else status_ |= TF_LBI_STATUS_HIDDEN;
    if (sink_ && previous != status_) sink_->OnUpdate(TF_LBI_STATUS);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetTooltipString(BSTR *tooltip) {
    if (!tooltip) return E_INVALIDARG;
    if (!owner_) {
        *tooltip = SysAllocString(L"Keynako");
    } else {
        std::wstring value = owner_->input_mode() == keynako::InputMode::japanese
                                 ? L"Keynako - ひらがな"
                                 : L"Keynako - 英数";
        value += owner_->live_conversion() ? L" / ライブ変換 オン" : L" / ライブ変換 オフ";
        *tooltip = SysAllocString(value.c_str());
    }
    return *tooltip ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::OnClick(TfLBIClick click, POINT, const RECT *) {
    if (!owner_) return E_FAIL;
    if (click == TF_LBI_CLK_LEFT) owner_->toggle_input_mode();
    return S_OK;
}

STDMETHODIMP LanguageBarItem::InitMenu(ITfMenu *menu) {
    if (!menu || !owner_) return E_INVALIDARG;
    const bool japanese = owner_->input_mode() == keynako::InputMode::japanese;
    const auto add_item = [menu](UINT id, DWORD flags, const wchar_t *label) {
        return menu->AddMenuItem(id, flags, nullptr, nullptr, label,
                                 static_cast<ULONG>(wcslen(label)), nullptr);
    };
    add_item(kMenuJapanese, japanese ? TF_LBMENUF_CHECKED : 0, L"ひらがな (あ)");
    add_item(kMenuEnglish, japanese ? 0 : TF_LBMENUF_CHECKED, L"英数 (A)");
    add_item(kMenuLiveConversion, owner_->live_conversion() ? TF_LBMENUF_CHECKED : 0,
             L"ライブ変換");
    menu->AddMenuItem(0, TF_LBMENUF_SEPARATOR, nullptr, nullptr, nullptr, 0, nullptr);
    add_item(kMenuRefreshDictionary, 0, L"共有辞書を今すぐ更新");
    add_item(kMenuSettings, 0, L"Keynako 設定");
    return S_OK;
}

STDMETHODIMP LanguageBarItem::OnMenuSelect(UINT id) {
    if (!owner_) return E_FAIL;
    switch (id) {
        case kMenuJapanese: owner_->set_input_mode(keynako::InputMode::japanese); break;
        case kMenuEnglish: owner_->set_input_mode(keynako::InputMode::english); break;
        case kMenuLiveConversion: owner_->toggle_live_conversion(); break;
        case kMenuRefreshDictionary: owner_->refresh_shared_dictionary(); break;
        case kMenuSettings: owner_->open_settings(); break;
        default: return E_INVALIDARG;
    }
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetIcon(HICON *icon) {
    if (!icon) return E_INVALIDARG;
    *icon = create_mode_icon(owner_ && owner_->input_mode() == keynako::InputMode::japanese
                                 ? L"あ"
                                 : L"A");
    return *icon ? S_OK : E_FAIL;
}

STDMETHODIMP LanguageBarItem::GetText(BSTR *text) {
    if (!text) return E_INVALIDARG;
    *text = SysAllocString(owner_ && owner_->input_mode() == keynako::InputMode::japanese
                               ? L"あ"
                               : L"A");
    return *text ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::AdviseSink(REFIID iid, IUnknown *unknown, DWORD *cookie) {
    if (iid != IID_ITfLangBarItemSink) return kConnectCannotConnect;
    if (!unknown || !cookie) return E_INVALIDARG;
    if (sink_) return kConnectAdviseLimit;
    const HRESULT result = unknown->QueryInterface(IID_PPV_ARGS(&sink_));
    if (FAILED(result)) return result;
    *cookie = 1;
    return S_OK;
}

STDMETHODIMP LanguageBarItem::UnadviseSink(DWORD cookie) {
    if (cookie != 1 || !sink_) return kConnectNoConnection;
    sink_->Release();
    sink_ = nullptr;
    return S_OK;
}

void LanguageBarItem::notify_mode_changed() {
    if (sink_) sink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP);
}

EditSession::EditSession(TextService *service, ITfContext *context, EditAction action)
    : service_(service), context_(context), action_(action) {
    service_->AddRef();
    context_->AddRef();
}
EditSession::~EditSession() { context_->Release(); service_->Release(); }
STDMETHODIMP EditSession::QueryInterface(REFIID iid, void **object) {
    if (!object) return E_INVALIDARG;
    if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
        *object = static_cast<ITfEditSession *>(this);
        AddRef();
        return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
}
STDMETHODIMP EditSession::DoEditSession(TfEditCookie edit_cookie) {
    return service_->apply_edit(edit_cookie, context_, action_);
}

class ClassFactory final : public IClassFactory {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void **object) override {
        if (!object) return E_INVALIDARG;
        if (iid == IID_IUnknown || iid == IID_IClassFactory) {
            *object = static_cast<IClassFactory *>(this);
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG value = --references_;
        if (value == 0) delete this;
        return value;
    }
    STDMETHODIMP CreateInstance(IUnknown *outer, REFIID iid, void **object) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        auto *service = new TextService();
        const HRESULT result = service->QueryInterface(iid, object);
        service->Release();
        return result;
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) ++g_objects; else --g_objects;
        return S_OK;
    }
private:
    std::atomic<ULONG> references_{1};
};

HRESULT set_registry_string(HKEY root, const std::wstring &path, const wchar_t *name, const std::wstring &value) {
    HKEY key = nullptr;
    const LONG opened = RegCreateKeyExW(root, path.c_str(), 0, nullptr, REG_OPTION_NON_VOLATILE,
                                         KEY_WRITE, nullptr, &key, nullptr);
    if (opened != ERROR_SUCCESS) return HRESULT_FROM_WIN32(opened);
    const LONG written = RegSetValueExW(key, name, 0, REG_SZ,
        reinterpret_cast<const BYTE *>(value.c_str()), static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    return HRESULT_FROM_WIN32(written);
}

std::wstring clsid_string() {
    wchar_t value[64]{};
    StringFromGUID2(kTextService, value, 64);
    return value;
}

HRESULT register_server() {
    wchar_t module[32768]{};
    GetModuleFileNameW(g_instance, module, 32768);
    const std::wstring base = L"Software\\Classes\\CLSID\\" + clsid_string();
    HRESULT result = set_registry_string(HKEY_CURRENT_USER, base, nullptr, kDescription);
    if (SUCCEEDED(result)) result = set_registry_string(HKEY_CURRENT_USER, base + L"\\InprocServer32", nullptr, module);
    if (SUCCEEDED(result)) result = set_registry_string(HKEY_CURRENT_USER, base + L"\\InprocServer32", L"ThreadingModel", L"Apartment");
    if (FAILED(result)) return result;

    ITfInputProcessorProfiles *profiles = nullptr;
    result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (SUCCEEDED(result)) {
        result = profiles->Register(kTextService);
        if (SUCCEEDED(result)) {
            const LANGID language = MAKELANGID(LANG_JAPANESE, SUBLANG_DEFAULT);
            // Refreshing the profile makes upgrades idempotent and replaces the
            // icon metadata cached by the Windows input switcher.
            profiles->RemoveLanguageProfile(kTextService, language, kLanguageProfile);
            std::error_code icon_error;
            const auto standalone_icon = module_directory() / L"KeynakoProfile.ico";
            const std::wstring icon_file = std::filesystem::exists(standalone_icon, icon_error) && !icon_error
                                               ? standalone_icon.wstring()
                                               : std::wstring(module);
            result = profiles->AddLanguageProfile(kTextService, language, kLanguageProfile,
                kDescription, static_cast<ULONG>(std::size(kDescription) - 1), icon_file.c_str(),
                static_cast<ULONG>(icon_file.size()), 0);
            if (SUCCEEDED(result)) {
                result = profiles->EnableLanguageProfile(kTextService, language, kLanguageProfile, TRUE);
            }
        }
        profiles->Release();
    }
    ITfCategoryMgr *categories = nullptr;
    if (SUCCEEDED(result) && SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&categories)))) {
        const GUID values[] = {GUID_TFCAT_TIP_KEYBOARD, GUID_TFCAT_TIPCAP_SECUREMODE,
                               GUID_TFCAT_TIPCAP_COMLESS, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
                               GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
                               GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT};
        for (const auto &category : values) categories->RegisterCategory(kTextService, category, kTextService);
        categories->Release();
    }
    return result;
}

HRESULT unregister_server() {
    ITfInputProcessorProfiles *profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles)))) {
        profiles->RemoveLanguageProfile(kTextService, MAKELANGID(LANG_JAPANESE, SUBLANG_DEFAULT), kLanguageProfile);
        profiles->Unregister(kTextService);
        profiles->Release();
    }
    ITfCategoryMgr *categories = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&categories)))) {
        const GUID values[] = {GUID_TFCAT_TIP_KEYBOARD, GUID_TFCAT_TIPCAP_SECUREMODE,
                               GUID_TFCAT_TIPCAP_COMLESS, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
                               GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
                               GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT};
        for (const auto &category : values) categories->UnregisterCategory(kTextService, category, kTextService);
        categories->Release();
    }
    const std::wstring path = L"Software\\Classes\\CLSID\\" + clsid_string();
    RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
    return S_OK;
}

}  // namespace

BOOL APIENTRY DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

STDAPI DllCanUnloadNow() {
    return g_objects.load() == 0 ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void **object) {
    if (clsid != kTextService) return CLASS_E_CLASSNOTAVAILABLE;
    auto *factory = new ClassFactory();
    const HRESULT result = factory->QueryInterface(iid, object);
    factory->Release();
    return result;
}

STDAPI DllRegisterServer() {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const HRESULT result = register_server();
    if (SUCCEEDED(initialized)) CoUninitialize();
    return result;
}

STDAPI DllUnregisterServer() {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const HRESULT result = unregister_server();
    if (SUCCEEDED(initialized)) CoUninitialize();
    return result;
}
