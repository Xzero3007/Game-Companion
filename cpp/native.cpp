#include "native.h"

#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtGui/QFontDatabase>
#include <QtGui/QGuiApplication>
#include <QtGui/QRegion>
#include <QtGui/QScreen>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>
#include <QtQuick/QQuickWindow>

#ifdef GC_LAYER_SHELL
#include <LayerShellQt/window.h>
#endif

NativeWindow::NativeWindow(QObject *parent)
    : QObject(parent)
    , m_demo(qEnvironmentVariable("GC_DEMO"))
{
}

void NativeWindow::attach(QQuickWindow *window)
{
    m_window = window;
    if (!window) {
        return;
    }
    window->setColor(Qt::transparent);
    QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen();
    if (screen) {
        window->setGeometry(screen->geometry());
    }

#ifdef GC_LAYER_SHELL
    if (QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        // Must happen before the window is shown.
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setLayer(LayerShellQt::Window::LayerOverlay);
            layer->setAnchors(LayerShellQt::Window::Anchors(
                LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
            // Covers the whole screen, panels too, and pushes nothing aside.
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            layer->setScope(QStringLiteral("game-companion"));
            m_layerShell = true;
        }
    }
#endif
    if (!m_layerShell) {
        // X11 or another desktop: a frameless window over the others. Above a
        // fullscreen game only where the desktop allows it.
        window->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool);
    }
    window->show();
    connect(window, &QWindow::visibleChanged, this, &NativeWindow::applyInputRegion);
    QTimer::singleShot(0, this, &NativeWindow::applyInputRegion);
    QTimer::singleShot(500, this, &NativeWindow::applyInputRegion);
}

void NativeWindow::setInputRects(const QVariantList &rects)
{
    QRegion region;
    for (const QVariant &value : rects) {
        const QRect rect = value.toRectF().toAlignedRect();
        if (rect.isValid()) {
            region += rect;
        }
    }
    if (region.isEmpty()) {
        // An empty mask means "the whole window" to Qt: one pixel instead.
        region = QRect(0, 0, 1, 1);
    }
    m_inputRegion = region;
    applyInputRegion();
}

void NativeWindow::applyInputRegion()
{
    if (m_window && m_window->isVisible()) {
        // Reset first: Qt skips a mask equal to the one it holds, even when
        // it could not give that one to the surface yet.
        m_window->setMask(QRegion());
        m_window->setMask(m_inputRegion);
    }
}

void NativeWindow::setKeyboard(bool wanted)
{
#ifdef GC_LAYER_SHELL
    if (m_layerShell && m_window) {
        if (auto *layer = LayerShellQt::Window::get(m_window)) {
            layer->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                   : LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }
#else
    Q_UNUSED(wanted);
#endif
}

int32_t gc_run()
{
    static int argc = 1;
    static char name[] = "game-companion";
    static char *argv[] = {name, nullptr};

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Game Companion"));
    QGuiApplication::setDesktopFileName(QStringLiteral("io.github.xzero3007.GameCompanion"));
    QGuiApplication::setQuitOnLastWindowClosed(true);

    // The fonts ship with the app: nothing is fetched.
    for (const char *font : {":/qt/qml/GameCompanion/assets/fonts/Rajdhani-Bold.ttf", ":/qt/qml/GameCompanion/assets/fonts/Rajdhani-SemiBold.ttf",
                             ":/qt/qml/GameCompanion/assets/fonts/Inter.ttf"}) {
        if (QFontDatabase::addApplicationFont(QString::fromLatin1(font)) < 0) {
            qWarning("game-companion: font %s not loaded", font);
        }
    }

    NativeWindow native;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("nativeWindow"), &native);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/GameCompanion/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window) {
        return 1;
    }
    native.attach(window);

    // For screenshots during development: GC_SCREENSHOT=<file.png>.
    const QString shot = qEnvironmentVariable("GC_SCREENSHOT");
    if (!shot.isEmpty()) {
        QTimer::singleShot(1500, window, [window, shot]() {
            window->grabWindow().save(shot);
            QGuiApplication::quit();
        });
    }
    return app.exec();
}
