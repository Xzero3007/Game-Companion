#include "hdrvideo.h"
#include "wlcolor.h"

#include <QtGui/QWindow>
#include <QtQuick/QQuickWindow>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include "protocols/alpha-modifier-v1-client.h"
#include "protocols/color-management-v1-client.h"
#include "protocols/viewporter-client.h"

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstring>

namespace {

void *eglProc(void *, const char *name)
{
    return reinterpret_cast<void *>(eglGetProcAddress(name));
}

// The few GL calls of its own (the rest are mpv's): through EGL, so no
// link to libGL.
using GlGetString = const unsigned char *(*)(unsigned int);
using GlBindFramebuffer = void (*)(unsigned int, unsigned int);
using GlReadPixels = void (*)(int, int, int, int, unsigned int, unsigned int, void *);
using GlGetError = unsigned int (*)();
constexpr unsigned int kGlVendor = 0x1F00, kGlRenderer = 0x1F01, kGlVersion = 0x1F02;
constexpr unsigned int kGlFramebuffer = 0x8D40, kGlRgba = 0x1908, kGlUnsignedByte = 0x1401;

} // namespace

HdrVideo::HdrVideo(Hooks hooks, QObject *parent)
    : QObject(parent)
    , m_hooks(std::move(hooks))
{
}

HdrVideo::~HdrVideo()
{
    detach();
    if (m_thread.joinable()) {
        {
            std::lock_guard<std::mutex> g(m_lock);
            m_quit = true;
        }
        m_wake.notify_all();
        m_thread.join();
    }
    std::lock_guard<std::recursive_mutex> g(m_gui);
    if (m_pq) {
        wp_image_description_v1_destroy(m_pq);
        m_pq = nullptr;
    }
}

QString HdrVideo::unavailable()
{
    WlColor *wl = WlColor::get();
    if (!wl) {
        return QStringLiteral("not on Wayland");
    }
    // GC_HDR_FORCE=1: the surface without PQ (test benches whose compositor
    // can't take it): everything but the HDR description itself.
    static const bool force = qEnvironmentVariableIsSet("GC_HDR_FORCE");
    if (force && wl->compositor && wl->subcompositor) {
        return QString();
    }
    return wl->missing();
}

bool HdrVideo::start()
{
    if (m_thread.joinable()) {
        return m_started;
    }
    const QString why = unavailable();
    if (!why.isEmpty()) {
        m_error = why;
        return false;
    }
    m_thread = std::thread([this] { run(); });
    std::unique_lock<std::mutex> l(m_lock);
    m_ack.wait_for(l, std::chrono::seconds(3), [this] { return m_started || m_failed; });
    if (!m_started && !m_failed) {
        m_error = QStringLiteral("the drawing thread did not start in time");
        m_failed = true;
    }
    return m_started;
}

void HdrVideo::run()
{
    WlColor *wl = WlColor::get();
    auto fail = [this](const QString &why) {
        std::lock_guard<std::mutex> g(m_lock);
        m_error = why;
        m_failed = true;
        m_ack.notify_all();
    };
    // The same EGL display as Qt's (one per wl_display): initialised again
    // here (harmless), never terminated (it would end Qt's too).
    // The way Qt asks for it (a platform display): the same EGLDisplay as
    // Qt's on every driver (NVIDIA's guesses the platform otherwise).
    using GetPlatformDisplay = EGLDisplay (*)(EGLenum, void *, const EGLint *);
    auto getPlatformDisplay = reinterpret_cast<GetPlatformDisplay>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
    constexpr EGLenum kPlatformWayland = 0x31D8; // EGL_PLATFORM_WAYLAND_KHR
    EGLDisplay dpy = getPlatformDisplay ? getPlatformDisplay(kPlatformWayland, wl->display, nullptr) : EGL_NO_DISPLAY;
    if (dpy == EGL_NO_DISPLAY) {
        dpy = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(wl->display));
    }
    if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, nullptr, nullptr)) {
        fail(QStringLiteral("no EGL display"));
        return;
    }
    const char *ext = eglQueryString(dpy, EGL_EXTENSIONS);
    if (!ext || !std::strstr(ext, "EGL_KHR_surfaceless_context")) {
        fail(QStringLiteral("EGL has no surfaceless contexts"));
        return;
    }
    if (!eglBindAPI(EGL_OPENGL_API)) {
        fail(QStringLiteral("EGL has no desktop OpenGL"));
        return;
    }
    // 10 bits per channel (PQ in 8 bits shows bands), else 8; without
    // alpha if there is such a configuration, else with it (NVIDIA offers
    // 10 bits only as RGB10_A2: MN's log said "8 bit"), shown opaque.
    EGLConfig config = nullptr;
    const EGLint wanted[][2] = {{10, 0}, {10, 2}, {8, 0}, {8, 8}};
    for (const auto &[bits, alpha] : wanted) {
        const EGLint want[] = {
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
            EGL_RED_SIZE, bits, EGL_GREEN_SIZE, bits, EGL_BLUE_SIZE, bits, EGL_ALPHA_SIZE, alpha, EGL_NONE,
        };
        EGLConfig configs[64];
        EGLint count = 0;
        if (!eglChooseConfig(dpy, want, configs, 64, &count)) continue;
        for (EGLint i = 0; i < count && !config; ++i) {
            EGLint r = 0, g = 0, b = 0, a = 0;
            eglGetConfigAttrib(dpy, configs[i], EGL_RED_SIZE, &r);
            eglGetConfigAttrib(dpy, configs[i], EGL_GREEN_SIZE, &g);
            eglGetConfigAttrib(dpy, configs[i], EGL_BLUE_SIZE, &b);
            eglGetConfigAttrib(dpy, configs[i], EGL_ALPHA_SIZE, &a);
            if (r == bits && g == bits && b == bits && a == alpha) config = configs[i];
        }
        if (config) {
            m_bits = bits;
            m_alphaBits = alpha;
            break;
        }
    }
    if (!config) {
        fail(QStringLiteral("no EGL configuration for a window"));
        return;
    }
    EGLContext ctx = eglCreateContext(dpy, config, EGL_NO_CONTEXT, nullptr);
    if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        if (ctx != EGL_NO_CONTEXT) eglDestroyContext(dpy, ctx);
        fail(QStringLiteral("no EGL context"));
        return;
    }
    if (!m_hooks.init || !m_hooks.init(eglProc)) {
        eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(dpy, ctx);
        fail(QStringLiteral("mpv could not draw with it"));
        return;
    }
    auto glGetString = reinterpret_cast<GlGetString>(eglGetProcAddress("glGetString"));
    auto glBindFramebuffer = reinterpret_cast<GlBindFramebuffer>(eglGetProcAddress("glBindFramebuffer"));
    auto glReadPixels = reinterpret_cast<GlReadPixels>(eglGetProcAddress("glReadPixels"));
    auto glGetError = reinterpret_cast<GlGetError>(eglGetProcAddress("glGetError"));
    auto str = [&](unsigned int what) {
        const unsigned char *v = glGetString ? glGetString(what) : nullptr;
        return v ? QString::fromUtf8(reinterpret_cast<const char *>(v)) : QStringLiteral("?");
    };
    {
        std::lock_guard<std::mutex> g(m_lock);
        m_info = QStringLiteral("EGL %1 %2; GL %3, %4, %5; %6 bit")
                     .arg(QString::fromUtf8(eglQueryString(dpy, EGL_VENDOR)), QString::fromUtf8(eglQueryString(dpy, EGL_VERSION)),
                          str(kGlVendor), str(kGlRenderer), str(kGlVersion))
                     .arg(m_bits)
                 + (m_alphaBits > 0 ? QStringLiteral(" with %1 bit alpha%2").arg(m_alphaBits).arg(std::strstr(ext, "EGL_EXT_present_opaque") ? ", shown opaque" : "") : QString());
        m_started = true;
        m_ack.notify_all();
    }
    // Whether mpv's frames have any picture at all: a few pixels read back
    // every 60 frames until one isn't black. Six black looks in a row (6 to
    // 12 s of video) mean mpv draws nothing here (MN, 2026-11-18: only
    // black on his NVIDIA card): it fails, and Qt's drawing takes over.
    int framesDrawn = 0, blackLooks = 0;
    bool probing = glBindFramebuffer && glReadPixels;

    EGLSurface surface = EGL_NO_SURFACE;
    wl_egl_window *window = nullptr;
    int w = 0, h = 0;
    for (;;) {
        bool changed = false, resize = false, draw = false;
        {
            std::unique_lock<std::mutex> l(m_lock);
            m_wake.wait(l, [this] { return m_quit || m_windowChanged || m_resize || (m_wantFrame && !m_frozen); });
            if (m_quit) break;
            if (m_windowChanged) {
                changed = true;
                m_windowChanged = false;
                window = m_eglWindow;
            }
            if (m_resize) {
                resize = true;
                m_resize = false;
                w = m_pixW;
                h = m_pixH;
            }
            if (m_wantFrame && !m_frozen) {
                draw = true;
                m_wantFrame = false;
            }
        }
        if (changed) {
            if (surface != EGL_NO_SURFACE) {
                eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx);
                eglDestroySurface(dpy, surface);
                surface = EGL_NO_SURFACE;
            }
            if (window) {
                // A configuration with alpha is still shown opaque (its
                // see-through comes from the alpha modifier alone).
                const bool presentOpaque = m_alphaBits > 0 && std::strstr(ext, "EGL_EXT_present_opaque");
                const EGLint opaque[] = {0x31DF /* EGL_PRESENT_OPAQUE_EXT */, EGL_TRUE, EGL_NONE};
                surface = eglCreateWindowSurface(dpy, config, reinterpret_cast<EGLNativeWindowType>(window), presentOpaque ? opaque : nullptr);
                if (surface != EGL_NO_SURFACE && eglMakeCurrent(dpy, surface, surface, ctx)) {
                    // Paced by mpv's frames, never by the compositor: a
                    // hidden surface must not hold this thread.
                    eglSwapInterval(dpy, 0);
                } else {
                    const EGLint err = eglGetError();
                    if (surface != EGL_NO_SURFACE) eglDestroySurface(dpy, surface);
                    surface = EGL_NO_SURFACE;
                    emit failed(QStringLiteral("no EGL surface (0x%1)").arg(err, 0, 16));
                }
            }
            std::lock_guard<std::mutex> g(m_lock);
            m_surfaceGone = window == nullptr;
            m_ack.notify_all();
            draw = draw || window;
        }
        if (resize && window) {
            wl_egl_window_resize(window, w, h, 0, 0);
            draw = true;
        }
        if (draw && surface != EGL_NO_SURFACE && w > 0 && h > 0) {
            m_hooks.render(w, h);
            ++framesDrawn;
            if (probing && framesDrawn % 60 == 0) {
                glBindFramebuffer(kGlFramebuffer, 0);
                bool lit = false;
                for (int i = 1; i <= 3 && !lit; ++i) {
                    for (int j = 1; j <= 3 && !lit; ++j) {
                        unsigned char px[4] = {0, 0, 0, 0};
                        glReadPixels(w * i / 4, h * j / 4, 1, 1, kGlRgba, kGlUnsignedByte, px);
                        lit = px[0] > 8 || px[1] > 8 || px[2] > 8;
                    }
                }
                if (glGetError) glGetError();
                if (lit) {
                    probing = false;
                } else if (++blackLooks >= 6) {
                    probing = false;
                    emit failed(QStringLiteral("the picture stayed black"));
                }
            }
            if (!eglSwapBuffers(dpy, surface)) {
                const EGLint err = eglGetError();
                std::lock_guard<std::mutex> g(m_lock);
                if (!m_swapFailed) {
                    m_swapFailed = true;
                    emit failed(QStringLiteral("eglSwapBuffers failed (0x%1)").arg(err, 0, 16));
                }
            }
        }
    }
    if (m_hooks.done) m_hooks.done();
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surface != EGL_NO_SURFACE) eglDestroySurface(dpy, surface);
    eglDestroyContext(dpy, ctx);
    eglReleaseThread();
}

void HdrVideo::frame()
{
    {
        std::lock_guard<std::mutex> g(m_lock);
        m_wantFrame = true;
    }
    m_wake.notify_all();
}

void HdrVideo::setFrozen(bool on)
{
    {
        std::lock_guard<std::mutex> g(m_lock);
        m_frozen = on;
    }
    m_wake.notify_all();
}

void HdrVideo::setHdr(bool on)
{
    std::lock_guard<std::recursive_mutex> g(m_gui);
    if (m_hdr == on) return;
    m_hdr = on;
    applyDescription();
}

void HdrVideo::applyDescription()
{
    // Asked for at once (it needs no surface), so `error` tells at once
    // whether the compositor takes it.
    WlColor *wl = WlColor::get();
    if (m_hdr && !m_pq && wl) {
        m_error.clear();
        m_pq = wl->pqDescription(&m_error);
    }
    // Takes hold with the surface's next commit: the next frame.
    if (!m_cm) return;
    if (m_hdr && m_pq) {
        wp_color_management_surface_v1_set_image_description(m_cm, m_pq, WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    } else {
        wp_color_management_surface_v1_unset_image_description(m_cm);
    }
    frame();
}

void HdrVideo::place(QWindow *window, const QRectF &rect, bool shown, qreal opacity)
{
    std::lock_guard<std::recursive_mutex> g(m_gui);
    WlColor *wl = WlColor::get();
    if (!wl || !m_started) return;
    wl_display_dispatch_queue_pending(wl->display, wl->queue);
    wl_surface *parent = shown ? WlColor::surfaceOf(window) : nullptr;
    const QRect r = rect.toRect();
    if (!parent || r.width() < 2 || r.height() < 2) {
        detach();
        return;
    }
    if (parent != m_parent || !m_surface) {
        detach();
        m_parent = parent;
        m_window = window;
        m_surface = wl_compositor_create_surface(wl->compositor);
        m_subsurface = wl_subcompositor_get_subsurface(wl->subcompositor, m_surface, parent);
        wl_subsurface_place_below(m_subsurface, parent);
        // Frames come when mpv has them, not with the window's commits.
        wl_subsurface_set_desync(m_subsurface);
        wl_region *none = wl_compositor_create_region(wl->compositor);
        wl_surface_set_input_region(m_surface, none);
        wl_region_destroy(none);
        if (wl->viewporter) m_viewport = wp_viewporter_get_viewport(wl->viewporter, m_surface);
        if (wl->alpha) m_alpha = wp_alpha_modifier_v1_get_surface(wl->alpha, m_surface);
        if (wl->manager) m_cm = wp_color_manager_v1_get_surface(wl->manager, m_surface);
        applyDescription();
        m_eglWindowOwned = wl_egl_window_create(m_surface, 16, 16);
        m_rect = QRectF();
        m_opacity = -1;
        {
            std::lock_guard<std::mutex> l(m_lock);
            m_eglWindow = m_eglWindowOwned;
            m_windowChanged = true;
        }
        m_wake.notify_all();
        m_visibleConn = connect(window, &QWindow::visibleChanged, this, [this](bool on) { if (!on) detach(); });
    }
    if (QRectF(r) != m_rect) {
        const qreal dpr = window->devicePixelRatio();
        int pw = std::max(1, int(std::lround(r.width() * dpr)));
        int ph = std::max(1, int(std::lround(r.height() * dpr)));
        if (m_viewport) {
            wp_viewport_set_destination(m_viewport, r.width(), r.height());
        } else {
            const int scale = std::max(1, int(std::ceil(dpr)));
            wl_surface_set_buffer_scale(m_surface, scale);
            pw = r.width() * scale;
            ph = r.height() * scale;
        }
        // The place takes hold with the window's next commit (it is drawn
        // right after this, or asked for below).
        wl_subsurface_set_position(m_subsurface, r.x(), r.y());
        {
            std::lock_guard<std::mutex> l(m_lock);
            m_pixW = pw;
            m_pixH = ph;
            m_resize = true;
            m_wantFrame = true;
        }
        m_wake.notify_all();
        m_rect = r;
    }
    if (m_alpha && !qFuzzyCompare(opacity + 1, m_opacity + 1)) {
        wp_alpha_modifier_surface_v1_set_multiplier(m_alpha, uint32_t(std::clamp(opacity, 0.0, 1.0) * double(UINT32_MAX)));
        m_opacity = opacity;
        frame();
    }
    wl_display_flush(wl->display);
}

void HdrVideo::detach()
{
    std::lock_guard<std::recursive_mutex> g(m_gui);
    if (!m_surface) return;
    disconnect(m_visibleConn);
    // The drawing thread lets its EGL surface go first.
    {
        std::unique_lock<std::mutex> l(m_lock);
        m_eglWindow = nullptr;
        m_windowChanged = true;
        m_surfaceGone = false;
        m_wake.notify_all();
        if (m_started && !m_failed) {
            m_ack.wait_for(l, std::chrono::seconds(1), [this] { return m_surfaceGone || m_quit; });
        }
    }
    // The wl_egl_window is the GUI side's: gone only now.
    if (m_eglWindowOwned) { wl_egl_window_destroy(m_eglWindowOwned); m_eglWindowOwned = nullptr; }
    if (m_cm) { wp_color_management_surface_v1_destroy(m_cm); m_cm = nullptr; }
    if (m_alpha) { wp_alpha_modifier_surface_v1_destroy(m_alpha); m_alpha = nullptr; }
    if (m_viewport) { wp_viewport_destroy(m_viewport); m_viewport = nullptr; }
    if (m_subsurface) { wl_subsurface_destroy(m_subsurface); m_subsurface = nullptr; }
    if (m_surface) { wl_surface_destroy(m_surface); m_surface = nullptr; }
    m_parent = nullptr;
    m_rect = QRectF();
    if (WlColor *wl = WlColor::get()) wl_display_flush(wl->display);
    // The window redraws without the picture under it (from any thread).
    if (auto *quick = qobject_cast<QQuickWindow *>(m_window.data())) QMetaObject::invokeMethod(quick, "update", Qt::QueuedConnection);
    m_window = nullptr;
}
