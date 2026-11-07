// TinserBoxMedia.exe — small Windows helper for TinserBox.
//
// 1. Media keys: registers TinserBox with System Media Transport Controls (SMTC), so
//    hardware Play/Pause, Next, Previous and Stop reach TinserBox even when unfocused.
//    Windows routes media keys to the active SMTC session, so other players keep theirs.
// 2. System audio ("visualize Spotify etc."): captures what the default output device
//    plays (WASAPI loopback; no drivers or admin rights) and streams it to TinserBox as
//    16-bit stereo PCM, so the visualizers can follow any app.
// 3. Now playing: while capturing, reads the title/artist of the current media session
//    (Spotify, browsers, ...) via GlobalSystemMediaTransportControlsSessionManager.
//
// Usage: TinserBoxMedia.exe <godot_udp_port> <godot_pid>
// To Godot (UDP 127.0.0.1:<port>): "hello", "play", "pause", "stop", "next", "previous",
//   "fmt <rate>", "np <title>\t<artist>", "error <step> <hr>", binary PCM packets (0x01 + int16 L/R).
// From Godot: "state playing|paused|stopped", "title <text>", "capture on|off", "smtc on|off".
// Exits when TinserBox exits.
#include <winsock2.h>
#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <inspectable.h>
#include <eventtoken.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <systemmediatransportcontrolsinterop.h>
#include <cstdio>
#include <cstring>
#include <string>

// --- WinRT ABI interfaces not declared by mingw-w64 (vtable order from the Windows SDK IDL) ---
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

// Windows.Media.Control (now playing of other apps) and async plumbing.
struct IAsyncInfoABI : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Id(UINT32*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Status(int*) = 0;  // 0 started, 1 completed, 2 canceled, 3 error
    virtual HRESULT STDMETHODCALLTYPE get_ErrorCode(HRESULT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE Cancel() = 0;
    virtual HRESULT STDMETHODCALLTYPE Close() = 0;
};
struct IAsyncOp : IInspectable {  // IAsyncOperation<T>, T an interface
    virtual HRESULT STDMETHODCALLTYPE put_Completed(IUnknown*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Completed(IUnknown**) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetResults(void**) = 0;
};
struct IMediaProps : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_Title(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Subtitle(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AlbumArtist(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Artist(HSTRING*) = 0;
};
struct ISession : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE get_SourceAppUserModelId(HSTRING*) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryGetMediaPropertiesAsync(IAsyncOp**) = 0;
};
struct ISessionManager : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE GetCurrentSession(ISession**) = 0;
};
struct ISessionManagerStatics : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE RequestAsync(IAsyncOp**) = 0;
};

static const IID IID_ISMTC = {0x99fa3ff4, 0x1742, 0x42a6, {0x90, 0x2e, 0x08, 0x7d, 0x41, 0xf9, 0x65, 0xec}};
static const IID IID_ISMTCInterop = {0xddb0472d, 0xc911, 0x4a1f, {0x86, 0xd9, 0xdc, 0x3d, 0x71, 0xa9, 0x5f, 0x5a}};
// TypedEventHandler<SystemMediaTransportControls, SystemMediaTransportControlsButtonPressedEventArgs>
static const IID IID_ButtonHandler = {0x0557e996, 0x7b23, 0x5bae, {0xaa, 0x81, 0xea, 0x0d, 0x67, 0x11, 0x43, 0xa4}};
static const IID IID_Agile = {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};
static const IID IID_AsyncInfo = {0x00000036, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID IID_SessionManagerStatics = {0x2050c4ee, 0x11a0, 0x57de, {0xae, 0xd7, 0xc9, 0x7c, 0x70, 0x33, 0x82, 0x45}};
static const CLSID CLSID_Enumerator = {0xbcde0395, 0xe52f, 0x467c, {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};
static const IID IID_Enumerator = {0xa95664d2, 0x9614, 0x4f35, {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};
static const IID IID_AudioClient = {0x1cb9ad4c, 0xdbfa, 0x4c32, {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2}};
static const IID IID_CaptureClient = {0xc8adbd64, 0xe71e, 0x48a0, {0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17}};
static const GUID SUBTYPE_FLOAT = {0x00000003, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};

enum { STATUS_CLOSED = 0, STATUS_STOPPED = 2, STATUS_PLAYING = 3, STATUS_PAUSED = 4 };
static const char *BUTTONS[] = {"play", "pause", "stop", "record", "fastforward", "rewind", "next", "previous"};

static SOCKET sock;
static sockaddr_in godot = {};
static ISMTC *smtc = nullptr;
static volatile LONG capture_on = 0;
static HANDLE capture_thread = nullptr;
static HANDLE np_thread = nullptr;
static HRESULT last_capture_error = S_OK;  // Report each distinct failure once.

static void send_bytes(const char *data, int len) {
    sendto(sock, data, len, 0, (sockaddr *)&godot, sizeof(godot));
}

static void send_msg(const char *msg) { send_bytes(msg, (int)strlen(msg)); }

static std::string utf8(const wchar_t *w, UINT32 len) {
    if (len == 0) return "";
    int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)len, nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w, (int)len, &s[0], n, nullptr, nullptr);
    return s;
}

static std::string from_hstring(HSTRING h) {
    UINT32 len = 0;
    const wchar_t *w = WindowsGetStringRawBuffer(h, &len);
    std::string s = utf8(w, len);
    WindowsDeleteString(h);
    return s;
}

// --- Media keys (SMTC) ---------------------------------------------------------------

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

static void set_title(const std::string &text) {
    IDisplayUpdater *updater = nullptr;
    IMusicDisplayProperties *music = nullptr;
    if (!smtc || FAILED(smtc->get_DisplayUpdater(&updater))) return;
    updater->put_Type(1);  // MediaPlaybackType::Music
    if (SUCCEEDED(updater->get_MusicProperties(&music))) {
        std::wstring wide(MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), nullptr, 0), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), (int)text.size(), &wide[0], (int)wide.size());
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

// --- System audio capture (WASAPI loopback) -------------------------------------------

static void capture_session() {
    IMMDeviceEnumerator *en = nullptr;
    IMMDevice *dev = nullptr;
    IAudioClient *client = nullptr;
    IAudioCaptureClient *cap = nullptr;
    WAVEFORMATEX *fmt = nullptr;
    char msg[64];
    HRESULT hr = CoCreateInstance(CLSID_Enumerator, nullptr, CLSCTX_ALL, IID_Enumerator, (void **)&en);
    if (SUCCEEDED(hr)) hr = en->GetDefaultAudioEndpoint(eRender, eConsole, &dev);
    if (SUCCEEDED(hr)) hr = dev->Activate(IID_AudioClient, CLSCTX_ALL, nullptr, (void **)&client);
    if (SUCCEEDED(hr)) hr = client->GetMixFormat(&fmt);
    if (SUCCEEDED(hr)) hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2000000, 0, fmt, nullptr);
    if (SUCCEEDED(hr)) hr = client->GetService(IID_CaptureClient, (void **)&cap);
    if (SUCCEEDED(hr)) hr = client->Start();
    if (FAILED(hr)) {
        if (hr != last_capture_error) {
            snprintf(msg, sizeof(msg), "error capture 0x%08lx", (unsigned long)hr);
            send_msg(msg);
        }
        last_capture_error = hr;
    } else {
        last_capture_error = S_OK;
        bool is_float = fmt->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
            (fmt->wFormatTag == WAVE_FORMAT_EXTENSIBLE && ((WAVEFORMATEXTENSIBLE *)fmt)->SubFormat == SUBTYPE_FLOAT);
        int channels = fmt->nChannels;
        int bits = fmt->wBitsPerSample;
        snprintf(msg, sizeof(msg), "fmt %lu", (unsigned long)fmt->nSamplesPerSec);
        send_msg(msg);
        char packet[1 + 480 * 4];
        packet[0] = 1;
        int filled = 0;
        while (capture_on) {
            Sleep(8);
            UINT32 next = 0;
            while (SUCCEEDED(hr = cap->GetNextPacketSize(&next)) && next > 0) {
                BYTE *data = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                if (FAILED(hr = cap->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
                for (UINT32 f = 0; f < frames; f++) {
                    float l = 0.0f, r = 0.0f;
                    if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT)) {
                        if (is_float && bits == 32) {
                            float *p = (float *)data + f * channels;
                            l = p[0];
                            r = channels > 1 ? p[1] : p[0];
                        } else if (bits == 16) {
                            short *p = (short *)data + f * channels;
                            l = p[0] / 32768.0f;
                            r = (channels > 1 ? p[1] : p[0]) / 32768.0f;
                        }
                    }
                    short sl = (short)(l > 1.0f ? 32767 : l < -1.0f ? -32767 : l * 32767.0f);
                    short sr = (short)(r > 1.0f ? 32767 : r < -1.0f ? -32767 : r * 32767.0f);
                    memcpy(packet + 1 + filled * 4, &sl, 2);
                    memcpy(packet + 3 + filled * 4, &sr, 2);
                    if (++filled == 480) {
                        send_bytes(packet, sizeof(packet));
                        filled = 0;
                    }
                }
                cap->ReleaseBuffer(frames);
            }
            if (FAILED(hr)) break;  // e.g. the output device changed: reopen below.
        }
        client->Stop();
    }
    if (fmt) CoTaskMemFree(fmt);
    if (cap) cap->Release();
    if (client) client->Release();
    if (dev) dev->Release();
    if (en) en->Release();
}

static DWORD WINAPI capture_loop(LPVOID) {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    while (capture_on) {
        capture_session();
        for (int i = 0; i < 20 && capture_on; i++) Sleep(100);  // Device changed or missing: retry every 2 s.
    }
    CoUninitialize();
    return 0;
}

// --- Now playing (other apps' media sessions) -----------------------------------------

static bool wait_async(IAsyncOp *op) {
    IAsyncInfoABI *info = nullptr;
    if (FAILED(op->QueryInterface(IID_AsyncInfo, (void **)&info))) return false;
    int status = 0;
    for (int i = 0; i < 300 && SUCCEEDED(info->get_Status(&status)) && status == 0; i++) Sleep(10);
    info->Release();
    return status == 1;
}

static DWORD WINAPI now_playing_loop(LPVOID) {
    RoInitialize(RO_INIT_MULTITHREADED);
    ISessionManager *manager = nullptr;
    HSTRING cls = nullptr;
    const wchar_t *name = L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager";
    WindowsCreateString(name, (UINT32)wcslen(name), &cls);
    ISessionManagerStatics *statics = nullptr;
    if (SUCCEEDED(RoGetActivationFactory(cls, IID_SessionManagerStatics, (void **)&statics))) {
        IAsyncOp *op = nullptr;
        if (SUCCEEDED(statics->RequestAsync(&op))) {
            if (wait_async(op)) op->GetResults((void **)&manager);
            op->Release();
        }
        statics->Release();
    }
    WindowsDeleteString(cls);
    std::string last = "\x01";
    while (capture_on && manager) {
        std::string text;
        ISession *session = nullptr;
        if (SUCCEEDED(manager->GetCurrentSession(&session)) && session) {
            HSTRING app = nullptr;
            std::string app_id = SUCCEEDED(session->get_SourceAppUserModelId(&app)) ? from_hstring(app) : "";
            IAsyncOp *op = nullptr;
            if (app_id.find("TinserBox") == std::string::npos && SUCCEEDED(session->TryGetMediaPropertiesAsync(&op))) {
                IMediaProps *props = nullptr;
                if (wait_async(op) && SUCCEEDED(op->GetResults((void **)&props)) && props) {
                    HSTRING t = nullptr, a = nullptr;
                    std::string title = SUCCEEDED(props->get_Title(&t)) ? from_hstring(t) : "";
                    std::string artist = SUCCEEDED(props->get_Artist(&a)) ? from_hstring(a) : "";
                    if (!title.empty()) text = title + "\t" + artist;
                    props->Release();
                }
                op->Release();
            }
            session->Release();
        }
        if (text != last) {
            last = text;
            send_msg(("np " + text).c_str());
        }
        for (int i = 0; i < 15 && capture_on; i++) Sleep(100);
    }
    if (manager) manager->Release();
    return 0;
}

// --- Commands from TinserBox --------------------------------------------------------------

static void set_capture(bool on) {
    if (on && !capture_on) {
        InterlockedExchange(&capture_on, 1);
        capture_thread = CreateThread(nullptr, 0, capture_loop, nullptr, 0, nullptr);
        np_thread = CreateThread(nullptr, 0, now_playing_loop, nullptr, 0, nullptr);
    } else if (!on && capture_on) {
        InterlockedExchange(&capture_on, 0);
        HANDLE threads[2] = {capture_thread, np_thread};
        WaitForMultipleObjects(2, threads, TRUE, 4000);
        CloseHandle(capture_thread);
        CloseHandle(np_thread);
    }
}

static DWORD WINAPI receive_loop(LPVOID) {
    RoInitialize(RO_INIT_MULTITHREADED);
    char buf[2048];
    for (;;) {
        int n = recv(sock, buf, sizeof(buf) - 1, 0);
        if (n <= 0) continue;
        buf[n] = 0;
        std::string msg(buf);
        if (msg == "capture on") set_capture(true);
        else if (msg == "capture off") set_capture(false);
        else if (!smtc) continue;
        else if (msg == "state playing") smtc->put_PlaybackStatus(STATUS_PLAYING);
        else if (msg == "state paused") smtc->put_PlaybackStatus(STATUS_PAUSED);
        else if (msg == "state stopped") smtc->put_PlaybackStatus(STATUS_STOPPED);
        else if (msg == "smtc off") {
            // Visualizing another app: step aside so its media keys and title take over.
            smtc->put_PlaybackStatus(STATUS_CLOSED);
            smtc->put_IsEnabled(false);
        } else if (msg == "smtc on") {
            smtc->put_IsEnabled(true);
            smtc->put_PlaybackStatus(STATUS_STOPPED);
        } else if (msg.rfind("title ", 0) == 0) set_title(msg.substr(6));
    }
}

static void report(const char *step, HRESULT hr) {
    char msg[128];
    snprintf(msg, sizeof(msg), "error %s 0x%08lx", step, (unsigned long)hr);
    send_msg(msg);
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
    int sndbuf = 1 << 20;
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, (const char *)&sndbuf, sizeof(sndbuf));
    godot.sin_family = AF_INET;
    godot.sin_port = htons((u_short)port);
    godot.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    RoInitialize(RO_INIT_MULTITHREADED);

    // Media keys are optional: if SMTC is unavailable, capture still works.
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
    EventRegistrationToken token = {};
    HRESULT hr = RoGetActivationFactory(class_name, IID_ISMTCInterop, (void **)&interop);
    if (SUCCEEDED(hr)) hr = interop->GetForWindow(hwnd, IID_ISMTC, (void **)&smtc);
    if (SUCCEEDED(hr)) {
        smtc->put_IsEnabled(true);
        smtc->put_IsPlayEnabled(true);
        smtc->put_IsPauseEnabled(true);
        smtc->put_IsStopEnabled(true);
        smtc->put_IsNextEnabled(true);
        smtc->put_IsPreviousEnabled(true);
        smtc->put_PlaybackStatus(STATUS_STOPPED);
        hr = smtc->add_ButtonPressed(&handler, &token);
    }
    if (FAILED(hr)) {
        report("smtc", hr);
        smtc = nullptr;
    }

    CreateThread(nullptr, 0, receive_loop, nullptr, 0, nullptr);
    send_msg(smtc ? "hello" : "hello nokeys");

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
    InterlockedExchange(&capture_on, 0);
    if (smtc) {
        smtc->put_PlaybackStatus(STATUS_CLOSED);
        smtc->remove_ButtonPressed(token);
    }
    return 0;
}
