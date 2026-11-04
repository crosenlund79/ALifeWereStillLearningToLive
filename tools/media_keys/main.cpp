// TinserBoxMedia.exe — registers TinserBox with Windows System Media Transport Controls (SMTC)
// so hardware Play/Pause, Next, Previous and Stop keys reach TinserBox even when it is
// minimized or unfocused. Windows routes media keys to the active SMTC session, so other
// media apps keep their own controls (nothing is hooked or globally intercepted).
//
// Usage: TinserBoxMedia.exe <godot_udp_port> <godot_pid>
// Sends "hello", "play", "pause", "stop", "next", "previous" as UDP datagrams to 127.0.0.1:<port>.
// Receives "state playing|paused|stopped" and "title <utf-8 text>". Exits when Godot exits.
#include <winsock2.h>
#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <inspectable.h>
#include <eventtoken.h>
#include <systemmediatransportcontrolsinterop.h>
#include <cstdio>
#include <cstring>
#include <string>

// WinRT ABI interfaces not declared by mingw-w64 (vtable order from the Windows SDK IDL).
struct IMusicDisplayProperties : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Title(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Title(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AlbumArtist(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_AlbumArtist(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Artist(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Artist(HSTRING) = 0;
};

struct IDisplayUpdater : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Type(int*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Type(int) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AppMediaId(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_AppMediaId(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Thumbnail(IUnknown**) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Thumbnail(IUnknown*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_MusicProperties(IMusicDisplayProperties**) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_VideoProperties(IUnknown**) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_ImageProperties(IUnknown**) = 0;
    virtual HRESULT STDMETHODCALLTYPE CopyFromFileAsync(int, IUnknown*, IUnknown**) = 0;
    virtual HRESULT STDMETHODCALLTYPE ClearAll() = 0;
    virtual HRESULT STDMETHODCALLTYPE Update() = 0;
};

struct IButtonPressedEventArgs : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Button(int*) = 0;
};

struct ISMTC : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_PlaybackStatus(int*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_PlaybackStatus(int) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_DisplayUpdater(IDisplayUpdater**) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_SoundLevel(int*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPlayEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsPlayEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsStopEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsStopEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPauseEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsPauseEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsRecordEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsRecordEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsFastForwardEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsFastForwardEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsRewindEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsRewindEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPreviousEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsPreviousEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsNextEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsNextEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsChannelUpEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsChannelUpEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsChannelDownEnabled(boolean*) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsChannelDownEnabled(boolean) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_ButtonPressed(IUnknown*, EventRegistrationToken*) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_ButtonPressed(EventRegistrationToken) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_PropertyChanged(IUnknown*, EventRegistrationToken*) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_PropertyChanged(EventRegistrationToken) = 0;
};

static const IID IID_ISMTC = {0x99fa3ff4, 0x1742, 0x42a6, {0x90, 0x2e, 0x08, 0x7d, 0x41, 0xf9, 0x65, 0xec}};
static const IID IID_ISMTCInterop = {0xddb0472d, 0xc911, 0x4a1f, {0x86, 0xd9, 0xdc, 0x3d, 0x71, 0xa9, 0x5f, 0x5a}};
// TypedEventHandler<SystemMediaTransportControls, SystemMediaTransportControlsButtonPressedEventArgs>
static const IID IID_ButtonHandler = {0x0557e996, 0x7b23, 0x5bae, {0xaa, 0x81, 0xea, 0x0d, 0x67, 0x11, 0x43, 0xa4}};
static const IID IID_Agile = {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};

enum { STATUS_CLOSED = 0, STATUS_STOPPED = 2, STATUS_PLAYING = 3, STATUS_PAUSED = 4 };
static const char *BUTTONS[] = {"play", "pause", "stop", "record", "fastforward", "rewind", "next", "previous"};

static SOCKET sock;
static sockaddr_in godot = {};
static ISMTC *smtc = nullptr;

static void send_msg(const char *msg) {
    sendto(sock, msg, (int)strlen(msg), 0, (sockaddr *)&godot, sizeof(godot));
}

struct ButtonHandler : IUnknown {
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
        if (riid == IID_IUnknown || riid == IID_Agile || riid == IID_ButtonHandler) {
            *out = this;
            return S_OK;
        }
        *out = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return 2; }  // static lifetime
    ULONG STDMETHODCALLTYPE Release() override { return 1; }
    virtual HRESULT STDMETHODCALLTYPE Invoke(ISMTC *, IButtonPressedEventArgs *args) {
        int button = -1;
        if (SUCCEEDED(args->get_Button(&button)) && button >= 0 && button < 8)
            send_msg(BUTTONS[button]);
        return S_OK;
    }
};
static ButtonHandler handler;

static void set_title(const std::string &utf8) {
    IDisplayUpdater *updater = nullptr;
    IMusicDisplayProperties *music = nullptr;
    if (FAILED(smtc->get_DisplayUpdater(&updater))) return;
    updater->put_Type(1);  // MediaPlaybackType::Music
    if (SUCCEEDED(updater->get_MusicProperties(&music))) {
        std::wstring wide(MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), nullptr, 0), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &wide[0], (int)wide.size());
        HSTRING title = nullptr, artist = nullptr;
        WindowsCreateString(wide.c_str(), (UINT32)wide.size(), &title);
        WindowsCreateString(L"TinserBox", 9, &artist);
        music->put_Title(title);
        music->put_Artist(artist);
        WindowsDeleteString(title);
        WindowsDeleteString(artist);
        music->Release();
    }
    updater->Update();
    updater->Release();
}

static DWORD WINAPI receive_loop(LPVOID) {
    RoInitialize(RO_INIT_MULTITHREADED);
    char buf[2048];
    for (;;) {
        int n = recv(sock, buf, sizeof(buf) - 1, 0);
        if (n <= 0) continue;
        buf[n] = 0;
        std::string msg(buf);
        if (msg == "state playing") smtc->put_PlaybackStatus(STATUS_PLAYING);
        else if (msg == "state paused") smtc->put_PlaybackStatus(STATUS_PAUSED);
        else if (msg == "state stopped") smtc->put_PlaybackStatus(STATUS_STOPPED);
        else if (msg.rfind("title ", 0) == 0) set_title(msg.substr(6));
    }
}

static int fail(const char *step, HRESULT hr) {
    char msg[128];
    snprintf(msg, sizeof(msg), "error %s 0x%08lx", step, (unsigned long)hr);
    send_msg(msg);
    return 1;
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR, int) {
    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argc < 3) return 1;
    int port = _wtoi(argv[1]);
    HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)_wtoi(argv[2]));

    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    sockaddr_in local = {};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(sock, (sockaddr *)&local, sizeof(local));
    godot.sin_family = AF_INET;
    godot.sin_port = htons((u_short)port);
    godot.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    RoInitialize(RO_INIT_MULTITHREADED);

    // SMTC needs a window handle; a hidden top-level window owned by this helper is enough.
    WNDCLASSW wc = {};
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = instance;
    wc.lpszClassName = L"TinserBoxMediaKeys";
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowExW(0, wc.lpszClassName, L"TinserBox", WS_OVERLAPPEDWINDOW, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);

    HSTRING class_name = nullptr;
    const wchar_t *name = L"Windows.Media.SystemMediaTransportControls";
    WindowsCreateString(name, (UINT32)wcslen(name), &class_name);
    ISystemMediaTransportControlsInterop *interop = nullptr;
    HRESULT hr = RoGetActivationFactory(class_name, IID_ISMTCInterop, (void **)&interop);
    if (FAILED(hr)) return fail("factory", hr);
    hr = interop->GetForWindow(hwnd, IID_ISMTC, (void **)&smtc);
    if (FAILED(hr)) return fail("smtc", hr);

    smtc->put_IsEnabled(true);
    smtc->put_IsPlayEnabled(true);
    smtc->put_IsPauseEnabled(true);
    smtc->put_IsStopEnabled(true);
    smtc->put_IsNextEnabled(true);
    smtc->put_IsPreviousEnabled(true);
    smtc->put_PlaybackStatus(STATUS_STOPPED);
    EventRegistrationToken token;
    hr = smtc->add_ButtonPressed(&handler, &token);
    if (FAILED(hr)) return fail("handler", hr);

    CreateThread(nullptr, 0, receive_loop, nullptr, 0, nullptr);
    send_msg("hello");

    // Pump messages until TinserBox exits.
    for (;;) {
        DWORD r = MsgWaitForMultipleObjects(parent ? 1 : 0, &parent, FALSE, INFINITE, QS_ALLINPUT);
        if (parent && r == WAIT_OBJECT_0) break;
        MSG m;
        while (PeekMessageW(&m, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
    }
    smtc->put_PlaybackStatus(STATUS_CLOSED);
    smtc->remove_ButtonPressed(token);
    return 0;
}
