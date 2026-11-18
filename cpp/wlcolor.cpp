#include "wlcolor.h"

#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>
#include <qpa/qplatformnativeinterface.h>

#include <wayland-client.h>
#include "protocols/alpha-modifier-v1-client.h"
#include "protocols/color-management-v1-client.h"
#include "protocols/linux-dmabuf-v1-client.h"
#include "protocols/viewporter-client.h"

#include <cstring>

// The protocols' glue (wayland-scanner's private code), compiled here as
// C++: the headers above declared the interfaces extern "C" already.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wattributes"
#include "protocols/alpha-modifier-v1-protocol.c"
#include "protocols/color-management-v1-protocol.c"
#include "protocols/linux-dmabuf-v1-protocol.c"
#include "protocols/viewporter-protocol.c"
#pragma GCC diagnostic pop

namespace {

void onIntent(void *, wp_color_manager_v1 *, uint32_t) {}
void onFeature(void *d, wp_color_manager_v1 *, uint32_t f) { static_cast<WlColor *>(d)->features << f; }
void onTf(void *d, wp_color_manager_v1 *, uint32_t t) { static_cast<WlColor *>(d)->tfs << t; }
void onPrimaries(void *d, wp_color_manager_v1 *, uint32_t p) { static_cast<WlColor *>(d)->primaries << p; }
void onDone(void *d, wp_color_manager_v1 *) { static_cast<WlColor *>(d)->managerDone = true; }
const wp_color_manager_v1_listener managerListener = { onIntent, onFeature, onTf, onPrimaries, onDone };

void onShmFormat(void *d, wl_shm *, uint32_t f) { static_cast<WlColor *>(d)->shmFormats << f; }
const wl_shm_listener shmListener = { onShmFormat };

void onDmabufFormat(void *, zwp_linux_dmabuf_v1 *, uint32_t) {}
void onDmabufModifier(void *d, zwp_linux_dmabuf_v1 *, uint32_t f, uint32_t hi, uint32_t lo)
{
    static_cast<WlColor *>(d)->dmabufFormats << qMakePair(f, (uint64_t(hi) << 32) | lo);
}
const zwp_linux_dmabuf_v1_listener dmabufListener = { onDmabufFormat, onDmabufModifier };

void onGlobal(void *d, wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
    auto *c = static_cast<WlColor *>(d);
    auto is = [&](const wl_interface &i) { return std::strcmp(iface, i.name) == 0; };
    if (is(wl_compositor_interface) && !c->compositor) {
        c->compositor = static_cast<wl_compositor *>(wl_registry_bind(r, name, &wl_compositor_interface, std::min<uint32_t>(version, 4)));
    } else if (is(wl_subcompositor_interface) && !c->subcompositor) {
        c->subcompositor = static_cast<wl_subcompositor *>(wl_registry_bind(r, name, &wl_subcompositor_interface, 1));
    } else if (is(wl_shm_interface) && !c->shm) {
        c->shm = static_cast<wl_shm *>(wl_registry_bind(r, name, &wl_shm_interface, 1));
        wl_shm_add_listener(c->shm, &shmListener, c);
    } else if (is(wp_color_manager_v1_interface) && !c->manager) {
        c->manager = static_cast<wp_color_manager_v1 *>(wl_registry_bind(r, name, &wp_color_manager_v1_interface, 1));
        wp_color_manager_v1_add_listener(c->manager, &managerListener, c);
    } else if (is(wp_viewporter_interface) && !c->viewporter) {
        c->viewporter = static_cast<wp_viewporter *>(wl_registry_bind(r, name, &wp_viewporter_interface, 1));
    } else if (is(wp_alpha_modifier_v1_interface) && !c->alpha) {
        c->alpha = static_cast<wp_alpha_modifier_v1 *>(wl_registry_bind(r, name, &wp_alpha_modifier_v1_interface, 1));
    } else if (is(zwp_linux_dmabuf_v1_interface) && !c->dmabuf && version >= 3) {
        c->dmabuf = static_cast<zwp_linux_dmabuf_v1 *>(wl_registry_bind(r, name, &zwp_linux_dmabuf_v1_interface, 3));
        zwp_linux_dmabuf_v1_add_listener(c->dmabuf, &dmabufListener, c);
    }
}
void onGlobalRemove(void *, wl_registry *, uint32_t) {}
const wl_registry_listener registryListener = { onGlobal, onGlobalRemove };

struct DescWait
{
    int state = 0; // 0 waiting, 1 ready, -1 failed
    QString error;
};
void onDescFailed(void *d, wp_image_description_v1 *, uint32_t cause, const char *msg)
{
    auto *w = static_cast<DescWait *>(d);
    if (!w) return;
    w->state = -1;
    w->error = QStringLiteral("%1 (cause %2)").arg(QString::fromUtf8(msg ? msg : "")).arg(cause);
}
void onDescReady(void *d, wp_image_description_v1 *, uint32_t) { if (d) static_cast<DescWait *>(d)->state = 1; }
const wp_image_description_v1_listener descListener = { onDescFailed, onDescReady };

QString tfName(uint32_t t)
{
    switch (t) {
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ: return QStringLiteral("pq");
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB: return QStringLiteral("srgb");
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_GAMMA22: return QStringLiteral("gamma22");
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_BT1886: return QStringLiteral("bt1886");
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_LINEAR: return QStringLiteral("linear");
    case WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG: return QStringLiteral("hlg");
    default: return QString::number(t);
    }
}

} // namespace

WlColor *WlColor::get()
{
    static WlColor *one = [] () -> WlColor * {
        auto *native = QGuiApplication::platformNativeInterface();
        auto *display = native && QGuiApplication::platformName().startsWith(QLatin1String("wayland"))
            ? static_cast<wl_display *>(native->nativeResourceForIntegration("wl_display")) : nullptr;
        if (!display) {
            return nullptr;
        }
        auto *c = new WlColor;
        c->display = display;
        c->queue = wl_display_create_queue(display);
        auto *wrapped = static_cast<wl_display *>(wl_proxy_create_wrapper(display));
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(wrapped), c->queue);
        wl_registry *registry = wl_display_get_registry(wrapped);
        wl_proxy_wrapper_destroy(wrapped);
        wl_registry_add_listener(registry, &registryListener, c);
        wl_display_roundtrip_queue(display, c->queue); // the globals
        wl_display_roundtrip_queue(display, c->queue); // what they offer
        wl_registry_destroy(registry);
        return c;
    }();
    return one;
}

bool WlColor::pqCapable() const
{
    return manager && features.contains(WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)
        && tfs.contains(WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ)
        && primaries.contains(WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
}

QString WlColor::missing() const
{
    if (!compositor || !subcompositor) return QStringLiteral("no subsurfaces");
    if (!manager) return QStringLiteral("the compositor has no colour management (wp_color_management_v1)");
    if (!pqCapable()) return QStringLiteral("the compositor can't take PQ / BT.2020");
    return QString();
}

wp_image_description_v1 *WlColor::pqDescription(QString *why)
{
    if (!pqCapable()) {
        if (why) *why = missing();
        return nullptr;
    }
    auto *creator = wp_color_manager_v1_create_parametric_creator(manager);
    wp_image_description_creator_params_v1_set_tf_named(creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
    wp_image_description_creator_params_v1_set_primaries_named(creator, WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
    auto *desc = wp_image_description_creator_params_v1_create(creator);
    DescWait wait;
    wp_image_description_v1_add_listener(desc, &descListener, &wait);
    for (int i = 0; i < 20 && wait.state == 0; ++i) {
        if (wl_display_roundtrip_queue(display, queue) < 0) break;
    }
    wp_image_description_v1_set_user_data(desc, nullptr);
    if (wait.state != 1) {
        if (why) *why = wait.error.isEmpty() ? QStringLiteral("no answer") : wait.error;
        wp_image_description_v1_destroy(desc);
        return nullptr;
    }
    // Its listener's data is gone now: no more events are expected.
    return desc;
}

wl_surface *WlColor::surfaceOf(QWindow *window)
{
    auto *native = QGuiApplication::platformNativeInterface();
    return window && native ? static_cast<wl_surface *>(native->nativeResourceForWindow("surface", window)) : nullptr;
}

QString WlColor::report() const
{
    QStringList tf;
    for (uint32_t t : tfs) tf << tfName(t);
    QString out = QStringLiteral("color management: %1\n").arg(manager ? QStringLiteral("yes (wp_color_management_v1)") : QStringLiteral("no"));
    if (manager) {
        out += QStringLiteral("parametric: %1, PQ: %2, BT.2020: %3, curves: %4\n")
                   .arg(features.contains(WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC) ? "yes" : "no",
                        tfs.contains(WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ) ? "yes" : "no",
                        primaries.contains(WP_COLOR_MANAGER_V1_PRIMARIES_BT2020) ? "yes" : "no", tf.join(','));
    }
    out += QStringLiteral("viewporter: %1, alpha modifier: %2\n").arg(viewporter ? "yes" : "no", alpha ? "yes" : "no");
    return out;
}
