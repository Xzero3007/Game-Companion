// The overlay window's native side: KDE's overlay layer, the input region
// (where clicks are taken; everywhere else they go to the game) and the
// keyboard. Exposed to QML as `nativeWindow`.
#pragma once

#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QString>
#include <QtGui/QRegion>
#include <cstdint>

class QQuickWindow;

class NativeWindow : public QObject
{
    Q_OBJECT
    /// Whether the overlay is on KDE's overlay layer (above fullscreen games).
    Q_PROPERTY(bool layerShell READ layerShell CONSTANT)
    /// GC_DEMO for screenshots: "unlocked", "settings", comma-separated.
    Q_PROPERTY(QString demo READ demo CONSTANT)

public:
    explicit NativeWindow(QObject *parent = nullptr);

    /// Puts the window on the overlay layer (or above other windows where
    /// there is none) and shows it.
    void attach(QQuickWindow *window);

    bool layerShell() const { return m_layerShell; }
    QString demo() const { return m_demo; }

    /// The rectangles (window coordinates) that take clicks. Everything else
    /// lets clicks through to the game.
    Q_INVOKABLE void setInputRects(const QVariantList &rects);

    /// Whether the overlay may take the keyboard (only while unlocked, and
    /// only when clicked into: the game keeps it otherwise).
    Q_INVOKABLE void setKeyboard(bool wanted);

private:
    /// Gives the window the input region last asked for. Again after the
    /// window is shown: before that, Wayland has no surface to give it to.
    void applyInputRegion();

    QQuickWindow *m_window = nullptr;
    QRegion m_inputRegion = QRegion(0, 0, 1, 1);
    bool m_layerShell = false;
    QString m_demo;
};

int32_t gc_run();
