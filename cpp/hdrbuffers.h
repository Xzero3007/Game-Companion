#pragma once

#include <QtCore/QString>

#include <array>
#include <cstddef>
#include <cstdint>

struct wl_buffer;
struct wl_display;
struct wl_event_queue;
struct wl_surface;
struct wl_shm;
struct zwp_linux_dmabuf_v1;
struct gbm_device;
struct gbm_bo;

/// The HDR video's frames handed to the compositor as buffers of our own
/// (0.8.78), not through an EGL window surface: on MN's NVIDIA 620
/// egl-wayland showed nothing (mpv's frame was there, the window's frame
/// buffer stayed 0/0/0) and offered no 10 bits at all, while the HDR test
/// (a buffer of its own) showed PQ in 10 bits.
///
/// Two ways, the first that works:
/// - dmabuf: buffers in graphics memory (GBM), drawn into by GL through an
///   EGLImage and handed to the compositor as they are (no copy), 10 bits
///   (XBGR2101010) where offered;
/// - shm: mpv draws into a texture of ours, read back into shared memory
///   (10 bits as XBGR2101010 where offered), as the HDR test does: one copy
///   per frame, so only where dmabuf can't be had.
///
/// Lives on the HDR drawing thread with its EGL context current; its
/// Wayland objects are on an event queue of its own.
class HdrBuffers
{
public:
    enum class Way { None, Dmabuf, Shm };

    /// `forced`: "dmabuf" or "shm" (GC_HDR_PATH) tries only that one.
    HdrBuffers(void *eglDisplay, const QString &forced);
    ~HdrBuffers();

    /// Picks the way (dmabuf, else shm). False if neither can be had
    /// (`why`). `notes` gets why dmabuf was passed over.
    bool begin(QString *why, QString *notes);
    Way way() const { return m_way; }
    int bits() const { return m_bits; }
    /// For the log: "dmabuf XB30 (10 bit)", "shm XR24 (8 bit)".
    QString describe() const;

    /// The frame buffer to draw the next frame into (`w`×`h` pixels, top
    /// row first), with its GL internal format; 0 when no buffer is free
    /// (the compositor holds them all) or they couldn't be made: then
    /// `error` tells why, and the way may have changed (dmabuf → shm).
    unsigned int target(int w, int h, int *internalFormat, QString *note);
    /// Hands the frame drawn into `target`'s frame buffer to `surface`.
    void present(wl_surface *surface);
    /// Lets every buffer go (the surface goes, or the size changes).
    void dropBuffers();
    QString error() const { return m_error; }
    /// wl_buffer.release (the compositor is done with the buffer).
    static void onRelease(void *data, wl_buffer *buffer);

private:
    struct Buf
    {
        wl_buffer *buffer = nullptr;
        bool busy = false;
        // dmabuf
        gbm_bo *bo = nullptr;
        void *image = nullptr; // EGLImage
        unsigned int tex = 0, fbo = 0;
        // shm
        void *data = nullptr;
        size_t size = 0;
    };

    bool beginDmabuf(QString *why);
    bool beginShm(QString *why);
    bool makeDmabuf(Buf &b, QString *why);
    bool makeShm(Buf &b, QString *why);
    bool makeBuffers(QString *why);
    Buf *takeFree();

    void *m_dpy;
    QString m_forced;
    Way m_way = Way::None;
    int m_bits = 8;
    uint32_t m_format = 0;
    std::array<uint64_t, 64> m_mods{};
    int m_modCount = 0; // 0: no modifiers (implicit layout)
    uint64_t m_modifier = 0;
    int m_planes = 1;
    wl_display *m_display = nullptr;
    wl_event_queue *m_queue = nullptr;
    zwp_linux_dmabuf_v1 *m_dmabuf = nullptr; // wrapped onto m_queue
    wl_shm *m_shm = nullptr;                  // wrapped onto m_queue
    int m_drmFd = -1;
    gbm_device *m_gbm = nullptr;
    std::array<Buf, 3> m_bufs;
    Buf *m_current = nullptr;
    int m_w = 0, m_h = 0;
    // shm: mpv's frame buffer (a texture), read back into the buffer.
    unsigned int m_tex = 0, m_fbo = 0;
    QString m_error;
    bool m_noted = false;
};
