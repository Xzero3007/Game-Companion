// The overlay's native side. Every part of the overlay (the bar, the player
// row, each panel, each video) is a small window of its own on KDE's
// overlay layer, just as big as the part: placed by its distance from the
// screen's top left corner, so nothing covers the rest of the screen and a
// video redraws only its own area. Exposed to QML as `nativeWindow`.
#pragma once

#include <QtCore/QObject>
#include <QtCore/QRectF>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <cstdint>

#include <QtQuick/QQuickItem>
class QQuickWindow;
class QScreen;

class NativeWindow : public QObject
{
    Q_OBJECT
    /// Whether the parts are on KDE's overlay layer (above fullscreen games).
    Q_PROPERTY(bool layerShell READ layerShell CONSTANT)
    /// GC_DEMO for screenshots: "unlocked", "settings", comma-separated.
    Q_PROPERTY(QString demo READ demo CONSTANT)
    /// GC_TEST_VIDEO for checking the video's drawing: a local file (an
    /// absolute path) that the Twitch window plays at start.
    Q_PROPERTY(QString testVideo READ testVideo CONSTANT)
    /// The screen the overlay is on, in its own pixels.
    Q_PROPERTY(int screenWidth READ screenWidth NOTIFY screenChanged)
    Q_PROPERTY(int screenHeight READ screenHeight NOTIFY screenChanged)
    /// GC_SCREENSHOT is set: the parts go into one window (`shotScene`, a
    /// screen-sized item) instead of their own, to be grabbed whole.
    Q_PROPERTY(bool screenshotMode READ screenshotMode CONSTANT)
    Q_PROPERTY(QQuickItem *shotScene READ shotScene WRITE setShotScene NOTIFY shotSceneChanged)

public:
    explicit NativeWindow(QObject *parent = nullptr);

    bool layerShell() const { return m_layerShell; }
    QString demo() const { return m_demo; }
    QString testVideo() const { return m_testVideo; }
    int screenWidth() const;
    int screenHeight() const;

    /// Makes a part's window an overlay surface (before it is first shown).
    Q_INVOKABLE void attach(QQuickWindow *window);
    /// Puts a part's window at `area` (screen pixels) and gives it that size.
    Q_INVOKABLE void place(QQuickWindow *window, const QRectF &area);
    /// Where a part's window takes clicks (its own coordinates): `all` for
    /// everywhere, else only `rects` (none: clicks go through to the game).
    Q_INVOKABLE void setInput(QQuickWindow *window, bool all, const QVariantList &rects);
    /// Whether a part may take the keyboard (only while unlocked, and only
    /// when clicked into: the game keeps it otherwise).
    Q_INVOKABLE void setKeyboard(QQuickWindow *window, bool wanted);

    /// For screenshots: every part shown, as on the screen.
    bool screenshot(const QString &file) const;
    bool screenshotMode() const { return m_screenshotMode; }
    QQuickItem *shotScene() const { return m_shotScene; }
    void setShotScene(QQuickItem *scene);

signals:
    void screenChanged();
    void shotSceneChanged();

private:
    QScreen *screen() const;
    bool m_layerShell = false;
    QString m_demo;
    QString m_testVideo;
    bool m_screenshotMode = false;
    QQuickItem *m_shotScene = nullptr;
};

int32_t gc_run();
void gc_quit();
