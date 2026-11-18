#pragma once

#include <QtCore/QList>
#include <QtCore/QString>
#include <cstdint>

struct wl_display;
struct wl_event_queue;
struct wl_compositor;
struct wl_subcompositor;
struct wl_shm;
struct wl_surface;
struct wp_color_manager_v1;
struct wp_image_description_v1;
struct wp_viewporter;
struct wp_alpha_modifier_v1;
class QWindow;

/// What the Wayland compositor offers for surfaces of our own beside Qt's
/// (the HDR video picture and the HDR test): bound once, on an event queue
/// of ours on Qt's connection, so Qt's own event handling is untouched.
struct WlColor
{
    /// The one instance (nullptr when not on Wayland).
    static WlColor *get();

    wl_display *display = nullptr;
    wl_event_queue *queue = nullptr;
    wl_compositor *compositor = nullptr;
    wl_subcompositor *subcompositor = nullptr;
    wl_shm *shm = nullptr;
    wp_color_manager_v1 *manager = nullptr;
    wp_viewporter *viewporter = nullptr;
    wp_alpha_modifier_v1 *alpha = nullptr;
    QList<uint32_t> features, tfs, primaries, shmFormats;
    bool managerDone = false;

    /// PQ with BT.2020 primaries can be described (parametric).
    bool pqCapable() const;
    /// Why HDR can't be had here ("" when it can).
    QString missing() const;
    /// A new PQ / BT.2020 description, waited for (nullptr if refused;
    /// `why` says why).
    wp_image_description_v1 *pqDescription(QString *why = nullptr);
    /// Qt's own surface of `window` (nullptr if it has none now).
    static wl_surface *surfaceOf(QWindow *window);
    /// Each finding, one per line.
    QString report() const;

private:
    WlColor() = default;
};
