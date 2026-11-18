#include "hdrtest.h"
#include "wlcolor.h"

#include <QtGui/QWindow>
#include <QtQuick/QQuickWindow>

#include <wayland-client.h>
#include "protocols/color-management-v1-client.h"

#include <cmath>
#include <sys/mman.h>
#include <unistd.h>

namespace {

// SMPTE ST 2084 (PQ): nits → signal 0..1.
double pq(double nits)
{
    const double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 4096.0 * 128.0;
    const double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 4096.0 * 32.0, c3 = 2392.0 / 4096.0 * 32.0;
    const double y = std::pow(std::max(0.0, nits) / 10000.0, m1);
    return std::pow((c1 + c2 * y) / (1.0 + c3 * y), m2);
}

} // namespace

HdrTest::HdrTest(QObject *parent) : QObject(parent) {}

HdrTest::~HdrTest()
{
    hide();
}

QList<int> HdrTest::patchNits()
{
    return { 203, 400, 800, 1200, 1900 };
}

QString HdrTest::show(QWindow *window, const QRect &area)
{
    QString report;
    hide();
    WlColor *wl = WlColor::get();
    if (!wl) {
        return QStringLiteral("not on Wayland: no HDR test\n");
    }
    report += wl->report();
    wl_surface *parent = WlColor::surfaceOf(window);
    if (!parent || area.isEmpty() || !wl->compositor || !wl->subcompositor || !wl->shm) {
        report += QStringLiteral("window or compositor parts missing: no HDR test\n");
        return report;
    }
    QString why;
    m_description = wl->pqDescription(&why);
    const bool hdr = m_description != nullptr;
    report += hdr ? QStringLiteral("HDR description (PQ, BT.2020): accepted\n")
                  : QStringLiteral("no HDR description (%1): the patches show as plain greys\n").arg(why);

    // 10 bits per channel if the compositor takes them, else 8.
    const bool deep = wl->shmFormats.contains(WL_SHM_FORMAT_XRGB2101010);
    const uint32_t format = deep ? WL_SHM_FORMAT_XRGB2101010 : WL_SHM_FORMAT_XRGB8888;
    report += QStringLiteral("buffer: %1\n").arg(deep ? QStringLiteral("10 bit (XRGB2101010)") : QStringLiteral("8 bit (XRGB8888)"));

    const int scale = std::max(1, int(std::ceil(window->devicePixelRatio())));
    const int w = area.width() * scale, h = area.height() * scale;
    const int stride = w * 4;
    m_size = size_t(stride) * size_t(h);
    const int fd = memfd_create("gc-hdr-test", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, off_t(m_size)) != 0) {
        if (fd >= 0) close(fd);
        hide();
        return report + QStringLiteral("no memory for the picture\n");
    }
    m_pixels = mmap(nullptr, m_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (m_pixels == MAP_FAILED) {
        m_pixels = nullptr;
        close(fd);
        hide();
        return report + QStringLiteral("no memory for the picture\n");
    }

    // Upper part: one grey patch per brightness; lower band: 0 to 2000 nits (MN's LG G5: 1900 peak, 800 paper white).
    // Without an HDR description the same places are plain sRGB greys.
    auto code = [&](double nits) {
        const double v = hdr ? pq(nits) : std::min(1.0, nits / 203.0);
        return deep ? uint32_t(std::lround(v * 1023.0)) : uint32_t(std::lround(v * 255.0));
    };
    auto pixel = [&](uint32_t c) { return deep ? (c << 20) | (c << 10) | c : (c << 16) | (c << 8) | c; };
    const QList<int> nits = patchNits();
    const int top = h * 22 / 100, patchH = h * 46 / 100, bandTop = h * 78 / 100, bandH = h * 14 / 100;
    const int gap = 8 * scale, patchW = (w - gap * (int(nits.size()) + 1)) / int(nits.size());
    auto *px = static_cast<uint32_t *>(m_pixels);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint32_t value = pixel(0);
            if (y >= top && y < top + patchH) {
                const int i = (x - gap) / (patchW + gap);
                const int inPatch = (x - gap) % (patchW + gap);
                if (x >= gap && i < nits.size() && inPatch < patchW) value = pixel(code(nits[i]));
            } else if (y >= bandTop && y < bandTop + bandH && x >= gap && x < w - gap) {
                value = pixel(code(2000.0 * double(x - gap) / double(w - 2 * gap)));
            }
            px[size_t(y) * size_t(w) + size_t(x)] = value;
        }
    }

    wl_shm_pool *pool = wl_shm_create_pool(wl->shm, fd, int32_t(m_size));
    m_buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, format);
    wl_shm_pool_destroy(pool);
    close(fd);

    m_surface = wl_compositor_create_surface(wl->compositor);
    m_subsurface = wl_subcompositor_get_subsurface(wl->subcompositor, m_surface, parent);
    wl_subsurface_set_position(m_subsurface, area.x(), area.y());
    wl_subsurface_place_below(m_subsurface, parent);
    // Clicks go to the window above (or through it), never to the picture.
    wl_region *none = wl_compositor_create_region(wl->compositor);
    wl_surface_set_input_region(m_surface, none);
    wl_region_destroy(none);
    wl_surface_set_buffer_scale(m_surface, scale);
    if (hdr) {
        m_cmSurface = wp_color_manager_v1_get_surface(wl->manager, m_surface);
        wp_color_management_surface_v1_set_image_description(m_cmSurface, m_description, WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    }
    wl_surface_attach(m_surface, m_buffer, 0, 0);
    wl_surface_damage_buffer(m_surface, 0, 0, w, h);
    wl_surface_commit(m_surface);
    // A subsurface's state takes hold with its parent's next commit.
    if (auto *quick = qobject_cast<QQuickWindow *>(window)) quick->update();
    else window->requestUpdate();
    wl_display_flush(wl->display);

    m_window = window;
    m_visibleConn = connect(window, &QWindow::visibleChanged, this, [this](bool on) { if (!on) hide(); });
    report += QStringLiteral("shown: %1x%2 at scale %3\n").arg(area.width()).arg(area.height()).arg(scale);
    return report;
}

void HdrTest::hide()
{
    disconnect(m_visibleConn);
    const bool had = m_surface != nullptr;
    if (m_cmSurface) { wp_color_management_surface_v1_destroy(m_cmSurface); m_cmSurface = nullptr; }
    if (m_description) { wp_image_description_v1_destroy(m_description); m_description = nullptr; }
    if (m_subsurface) { wl_subsurface_destroy(m_subsurface); m_subsurface = nullptr; }
    if (m_surface) { wl_surface_destroy(m_surface); m_surface = nullptr; }
    if (m_buffer) { wl_buffer_destroy(m_buffer); m_buffer = nullptr; }
    if (m_pixels) { munmap(m_pixels, m_size); m_pixels = nullptr; m_size = 0; }
    if (had) {
        if (auto *quick = qobject_cast<QQuickWindow *>(m_window.data())) quick->update();
        if (WlColor *wl = WlColor::get()) wl_display_flush(wl->display);
    }
    m_window = nullptr;
}
