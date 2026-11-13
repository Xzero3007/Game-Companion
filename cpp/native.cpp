#include "native.h"
#include "mpvvideo.h"
#include "twitchchat.h"

#include <QtCore/QMetaObject>
#include <QtCore/QMargins>

#include <climits>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSet>
#include <QtCore/QStandardPaths>
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

extern "C" {
// src/native.rs: what the Rust side tidies when the app ends.
void gc_about_to_quit();
}

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
    // The screen the user picked (settings.json "screen"), read only: the
    // Rust side owns the file and writes it.
    QFile settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/game-companion/settings.json"));
    if (settings.open(QIODevice::ReadOnly)) {
        m_preferred = QJsonDocument::fromJson(settings.read(4 << 20)).object().value(QStringLiteral("screen")).toString();
    }
    connect(qGuiApp, &QGuiApplication::screenAdded, this, &NativeWindow::screensChanged);
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, &NativeWindow::screensChanged);
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &NativeWindow::screensChanged);
    screensChanged();
}

// Screens came or went: KDE's primary screen again, and the one to watch.
void NativeWindow::screensChanged()
{
    m_kdePrimary = kdePrimary();
    QScreen *s = screen();
    if (s != m_watched) {
        if (m_watched) {
            disconnect(m_watched, &QScreen::geometryChanged, this, &NativeWindow::screenChanged);
        }
        m_watched = s;
        if (s) {
            connect(s, &QScreen::geometryChanged, this, &NativeWindow::screenChanged);
        }
    }
    emit screenChanged();
}

// Qt's primary screen on KWin is the first output KWin announced, not the
// one KDE calls primary (checked on KWin 6.8): with two monitors the parts
// landed on the wrong one. KWin keeps its choice in kwinoutputconfig.json:
// "outputs" (each with its connectorName) and "setups" (for each set of
// connected outputs: outputIndex, enabled, priority; 1 = primary).
QString NativeWindow::kdePrimary() const
{
    QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwinoutputconfig.json"));
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }
    QSet<QString> connected;
    for (QScreen *s : QGuiApplication::screens()) {
        connected.insert(s->name());
    }
    QJsonArray outputs;
    QJsonArray setups;
    for (const QJsonValue &part : QJsonDocument::fromJson(file.read(4 << 20)).array()) {
        const QJsonObject o = part.toObject();
        if (o.value(QStringLiteral("name")).toString() == QLatin1String("outputs")) {
            outputs = o.value(QStringLiteral("data")).toArray();
        } else if (o.value(QStringLiteral("name")).toString() == QLatin1String("setups")) {
            setups = o.value(QStringLiteral("data")).toArray();
        }
    }
    // The setup for exactly the connected outputs; its enabled output with
    // the lowest priority.
    for (const QJsonValue &setupValue : setups) {
        const QJsonArray list = setupValue.toObject().value(QStringLiteral("outputs")).toArray();
        QSet<QString> names;
        QString best;
        int bestPriority = INT_MAX;
        for (const QJsonValue &entryValue : list) {
            const QJsonObject entry = entryValue.toObject();
            const int index = entry.value(QStringLiteral("outputIndex")).toInt(-1);
            if (index < 0 || index >= outputs.size()) {
                continue;
            }
            const QString name = outputs.at(index).toObject().value(QStringLiteral("connectorName")).toString();
            if (name.isEmpty()) {
                continue;
            }
            const bool enabled = entry.value(QStringLiteral("enabled")).toBool(true);
            if (enabled) {
                names.insert(name);
            }
            const int priority = entry.value(QStringLiteral("priority")).toInt(INT_MAX);
            if (enabled && priority < bestPriority) {
                bestPriority = priority;
                best = name;
            }
        }
        if (!best.isEmpty() && names == connected) {
            return best;
        }
    }
    return QString();
}

QScreen *NativeWindow::screen() const
{
    const auto named = [](const QString &name) -> QScreen * {
        if (name.isEmpty()) {
            return nullptr;
        }
        for (QScreen *s : QGuiApplication::screens()) {
            if (s->name() == name) {
                return s;
            }
        }
        return nullptr;
    };
    // GC_SCREEN=<name> for checks; then the user's choice; then KDE's
    // primary screen; then Qt's.
    if (QScreen *s = named(qEnvironmentVariable("GC_SCREEN"))) {
        return s;
    }
    if (QScreen *s = named(m_preferred)) {
        return s;
    }
    if (QScreen *s = named(m_kdePrimary)) {
        return s;
    }
    return QGuiApplication::primaryScreen();
}

QString NativeWindow::screenName() const
{
    return screen() ? screen()->name() : QString();
}

QString NativeWindow::screenList() const
{
    QJsonArray list;
    for (QScreen *s : QGuiApplication::screens()) {
        const QString model = s->model().isEmpty() ? s->manufacturer() : s->model();
        QString label = s->name();
        if (!model.isEmpty()) {
            label += QStringLiteral(" · ") + model;
        }
        label += QStringLiteral(" · %1×%2").arg(s->geometry().width()).arg(s->geometry().height());
        if (s->name() == m_kdePrimary) {
            label += QStringLiteral(" (primary)");
        }
        list.append(QJsonObject{{QStringLiteral("id"), s->name()}, {QStringLiteral("name"), label}});
    }
    return QString::fromUtf8(QJsonDocument(list).toJson(QJsonDocument::Compact));
}

void NativeWindow::setPreferredScreen(const QString &name)
{
    if (name == m_preferred) {
        return;
    }
    m_preferred = name;
    screensChanged();
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
    // Every part lives on the main screen (where the game runs). Qt picks a
    // window's screen from its position, and layer-shell-qt takes the output
    // from the window's screen: a window left at 0,0 would land on whichever
    // screen sits there (the person's second monitor).
    QScreen *s = screen();
    const QPoint origin = s ? s->geometry().topLeft() : QPoint();
    const bool moved = s && window->screen() != s;
#ifdef GC_LAYER_SHELL
    if (m_layerShell) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            // A layer surface's output is fixed when it is made: to change
            // screens the window is hidden (its surface goes) and shown
            // again on the new screen (found on Sway by the Arch test).
            const bool remake = moved && window->isVisible();
            if (remake) {
                window->hide();
            }
            if (moved) {
                window->setScreen(s);
            }
            layer->setMargins(QMargins(r.x(), r.y(), 0, 0));
            window->setGeometry(QRect(origin + r.topLeft(), size));
            if (remake) {
                window->show();
            }
            window->requestUpdate();
            return;
        }
    }
#endif
    if (moved) {
        window->setScreen(s);
    }
    window->setGeometry(QRect(origin + r.topLeft(), size));
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
    // GC_DEBUG_INPUT=1: every input region given, for click problems on
    // the person's desktop (which part, its place, what takes clicks).
    static const bool debug = qEnvironmentVariableIsSet("GC_DEBUG_INPUT");
    if (debug) {
        qInfo().noquote() << "input" << window->objectName() << "area" << window->property("gcArea").toRect()
                          << "size" << window->size() << (all ? "all" : "only") << region.boundingRect()
                          << "rects" << region.rectCount();
    }
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
        // Chat emotes: Twitch's own (static-cdn), 7TV's and BTTV's.
        static const QStringList hosts = {QStringLiteral("static-cdn.jtvnw.net"), QStringLiteral("i.ytimg.com"),
                                          QStringLiteral("yt3.ggpht.com"), QStringLiteral("cdn.7tv.app"),
                                          QStringLiteral("cdn.betterttv.net")};
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
    gc_register_chat();
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

    // For checks during development: GC_DEBUG_SCREENS=1 prints, after a
    // second, each part's window, its screen and its place.
    if (!qEnvironmentVariableIsEmpty("GC_DEBUG_SCREENS")) {
        QTimer::singleShot(1500, &app, []() {
            for (QWindow *w : QGuiApplication::allWindows()) {
                if (w->isVisible()) {
                    const QRect g = w->geometry();
                    qWarning("window %s on %s at %d,%d %dx%d", qPrintable(w->title()), w->screen() ? qPrintable(w->screen()->name()) : "none",
                             g.x(), g.y(), g.width(), g.height());
                }
            }
        });
    }

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
    // The single-instance socket file goes when the app quits normally.
    QObject::connect(&app, &QCoreApplication::aboutToQuit, []() { gc_about_to_quit(); });
    return app.exec();
}

void gc_quit()
{
    QMetaObject::invokeMethod(qApp, &QCoreApplication::quit, Qt::QueuedConnection);
}
