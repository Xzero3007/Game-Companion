#include "native.h"
#include "mpvvideo.h"

#include <QtCore/QMetaObject>
#include <QtCore/QMargins>

#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtGui/QFontDatabase>
#include <QtGui/QGuiApplication>
#include <QtGui/QSurfaceFormat>
#include <QtGui/QRegion>
#include <QtGui/QScreen>
#include <QtQml/QQmlApplicationEngine>

#include "icons.h"
#include "jellyfinpictures.h"
#include <QtQml/QQmlContext>
#include <QtQml/QQmlNetworkAccessManagerFactory>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QSGRendererInterface>

#ifdef GC_LAYER_SHELL
#include <LayerShellQt/window.h>
#endif

NativeWindow::NativeWindow(QObject *parent)
    : QObject(parent)
    , m_demo(qEnvironmentVariable("GC_DEMO"))
    , m_screenshotMode(!qEnvironmentVariableIsEmpty("GC_SCREENSHOT"))
{
    // A local file only: never an address.
    const QString file = qEnvironmentVariable("GC_TEST_VIDEO");
    if (file.startsWith(QLatin1Char('/'))) {
        m_testVideo = file;
    }
#ifdef GC_LAYER_SHELL
    m_layerShell = QGuiApplication::platformName().startsWith(QLatin1String("wayland"));
#endif
    if (QScreen *s = screen()) {
        connect(s, &QScreen::geometryChanged, this, &NativeWindow::screenChanged);
    }
}

QScreen *NativeWindow::screen() const
{
    return QGuiApplication::primaryScreen();
}

int NativeWindow::screenWidth() const
{
    return screen() ? screen()->geometry().width() : 1280;
}

int NativeWindow::screenHeight() const
{
    return screen() ? screen()->geometry().height() : 720;
}

void NativeWindow::attach(QQuickWindow *window)
{
    if (!window) {
        return;
    }
    window->setColor(Qt::transparent);
    QSurfaceFormat format = window->format();
    format.setAlphaBufferSize(8);
    window->setFormat(format);
    if (QScreen *s = screen()) {
        window->setScreen(s);
    }
#ifdef GC_LAYER_SHELL
    if (m_layerShell) {
        // Must happen before the window is shown.
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setLayer(LayerShellQt::Window::LayerOverlay);
            // Placed from the top left corner by margins: KWin puts it there.
            layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorLeft));
            // Measured from the screen's edge, not pushed aside by panels.
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            layer->setScope(QStringLiteral("game-companion"));
            return;
        }
    }
#endif
    // X11 or another desktop: frameless windows over the others. Above a
    // fullscreen game only where the desktop allows it.
    window->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool | Qt::WindowDoesNotAcceptFocus);
}

void NativeWindow::place(QQuickWindow *window, const QRectF &area)
{
    if (!window) {
        return;
    }
    const QRect r = area.toAlignedRect();
    const QSize size(qMax(1, r.width()), qMax(1, r.height()));
    window->setProperty("gcArea", QRect(r.topLeft(), size));
#ifdef GC_LAYER_SHELL
    if (m_layerShell) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setMargins(QMargins(r.x(), r.y(), 0, 0));
            if (window->size() != size) {
                window->resize(size);
            }
            window->requestUpdate();
            return;
        }
    }
#endif
    window->setGeometry(QRect(r.topLeft(), size));
}

void NativeWindow::setInput(QQuickWindow *window, bool all, const QVariantList &rects)
{
    if (!window) {
        return;
    }
    QRegion region;
    if (!all) {
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
    }
    // Reset first: Qt skips a mask equal to the one it holds, even when it
    // could not give that one to the surface yet.
    window->setMask(QRegion());
    if (!all) {
        window->setMask(region);
    }
    window->setProperty("gcMask", region);
}

void NativeWindow::setKeyboard(QQuickWindow *window, bool wanted)
{
#ifdef GC_LAYER_SHELL
    if (m_layerShell && window) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                   : LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }
#else
    Q_UNUSED(window);
    Q_UNUSED(wanted);
#endif
}

bool NativeWindow::screenshot(const QString &file) const
{
    // In screenshot mode every part sits in one window (Main's shotWindow),
    // as on the screen: grabbed whole.
    auto *window = m_shotScene ? m_shotScene->window() : nullptr;
    return window && window->grabWindow().save(file);
}

void NativeWindow::setShotScene(QQuickItem *scene)
{
    if (m_shotScene != scene) {
        m_shotScene = scene;
        emit shotSceneChanged();
    }
}

namespace {

// QML loads pictures from these hosts only (Twitch's and YouTube's
// thumbnails, the streams module's allowed hosts); any other address,
// and anything but https, is refused before a connection is made.
class PictureNetwork : public QNetworkAccessManager
{
public:
    using QNetworkAccessManager::QNetworkAccessManager;

    static bool allowed(const QUrl &url)
    {
        static const QStringList hosts = {QStringLiteral("static-cdn.jtvnw.net"), QStringLiteral("i.ytimg.com"),
                                          QStringLiteral("yt3.ggpht.com")};
        return url.scheme() == QLatin1String("https") && url.userInfo().isEmpty() && url.port(443) == 443
            && hosts.contains(url.host().toLower());
    }

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *data) override
    {
        if (op == GetOperation && allowed(request.url())) {
            QNetworkRequest r(request);
            // No redirects: they would go elsewhere unchecked.
            r.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
            return QNetworkAccessManager::createRequest(op, r, data);
        }
        // An address no request goes to: the picture stays empty.
        QNetworkRequest refused(QUrl(QStringLiteral("refused:")));
        return QNetworkAccessManager::createRequest(GetOperation, refused, nullptr);
    }
};

class PictureNetworkFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        return new PictureNetwork(parent);
    }
};

} // namespace

int32_t gc_run()
{
    static int argc = 1;
    static char name[] = "game-companion";
    static char *argv[] = {name, nullptr};

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Game Companion"));
    QGuiApplication::setDesktopFileName(QStringLiteral("io.github.xzero3007.GameCompanion"));

    // The fonts ship with the app: nothing is fetched.
    for (const char *font : {":/qt/qml/GameCompanion/assets/fonts/Rajdhani-Bold.ttf", ":/qt/qml/GameCompanion/assets/fonts/Rajdhani-SemiBold.ttf",
                             ":/qt/qml/GameCompanion/assets/fonts/Inter.ttf"}) {
        if (QFontDatabase::addApplicationFont(QString::fromLatin1(font)) < 0) {
            qWarning("game-companion: font %s not loaded", font);
        }
    }

    // Videos draw through OpenGL (libmpv); screenshots may ask for software.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")) {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    }
    gc_register_video();
    // The parts' windows are see-through where nothing is drawn.
    QQuickWindow::setDefaultAlphaBuffer(true);

    NativeWindow native;
    QQmlApplicationEngine engine;
    PictureNetworkFactory pictures;
    engine.setNetworkAccessManagerFactory(&pictures);
    gc_register_icons(&engine);
    gc_register_jellyfin_pictures(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("nativeWindow"), &native);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/GameCompanion/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    // The parts' windows: when the last one closes, so does the app (none
    // is closed by the user; Settings' "Turn off" quits).
    QGuiApplication::setQuitOnLastWindowClosed(false);

    // For screenshots during development: GC_SCREENSHOT=<file.png>.
    const QString shot = qEnvironmentVariable("GC_SCREENSHOT");
    if (!shot.isEmpty()) {
        // GC_SCREENSHOT_DELAY: milliseconds before it is taken (1500).
        const int delay = qEnvironmentVariableIntValue("GC_SCREENSHOT_DELAY") > 0 ? qEnvironmentVariableIntValue("GC_SCREENSHOT_DELAY") : 1500;
        QTimer::singleShot(delay, &app, [&native, shot]() {
            native.screenshot(shot);
            QGuiApplication::quit();
        });
    }
    return app.exec();
}

void gc_quit()
{
    QMetaObject::invokeMethod(qApp, &QCoreApplication::quit, Qt::QueuedConnection);
}
