#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QRectF>
#include <QtCore/QString>

#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>

class QWindow;
struct wl_surface;
struct wl_subsurface;
struct wl_egl_window;
struct wp_viewport;
struct wp_alpha_modifier_surface_v1;
struct wp_color_management_surface_v1;
struct wp_image_description_v1;

/// The video picture on a surface of its own (MN, 2026-11-18, "Weg C"): a
/// Wayland subsurface right under the video window's surface, drawn by a
/// thread of its own with an EGL context of its own (10 bits per channel),
/// described to KWin as PQ / BT.2020 while an HDR video plays, else as
/// plain sRGB. The window above stays see-through over it, so its bars,
/// lists and notes lie on the picture as before. The subsurface moves and
/// resizes with the window by itself; it never takes clicks.
///
/// mpv's render context lives on this thread (the hooks): `init` makes it
/// once the context is current, `render` draws into the default frame
/// buffer, `done` lets it go before the context goes.
class HdrVideo : public QObject
{
    Q_OBJECT
public:
    struct Hooks
    {
        /// Called on the drawing thread with the context current; false if
        /// mpv could not take it. `getProc` resolves GL functions.
        std::function<bool(void *(*getProc)(void *, const char *))> init;
        /// Draws one frame: default frame buffer, `w`×`h` pixels, 10 bit.
        std::function<void(int w, int h)> render;
        /// Called on the drawing thread before the context goes.
        std::function<void()> done;
    };

    explicit HdrVideo(Hooks hooks, QObject *parent = nullptr);
    ~HdrVideo() override;

    /// Why it can't run here ("" when it can): Wayland, colour management
    /// with PQ, subsurfaces.
    static QString unavailable();
    /// Starts the drawing thread and waits for its context and mpv's
    /// render context (at most 3 s). False (and `error`) if that failed.
    bool start();
    QString error() const { return m_error; }
    /// Bits per colour channel of its frames (10, or 8 where there is no 10).
    int bits() const { return m_bits; }
    /// For the log: EGL's and GL's vendor, renderer and version, the bits.
    QString info() const { return m_info; }

    /// Where the picture is: in `window`'s coordinates (logical pixels),
    /// shown or not. Made, moved and taken away as needed. Call on the GUI
    /// thread, or on Qt's render thread while the GUI thread waits.
    void place(QWindow *window, const QRectF &rect, bool shown, qreal opacity);
    /// Takes the surface away at once (its window hides or goes).
    void detach();
    /// HDR (PQ, BT.2020) or plain sRGB from the next frame.
    void setHdr(bool on);
    bool hdr() const { return m_hdr; }
    /// Frames wait (dragging, Spectacle): the last one stays.
    void setFrozen(bool on);
    /// mpv has a new frame (any thread).
    void frame();

signals:
    /// It stopped working after it started (from the drawing thread).
    void failed(const QString &why);

private:
    void run();
    void applyDescription();

    Hooks m_hooks;
    QString m_error;
    int m_bits = 0;
    int m_alphaBits = 0;
    QString m_info;
    bool m_swapFailed = false;
    std::thread m_thread;
    std::mutex m_lock;
    std::condition_variable m_wake, m_ack;
    // Shared with the drawing thread (under m_lock).
    bool m_quit = false, m_wantFrame = false, m_frozen = false;
    bool m_started = false, m_failed = false;
    wl_egl_window *m_eglWindow = nullptr; // set by the GUI thread
    bool m_windowChanged = false, m_surfaceGone = true;
    int m_pixW = 0, m_pixH = 0;
    bool m_resize = false;

    // GUI side (Qt's render thread too, while the GUI thread waits).
    std::recursive_mutex m_gui;
    wl_egl_window *m_eglWindowOwned = nullptr;
    QPointer<QWindow> m_window;
    wl_surface *m_parent = nullptr;
    wl_surface *m_surface = nullptr;
    wl_subsurface *m_subsurface = nullptr;
    wp_viewport *m_viewport = nullptr;
    wp_alpha_modifier_surface_v1 *m_alpha = nullptr;
    wp_color_management_surface_v1 *m_cm = nullptr;
    wp_image_description_v1 *m_pq = nullptr;
    QRectF m_rect;
    qreal m_opacity = 1;
    bool m_shown = false;
    bool m_hdr = false;
    QMetaObject::Connection m_visibleConn;
};
