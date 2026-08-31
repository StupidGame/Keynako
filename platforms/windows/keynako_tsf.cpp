#include <windows.h>
#include <msctf.h>
#include <objbase.h>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <iterator>
#include <memory>
#include <string>

#include "keynako_ime_core.h"
#include "zenzai_client.h"

namespace {

// {F7959D5B-0818-43CC-9919-6AFA791730FC}
constexpr CLSID kTextService = {0xf7959d5b, 0x0818, 0x43cc, {0x99, 0x19, 0x6a, 0xfa, 0x79, 0x17, 0x30, 0xfc}};
// {9E061A9A-A339-4AE0-B6DC-A13F21A340C2}
constexpr GUID kLanguageProfile = {0x9e061a9a, 0xa339, 0x4ae0, {0xb6, 0xdc, 0xa1, 0x3f, 0x21, 0xa3, 0x40, 0xc2}};
constexpr wchar_t kDescription[] = L"Keynako Japanese IME";

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

class TextService;

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
            keys->Release();
        }
        return result;
    }
    STDMETHODIMP Deactivate() override {
        if (thread_manager_) {
            ITfKeystrokeMgr *keys = nullptr;
            if (SUCCEEDED(thread_manager_->QueryInterface(IID_PPV_ARGS(&keys)))) {
                keys->UnadviseKeyEventSink(client_id_);
                keys->Release();
            }
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
            session_.set_mode(session_.mode() == keynako::InputMode::japanese
                                  ? keynako::InputMode::english
                                  : keynako::InputMode::japanese);
            request_edit(context, EditAction::cancel);
            *eaten = TRUE;
            return S_OK;
        }
        if (!handles_key(key)) return S_OK;

        EditAction action = EditAction::update;
        if ((key >= 'A' && key <= 'Z') || key == VK_OEM_MINUS || key == VK_OEM_COMMA || key == VK_OEM_PERIOD) {
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
            session_.backspace();
            action = session_.raw_input().empty() ? EditAction::cancel : EditAction::update;
        } else if (key == VK_SPACE || key == VK_DOWN) {
            if (session_.raw_input().empty()) return S_OK;
            const bool zenzai_added = key == VK_SPACE &&
                session_.mode() == keynako::InputMode::japanese && add_zenzai_candidate();
            if (!zenzai_added) session_.select_next();
        } else if (key == VK_UP) {
            if (session_.raw_input().empty()) return S_OK;
            session_.select_previous();
        } else if (key == VK_RETURN) {
            if (session_.raw_input().empty()) return S_OK;
            action = EditAction::commit;
        } else if (key == VK_ESCAPE) {
            if (session_.raw_input().empty()) return S_OK;
            action = EditAction::cancel;
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
    STDMETHODIMP OnPreservedKey(ITfContext *, REFGUID, BOOL *eaten) override {
        if (!eaten) return E_INVALIDARG;
        *eaten = FALSE;
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
            show_candidates(edit_cookie, context, range);
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

    bool handles_key(WPARAM key) const {
        const bool control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        if (control && key == VK_SPACE) return true;
        if (control || (GetKeyState(VK_MENU) & 0x8000) != 0) return false;
        if (key >= 'A' && key <= 'Z') return true;
        if (key == VK_OEM_MINUS || key == VK_OEM_COMMA || key == VK_OEM_PERIOD) return true;
        if (session_.raw_input().empty()) return false;
        return key == VK_BACK || key == VK_SPACE || key == VK_UP || key == VK_DOWN || key == VK_RETURN || key == VK_ESCAPE;
    }

    void request_edit(ITfContext *context, EditAction action) {
        auto *edit = new EditSession(this, context, action);
        HRESULT session_result = E_FAIL;
        context->RequestEditSession(client_id_, edit, TF_ES_SYNC | TF_ES_READWRITE, &session_result);
        edit->Release();
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

    void show_candidates(TfEditCookie cookie, ITfContext *context, ITfRange *range) {
        if (session_.candidates().empty()) { hide_candidates(); return; }
        if (!candidate_window_) {
            candidate_window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                L"STATIC", L"", WS_POPUP | WS_BORDER | SS_LEFT, 0, 0, 320, 100,
                nullptr, nullptr, g_instance, nullptr);
            if (candidate_window_) SendMessageW(candidate_window_, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
        }
        if (!candidate_window_) return;
        std::wstring text;
        for (std::size_t index = 0; index < session_.candidates().size() && index < 9; ++index) {
            text += index == session_.selected_index() ? L"› " : L"  ";
            text += std::to_wstring(index + 1) + L"  " + utf8_to_wide(session_.candidates()[index].text) + L"\r\n";
        }
        SetWindowTextW(candidate_window_, text.c_str());
        RECT rectangle{0, 0, 0, 0};
        BOOL clipped = FALSE;
        ITfContextView *view = nullptr;
        if (SUCCEEDED(context->GetActiveView(&view))) {
            view->GetTextExt(cookie, range, &rectangle, &clipped);
            view->Release();
        }
        const int height = static_cast<int>(std::min<std::size_t>(session_.candidates().size(), 9) * 24 + 8);
        SetWindowPos(candidate_window_, HWND_TOPMOST, rectangle.left, rectangle.bottom + 2, 360, height,
                     SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    void hide_candidates() {
        if (candidate_window_) {
            DestroyWindow(candidate_window_);
            candidate_window_ = nullptr;
        }
    }

    friend class EditSession;
};

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
        }
        profiles->Release();
    }
    ITfCategoryMgr *categories = nullptr;
    if (SUCCEEDED(result) && SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&categories)))) {
        const GUID values[] = {GUID_TFCAT_TIP_KEYBOARD, GUID_TFCAT_TIPCAP_SECUREMODE,
                               GUID_TFCAT_TIPCAP_COMLESS, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
                               GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT};
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
                               GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT};
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
