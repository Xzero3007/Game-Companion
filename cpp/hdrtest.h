#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QRect>
#include <QtCore/QString>

class QWindow;
struct wl_surface;
struct wl_subsurface;
struct wl_buffer;
struct wp_color_management_surface_v1;
struct wp_image_description_v1;

/// HDR test picture (MN, 2026-11-18, "Weg C"): a small Wayland subsurface
/// under one of our windows, filled with PQ (SMPTE ST 2084, BT.2020) grey
/// patches of known brightness and described to the compositor through
/// wp_color_management_v1. The window above stays see-through there and
/// labels them. With HDR on in KDE the bright patches glow brighter than
/// the overlay's white. Wayland only; elsewhere it says so.
class HdrTest : public QObject
{
    Q_OBJECT
public:
    explicit HdrTest(QObject *parent = nullptr);
    ~HdrTest() override;

    /// Shows the picture under `window` at `area` (window coordinates,
    /// logical pixels). Returns the findings, one per line.
    QString show(QWindow *window, const QRect &area);
    /// Takes it away (also when its window hides).
    void hide();
    /// The nits of each patch, left to right.
    static QList<int> patchNits();

private:
    wl_surface *m_surface = nullptr;
    wl_subsurface *m_subsurface = nullptr;
    wl_buffer *m_buffer = nullptr;
    wp_color_management_surface_v1 *m_cmSurface = nullptr;
    wp_image_description_v1 *m_description = nullptr;
    void *m_pixels = nullptr;
    size_t m_size = 0;
    QPointer<QWindow> m_window;
    QMetaObject::Connection m_visibleConn;
};
