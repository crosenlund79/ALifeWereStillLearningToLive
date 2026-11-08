// TinserBoxMedia.exe — small Windows helper for TinserBox.
//
// 1. Media keys: registers TinserBox with System Media Transport Controls (SMTC), so
//    hardware Play/Pause, Next, Previous and Stop reach TinserBox even when unfocused.
//    Windows routes media keys to the active SMTC session, so other players keep theirs.
// 2. System audio ("visualize Spotify etc."): captures what the default output device
//    plays (WASAPI loopback; no drivers or admin rights) and streams it to TinserBox as
//    16-bit stereo PCM, so the visualizers can follow any app.
// 3. Recording: writes the captured system output to MP3 (Windows' Media Foundation MP3
//    encoder, 320 kbps) or, if that encoder is unavailable, to 16-bit PCM WAV. Gaps where
//    nothing plays are filled with silence so recordings keep real time.
// 4. Now playing: while capturing, reads the title/artist of the current media session
//    (Spotify, browsers, ...) via GlobalSystemMediaTransportControlsSessionManager.
//
// Usage: TinserBoxMedia.exe <godot_udp_port> <godot_pid>
// To Godot (UDP 127.0.0.1:<port>): "hello", "play", "pause", "stop", "next", "previous",
//   "fmt <rate>", "np <title>\t<artist>", "error <step> <hr>", binary PCM packets (0x01 + int16 L/R).
// From Godot: "state playing|paused|stopped", "title <text>", "capture on|off", "smtc on|off",
//   "rec start <path without extension>", "rec stop".
// Recording replies: "rec started mp3|wav <path>", "rec done <seconds> <path>", "rec error <what>".
// Exits when TinserBox exits.
#include <winsock2.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
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
#include <algorithm>
#include <cmath>

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
static volatile LONG capture_on = 0;  // Visualizing: send PCM to TinserBox.
static volatile LONG recording = 0;   // Writing to a file.
static volatile LONG capture_running = 0;
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

// --- Recorder: MP3 via Media Foundation, else WAV -----------------------------------------

static CRITICAL_SECTION rec_lock;
static std::wstring rec_request;  // Path (no extension) waiting for the capture format.
static bool rec_stop_request = false;
static IMFSinkWriter *rec_writer = nullptr;
static DWORD rec_stream = 0;
static FILE *rec_wav = nullptr;
static UINT64 rec_frames = 0;
static int rec_rate = 0;
static std::wstring rec_path;
static LARGE_INTEGER rec_t0, qpc_freq;

static std::wstring widen(const std::string &s) {
    std::wstring w(MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], (int)w.size());
    return w;
}

static bool open_mp3(const std::wstring &path, int rate) {
    static bool mf_started = false;
    if (!mf_started) mf_started = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
    if (!mf_started || (rate != 32000 && rate != 44100 && rate != 48000)) return false;
    IMFMediaType *out = nullptr, *in = nullptr;
    HRESULT hr = MFCreateSinkWriterFromURL(path.c_str(), nullptr, nullptr, &rec_writer);
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&out);
    if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_MP3);
    if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate);
    if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
    if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 320000 / 8);
    if (SUCCEEDED(hr)) hr = rec_writer->AddStream(out, &rec_stream);
    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&in);
    if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
    if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, rate * 4);
    if (SUCCEEDED(hr)) hr = rec_writer->SetInputMediaType(rec_stream, in, nullptr);
    if (SUCCEEDED(hr)) hr = rec_writer->BeginWriting();
    if (out) out->Release();
    if (in) in->Release();
    if (FAILED(hr) && rec_writer) {
        rec_writer->Release();
        rec_writer = nullptr;
        DeleteFileW(path.c_str());
    }
    return SUCCEEDED(hr);
}

static void wav_header(FILE *f, int rate, UINT32 data_bytes) {
    UINT32 riff = 36 + data_bytes, fmt_len = 16, byte_rate = rate * 4, srate = rate;
    UINT16 pcm = 1, ch = 2, align = 4, bits = 16;
    fseek(f, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt_len, 4, 1, f); fwrite(&pcm, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&srate, 4, 1, f);
    fwrite(&byte_rate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data_bytes, 4, 1, f);
}

// Called from the capture thread with the lock held.
static void rec_open(int rate) {
    std::wstring base = rec_request;
    rec_request.clear();
    rec_frames = 0;
    rec_rate = rate;
    QueryPerformanceFrequency(&qpc_freq);
    QueryPerformanceCounter(&rec_t0);
    const char *kind = "mp3";
    rec_path = base + L".mp3";
    if (!open_mp3(rec_path, rate)) {
        kind = "wav";
        rec_path = base + L".wav";
        rec_wav = _wfopen(rec_path.c_str(), L"wb");
        if (rec_wav) wav_header(rec_wav, rate, 0);
    }
    if (!rec_writer && !rec_wav) {
        send_msg("rec error file");
        InterlockedExchange(&recording, 0);
        return;
    }
    std::string msg = std::string("rec started ") + kind + " " + utf8(rec_path.c_str(), (UINT32)rec_path.size());
    send_msg(msg.c_str());
}

static void rec_write(const short *pcm, UINT32 frames) {
    if (frames == 0) return;
    if (rec_writer) {
        IMFMediaBuffer *buf = nullptr;
        IMFSample *sample = nullptr;
        BYTE *dst = nullptr;
        DWORD bytes = frames * 4;
        if (SUCCEEDED(MFCreateMemoryBuffer(bytes, &buf)) && SUCCEEDED(buf->Lock(&dst, nullptr, nullptr))) {
            memcpy(dst, pcm, bytes);
            buf->Unlock();
            buf->SetCurrentLength(bytes);
            if (SUCCEEDED(MFCreateSample(&sample))) {
                sample->AddBuffer(buf);
                sample->SetSampleTime((LONGLONG)(rec_frames * 10000000ULL / rec_rate));
                sample->SetSampleDuration((LONGLONG)(frames * 10000000ULL / rec_rate));
                rec_writer->WriteSample(rec_stream, sample);
                sample->Release();
            }
        }
        if (buf) buf->Release();
    } else if (rec_wav) {
        fwrite(pcm, 4, frames, rec_wav);
    }
    rec_frames += frames;
}

// Keep real time: when nothing plays, loopback delivers no data, so write silence.
static void rec_fill_silence() {
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    UINT64 expected = (UINT64)((now.QuadPart - rec_t0.QuadPart) * (double)rec_rate / qpc_freq.QuadPart);
    static short zeros[4800 * 2] = {0};
    while (rec_frames + rec_rate / 10 < expected) {
        UINT32 n = (UINT32)std::min((UINT64)4800, expected - rec_frames);
        rec_write(zeros, n);
    }
}

static void rec_close() {
    double seconds = rec_rate ? (double)rec_frames / rec_rate : 0.0;
    if (rec_writer) {
        rec_writer->Finalize();
        rec_writer->Release();
        rec_writer = nullptr;
    }
    if (rec_wav) {
        UINT64 bytes = rec_frames * 4;
        wav_header(rec_wav, rec_rate, (UINT32)std::min(bytes, (UINT64)0xFFFFFFF0ULL));
        fclose(rec_wav);
        rec_wav = nullptr;
    }
    char head[64];
    snprintf(head, sizeof(head), "rec done %.1f ", seconds);
    std::string msg = head + utf8(rec_path.c_str(), (UINT32)rec_path.size());
    send_msg(msg.c_str());
    rec_stop_request = false;
    InterlockedExchange(&recording, 0);
}

static void rec_service(int rate) {
    EnterCriticalSection(&rec_lock);
    if (!rec_request.empty() && !rec_writer && !rec_wav) rec_open(rate);
    if (rec_writer || rec_wav) {
        rec_fill_silence();
        if (rec_stop_request) rec_close();
    }
    LeaveCriticalSection(&rec_lock);
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
        static short frame_buf[4096 * 2];
        int rate = (int)fmt->nSamplesPerSec;
        while (capture_on || recording) {
            Sleep(8);
            UINT32 next = 0;
            while (SUCCEEDED(hr = cap->GetNextPacketSize(&next)) && next > 0) {
                BYTE *data = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                if (FAILED(hr = cap->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
                UINT32 done = 0;
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
                    frame_buf[done * 2] = sl;
                    frame_buf[done * 2 + 1] = sr;
                    if (++done == 4096 || f + 1 == frames) {
                        EnterCriticalSection(&rec_lock);
                        if (rec_writer || rec_wav) rec_write(frame_buf, done);
                        LeaveCriticalSection(&rec_lock);
                        done = 0;
                    }
                    if (capture_on) {
                        memcpy(packet + 1 + filled * 4, &sl, 2);
                        memcpy(packet + 3 + filled * 4, &sr, 2);
                        if (++filled == 480) {
                            send_bytes(packet, sizeof(packet));
                            filled = 0;
                        }
                    }
                }
                cap->ReleaseBuffer(frames);
            }
            rec_service(rate);
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
    while (capture_on || recording) {
        capture_session();
        if (recording && last_capture_error != S_OK) {
            // No output device to record from: give up this recording rather than hang.
            EnterCriticalSection(&rec_lock);
            if (rec_writer || rec_wav) rec_close();
            else {
                rec_request.clear();
                InterlockedExchange(&recording, 0);
                send_msg("rec error capture");
            }
            LeaveCriticalSection(&rec_lock);
        }
        for (int i = 0; i < 20 && (capture_on || recording); i++) Sleep(100);  // Retry every 2 s.
    }
    InterlockedExchange(&capture_running, 0);
    CoUninitialize();
    return 0;
}

static void ensure_capture_thread() {
    if (InterlockedCompareExchange(&capture_running, 1, 0) == 0)
        CloseHandle(CreateThread(nullptr, 0, capture_loop, nullptr, 0, nullptr));
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
        ensure_capture_thread();
        np_thread = CreateThread(nullptr, 0, now_playing_loop, nullptr, 0, nullptr);
    } else if (!on && capture_on) {
        InterlockedExchange(&capture_on, 0);
        WaitForSingleObject(np_thread, 4000);
        CloseHandle(np_thread);
    }
}

static void set_recording(const std::string &path_utf8) {
    EnterCriticalSection(&rec_lock);
    if (!path_utf8.empty()) {
        if (!recording) {
            rec_request = widen(path_utf8);
            rec_stop_request = false;
            InterlockedExchange(&recording, 1);
        }
    } else if (recording) {
        rec_stop_request = true;
    }
    LeaveCriticalSection(&rec_lock);
    if (recording) ensure_capture_thread();
}

static DWORD WINAPI receive_loop(LPVOID) {
    RoInitialize(RO_INIT_MULTITHREADED);
    char buf[2048];
    for (;;) {
        int n = recv(sock, buf, sizeof(buf) - 1, 0);
        if (n <= 0) continue;
        buf[n] = 0;
        std::string msg(buf);
        if (msg.rfind("rec start ", 0) == 0) set_recording(msg.substr(10));
        else if (msg == "rec stop") set_recording("");
        else if (msg == "capture on") set_capture(true);
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
    InitializeCriticalSection(&rec_lock);
    if (argc == 3 && wcscmp(argv[1], L"--selftest-rec") == 0) {
        // Diagnostics: write a 3 s 440 Hz tone through the recorder (MP3, else WAV).
        CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        rec_request = argv[2];
        rec_open(48000);
        static short tone[48000 * 2];
        for (int i = 0; i < 48000; i++) tone[i * 2] = tone[i * 2 + 1] = (short)(8000 * sin(i * 2.0 * 3.14159265 * 440.0 / 48000));
        for (int k = 0; k < 3; k++) rec_write(tone, 48000);
        rec_close();
        wprintf(L"%ls\n", rec_path.c_str());
        return 0;
    }
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
    // TinserBox exited: finish any recording so the file is valid.
    if (recording) {
        set_recording("");
        for (int i = 0; i < 50 && recording; i++) Sleep(100);
    }
    InterlockedExchange(&capture_on, 0);
    if (smtc) {
        smtc->put_PlaybackStatus(STATUS_CLOSED);
        smtc->remove_ButtonPressed(token);
    }
    return 0;
}
