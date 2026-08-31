#include <windows.h>
#include <windowsx.h>
#include <ctfutb.h>
#include <dwmapi.h>
#include <msctf.h>
#include <objbase.h>
#include <ocidl.h>
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
#include <sstream>
#include <string>
#include <vector>

#include "keynako_resources.h"
#include "keynako_ime_core.h"
#include "zenzai_client.h"

namespace {

// {F7959D5B-0818-43CC-9919-6AFA791730FC}
constexpr CLSID kTextService = {0xf7959d5b, 0x0818, 0x43cc, {0x99, 0x19, 0x6a, 0xfa, 0x79, 0x17, 0x30, 0xfc}};
// {9E061A9A-A339-4AE0-B6DC-A13F21A340C2}
constexpr GUID kLanguageProfile = {0x9e061a9a, 0xa339, 0x4ae0, {0xb6, 0xdc, 0xa1, 0x3f, 0x21, 0xa3, 0x40, 0xc2}};
// {3116A7F8-8F02-4327-BA10-3625B689E948}
constexpr GUID kPreservedToggle = {0x3116a7f8, 0x8f02, 0x4327, {0xba, 0x10, 0x36, 0x25, 0xb6, 0x89, 0xe9, 0x48}};
// GUID_LBI_INPUTMODE is not declared by every supported Windows SDK, even
// though Windows 8 and later require this value for the taskbar mode button.
constexpr GUID kLangBarInputMode = {0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
// The Japanese DBE virtual-key constants are likewise absent from some SDKs.
constexpr WPARAM kVirtualKeyDbeAlphanumeric = 0xf0;
constexpr WPARAM kVirtualKeyDbeHiragana = 0xf2;
constexpr wchar_t kDescription[] = L"Keynako Japanese IME";

constexpr UINT kMenuJapanese = 1;
constexpr UINT kMenuEnglish = 2;
constexpr UINT kMenuLiveConversion = 3;
constexpr UINT kMenuSettings = 4;
constexpr wchar_t kCandidateWindowClass[] = L"KeynakoCandidateWindow";

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
        hide_candidates();
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
        session_.set_mode(mode);
        sync_input_compartments();
        if (language_bar_) language_bar_->notify_mode_changed();
        if (context) {
            request_edit(context, EditAction::cancel);
        } else {
            request_active_edit(EditAction::cancel);
        }
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
            const TF_PRESERVEDKEY toggle_key{VK_KANJI, 0};
            keys->PreserveKey(client_id_, kPreservedToggle, &toggle_key,
                              L"Toggle Keynako input mode", 25);
            keys->Release();
        }
        initialize_language_bar();
        sync_input_compartments();
        reload_shared_dictionary(true);
        return result;
    }
    STDMETHODIMP Deactivate() override {
        if (thread_manager_) {
            ITfKeystrokeMgr *keys = nullptr;
            if (SUCCEEDED(thread_manager_->QueryInterface(IID_PPV_ARGS(&keys)))) {
                const TF_PRESERVEDKEY toggle_key{VK_KANJI, 0};
                keys->UnpreserveKey(kPreservedToggle, &toggle_key);
                keys->UnadviseKeyEventSink(client_id_);
                keys->Release();
            }
            remove_language_bar();
            thread_manager_->Release();
            thread_manager_ = nullptr;
        }
        session_.clear();
        hide_candidates();
        return S_OK;
    }

    STDMETHODIMP OnSetFocus(BOOL) override { return S_OK; }
    STDMETHODIMP OnTestKeyDown(ITfContext *, WPARAM key, LPARAM, BOOL *eaten) override {
        if (!eaten) return E_INVALIDARG;
        *eaten = handles_key(key) ? TRUE : FALSE;
        return S_OK;
    }
    STDMETHODIMP OnKeyDown(ITfContext *context, WPARAM key, LPARAM, BOOL *eaten) override {
        if (!context || !eaten) return E_INVALIDARG;
        *eaten = FALSE;
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        if (control && key == VK_SPACE) {
            toggle_input_mode(context);
            *eaten = TRUE;
            return S_OK;
        }
        if (!handles_key(key)) return S_OK;

        if (key == VK_KANJI) {
            toggle_input_mode(context);
            *eaten = TRUE;
            return S_OK;
        }
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
        if (key >= '1' && key <= '9' && session_.is_converting()) {
            if (!session_.select_candidate(static_cast<std::size_t>(key - '1'))) return S_OK;
            action = EditAction::commit;
        } else if ((key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9') ||
            key == VK_OEM_MINUS || key == VK_OEM_COMMA || key == VK_OEM_PERIOD) {
            reload_shared_dictionary();
            BYTE keyboard[256]{};
            WCHAR translated[4]{};
            GetKeyboardState(keyboard);
            const int count = ToUnicode(static_cast<UINT>(key), 0, keyboard, translated, 4, 0);
            char value = 0;
            if (count > 0 && translated[0] < 128) value = static_cast<char>(translated[0]);
            if (!value) value = key == VK_OEM_MINUS ? '-' : key == VK_OEM_COMMA ? ',' : key == VK_OEM_PERIOD ? '.' : static_cast<char>(std::tolower(static_cast<unsigned char>(key)));
            session_.append_ascii(value);
        } else if (key == VK_BACK) {
            if (session_.raw_input().empty()) return S_OK;
            if (!session_.cancel_conversion()) session_.backspace();
            action = session_.raw_input().empty() ? EditAction::cancel : EditAction::update;
        } else if (key == VK_SPACE || key == VK_CONVERT || key == VK_DOWN ||
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
        if (!eaten) return E_INVALIDARG;
        *eaten = FALSE;
        if (guid == kPreservedToggle) {
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

        if (!composition_) {
            TF_SELECTION selection{};
            ULONG fetched = 0;
            HRESULT result = context->GetSelection(edit_cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
            if (FAILED(result) || fetched != 1) return FAILED(result) ? result : E_FAIL;
            ITfContextComposition *composition_context = nullptr;
            result = context->QueryInterface(IID_PPV_ARGS(&composition_context));
            if (SUCCEEDED(result)) {
                result = composition_context->StartComposition(edit_cookie, selection.range, this, &composition_);
                composition_context->Release();
            }
            selection.range->Release();
            if (FAILED(result)) return result;
        }

        ITfRange *range = nullptr;
        HRESULT result = composition_->GetRange(&range);
        if (FAILED(result)) return result;
        const std::wstring text = utf8_to_wide(action == EditAction::commit ? session_.selected_text() : session_.display_text());
        result = range->SetText(edit_cookie, 0, text.data(), static_cast<LONG>(text.size()));
        if (SUCCEEDED(result) && action == EditAction::commit) {
            range->Collapse(edit_cookie, TF_ANCHOR_END);
            ITfComposition *ending = composition_;
            composition_ = nullptr;
            ending->EndComposition(edit_cookie);
            ending->Release();
            session_.clear();
            hide_candidates();
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
    LanguageBarItem *language_bar_ = nullptr;
    std::filesystem::path shared_dictionary_path_;
    std::filesystem::file_time_type shared_dictionary_write_time_{};
    std::chrono::steady_clock::time_point last_dictionary_check_{};

    bool handles_key(WPARAM key) const {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        if (control && key == VK_SPACE) return true;
        if (control || (GetKeyState(VK_MENU) & 0x8000) != 0) return false;
        if (key == VK_KANJI || key == VK_KANA || key == kVirtualKeyDbeHiragana ||
            key == kVirtualKeyDbeAlphanumeric || key == VK_NONCONVERT) return true;
        const bool japanese = session_.mode() == keynako::InputMode::japanese;
        if (japanese && key >= 'A' && key <= 'Z') return true;
        if (japanese && key >= '0' && key <= '9' && !session_.is_converting()) return true;
        if (japanese && (key == VK_OEM_MINUS || key == VK_OEM_COMMA || key == VK_OEM_PERIOD)) return true;
        if (session_.raw_input().empty()) return false;
        if (session_.is_converting() && key >= '1' && key <= '9') return true;
        return key == VK_BACK || key == VK_SPACE || key == VK_CONVERT || key == VK_UP ||
               key == VK_DOWN || key == VK_TAB || key == VK_PRIOR || key == VK_NEXT ||
               key == VK_RETURN || key == VK_ESCAPE;
    }

    void request_edit(ITfContext *context, EditAction action) {
        auto *edit = new EditSession(this, context, action);
        HRESULT session_result = E_FAIL;
        context->RequestEditSession(client_id_, edit, TF_ES_SYNC | TF_ES_READWRITE, &session_result);
        edit->Release();
    }

    void request_active_edit(EditAction action) {
        if (!thread_manager_) return;
        ITfDocumentMgr *document = nullptr;
        if (FAILED(thread_manager_->GetFocus(&document)) || !document) return;
        ITfContext *context = nullptr;
        if (SUCCEEDED(document->GetTop(&context)) && context) {
            request_edit(context, action);
            context->Release();
        }
        document->Release();
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
        set_compartment_value(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, japanese ? 1 : 0);
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
        if (!program_data.empty()) files.push_back(program_data / L"Keynako" / L"shared_dictionary.tsv");
        if (!local_app_data.empty()) files.push_back(local_app_data / L"Keynako" / L"shared_dictionary.tsv");

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
            while (std::getline(stream, line)) {
                if (!line.empty() && line.back() == '\r') line.pop_back();
                if (line.empty() || line.front() == '#') continue;
                const auto first_tab = line.find('\t');
                const auto second_tab = first_tab == std::string::npos
                    ? std::string::npos
                    : line.find('\t', first_tab + 1);
                if (first_tab == std::string::npos || second_tab == std::string::npos) continue;
                try {
                    const int importance = std::clamp(std::stoi(line.substr(0, first_tab)), 1, 5);
                    std::string reading = line.substr(first_tab + 1, second_tab - first_tab - 1);
                    std::string value = line.substr(second_tab + 1);
                    if (!reading.empty() && !value.empty()) {
                        entries.push_back({std::move(reading), std::move(value), importance});
                    }
                } catch (const std::exception &) {
                    continue;
                }
            }
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

    static LRESULT CALLBACK candidate_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
        auto *service = reinterpret_cast<TextService *>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
            service = static_cast<TextService *>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(service));
        }
        if (!service) return DefWindowProcW(window, message, wparam, lparam);
        switch (message) {
            case WM_PAINT: service->paint_candidate_window(window); return 0;
            case WM_ERASEBKGND: return 1;
            case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
            case WM_LBUTTONDOWN:
            case WM_LBUTTONDBLCLK: {
                const UINT dpi = GetDpiForWindow(window);
                const int row_height = MulDiv(36, static_cast<int>(dpi), 96);
                const int row = GET_Y_LPARAM(lparam) / std::max(1, row_height);
                const std::size_t page_start = (service->session_.selected_index() / 9) * 9;
                const std::size_t index = page_start + static_cast<std::size_t>(std::max(0, row));
                if (index < service->session_.candidates().size() && row < 9 &&
                    service->session_.select_candidate(index)) {
                    service->request_active_edit(message == WM_LBUTTONDBLCLK
                                                     ? EditAction::commit
                                                     : EditAction::update);
                }
                return 0;
            }
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
        const std::wstring footer_text = std::to_wstring(page_start / 9 + 1) + L" / " +
                                         std::to_wstring(page_count) +
                                         L"   ↑↓ 選択   Space・変換 次候補   Enter 確定";
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
        InvalidateRect(candidate_window_, nullptr, TRUE);
        NotifyWinEvent(was_visible ? EVENT_OBJECT_IME_CHANGE : EVENT_OBJECT_IME_SHOW,
                       candidate_window_, OBJID_CLIENT, CHILDID_SELF);
    }

    void hide_candidates() {
        if (candidate_window_) {
            NotifyWinEvent(EVENT_OBJECT_IME_HIDE, candidate_window_, OBJID_CLIENT, CHILDID_SELF);
            DestroyWindow(candidate_window_);
            candidate_window_ = nullptr;
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
    add_item(kMenuSettings, 0, L"Keynako 設定");
    return S_OK;
}

STDMETHODIMP LanguageBarItem::OnMenuSelect(UINT id) {
    if (!owner_) return E_FAIL;
    switch (id) {
        case kMenuJapanese: owner_->set_input_mode(keynako::InputMode::japanese); break;
        case kMenuEnglish: owner_->set_input_mode(keynako::InputMode::english); break;
        case kMenuLiveConversion: owner_->toggle_live_conversion(); break;
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
    if (iid != IID_ITfLangBarItemSink) return CONNECT_E_CANNOTCONNECT;
    if (!unknown || !cookie) return E_INVALIDARG;
    if (sink_) return CONNECT_E_ADVISELIMIT;
    const HRESULT result = unknown->QueryInterface(IID_PPV_ARGS(&sink_));
    if (FAILED(result)) return result;
    *cookie = 1;
    return S_OK;
}

STDMETHODIMP LanguageBarItem::UnadviseSink(DWORD cookie) {
    if (cookie != 1 || !sink_) return CONNECT_E_NOCONNECTION;
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
            result = profiles->AddLanguageProfile(kTextService, language, kLanguageProfile,
                kDescription, static_cast<ULONG>(std::size(kDescription) - 1), module,
                static_cast<ULONG>(wcslen(module)), 0);
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
