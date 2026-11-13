#include "mpvvideo.h"

#include <QtCore/QByteArray>
#include <QtCore/QMetaObject>
#include <QtGui/QOpenGLContext>
#include <QtOpenGL/QOpenGLFramebufferObject>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QQuickOpenGLUtils>
#include <QtQuick/QSGRendererInterface>
#include <QtCore/QPointer>

#include <clocale>
#include <dlfcn.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>

namespace {

// libmpv, loaded once at run time: the app does not need it to start.
struct Mpv
{
    decltype(&mpv_create) create = nullptr;
    decltype(&mpv_initialize) initialize = nullptr;
    decltype(&mpv_terminate_destroy) terminate_destroy = nullptr;
    decltype(&mpv_set_option_string) set_option_string = nullptr;
    decltype(&mpv_set_property_string) set_property_string = nullptr;
    decltype(&mpv_command) command = nullptr;
    decltype(&mpv_observe_property) observe_property = nullptr;
    decltype(&mpv_wait_event) wait_event = nullptr;
    decltype(&mpv_set_wakeup_callback) set_wakeup_callback = nullptr;
    decltype(&mpv_error_string) error_string = nullptr;
    decltype(&mpv_request_log_messages) request_log_messages = nullptr;
    decltype(&mpv_render_context_create) render_create = nullptr;
    decltype(&mpv_render_context_free) render_free = nullptr;
    decltype(&mpv_render_context_render) render_render = nullptr;
    decltype(&mpv_render_context_set_update_callback) render_set_update_callback = nullptr;
    decltype(&mpv_render_context_update) render_update = nullptr;
    bool ok = false;
};

const Mpv &mpv()
{
    static const Mpv lib = [] {
        Mpv m;
        void *h = dlopen("libmpv.so.2", RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            h = dlopen("libmpv.so", RTLD_NOW | RTLD_LOCAL);
        }
        if (!h) {
            return m;
        }
#define GC_SYM(field, name) m.field = reinterpret_cast<decltype(m.field)>(dlsym(h, name))
        GC_SYM(create, "mpv_create");
        GC_SYM(initialize, "mpv_initialize");
        GC_SYM(terminate_destroy, "mpv_terminate_destroy");
        GC_SYM(set_option_string, "mpv_set_option_string");
        GC_SYM(set_property_string, "mpv_set_property_string");
        GC_SYM(command, "mpv_command");
        GC_SYM(observe_property, "mpv_observe_property");
        GC_SYM(wait_event, "mpv_wait_event");
        GC_SYM(set_wakeup_callback, "mpv_set_wakeup_callback");
        GC_SYM(error_string, "mpv_error_string");
        GC_SYM(request_log_messages, "mpv_request_log_messages");
        GC_SYM(render_create, "mpv_render_context_create");
        GC_SYM(render_free, "mpv_render_context_free");
        GC_SYM(render_render, "mpv_render_context_render");
        GC_SYM(render_set_update_callback, "mpv_render_context_set_update_callback");
        GC_SYM(render_update, "mpv_render_context_update");
#undef GC_SYM
        m.ok = m.create && m.initialize && m.terminate_destroy && m.set_option_string && m.set_property_string
            && m.command && m.observe_property && m.wait_event && m.set_wakeup_callback && m.error_string
            && m.render_create && m.render_free && m.render_render && m.render_set_update_callback;
        return m;
    }();
    return lib;
}

} // namespace

struct MpvCore
{
    mpv_handle *handle = nullptr;
    /// Gone once the item is: no more redraws are asked of it.
    QPointer<MpvVideo> item;
    ~MpvCore()
    {
        if (handle) {
            mpv().terminate_destroy(handle);
        }
    }
};

namespace {

void *getProcAddress(void *, const char *name)
{
    QOpenGLContext *ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void *>(ctx->getProcAddress(QByteArray(name))) : nullptr;
}

// Draws the item's mpv into the frame buffer Qt Quick gives it.
class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(MpvVideo *item)
        : m_core(item->core())
    {
    }

    ~MpvRenderer() override
    {
        if (m_render) {
            mpv().render_free(m_render);
        }
        // Then m_core lets mpv go, if the item is gone too.
    }

    // The GUI thread waits meanwhile: the item may be read.
    void synchronize(QQuickFramebufferObject *item) override
    {
        auto core = static_cast<MpvVideo *>(item)->core();
        if (core && core != m_core && !m_render) {
            // mpv started after this renderer: a new frame buffer makes the context.
            m_core = core;
            invalidateFramebufferObject();
        }
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        // Made here, on the render thread, with Qt's GL context current.
        if (!m_render && m_core && m_core->handle && mpv().ok) {
            mpv_opengl_init_params gl{getProcAddress, nullptr};
            const char *api = MPV_RENDER_API_TYPE_OPENGL;
            mpv_render_param params[] = {
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(api)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl},
                {MPV_RENDER_PARAM_INVALID, nullptr},
            };
            if (mpv().render_create(&m_render, m_core->handle, params) >= 0) {
                mpv().render_set_update_callback(m_render, &MpvRenderer::onUpdate, m_core.get());
                // Now mpv can show a video: what waited for it plays.
                QPointer<MpvVideo> item = m_core->item;
                if (item) {
                    QMetaObject::invokeMethod(item.data(), "renderReady", Qt::QueuedConnection);
                }
            } else {
                m_render = nullptr;
            }
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (!m_render) {
            return;
        }
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo target{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &target},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv().render_render(m_render, params);
        QQuickOpenGLUtils::resetOpenGLState();
    }

private:
    static void onUpdate(void *ctx)
    {
        // mpv's thread: draw again on Qt's.
        auto *core = static_cast<MpvCore *>(ctx);
        QPointer<MpvVideo> item = core->item;
        if (item) {
            QMetaObject::invokeMethod(item.data(), [item] { if (item) item->update(); }, Qt::QueuedConnection);
        }
    }

    std::shared_ptr<MpvCore> m_core;
    mpv_render_context *m_render = nullptr;
};

// What helps with what yt-dlp says, where that is known.
QString hintFor(const QString &why)
{
    if (why.contains(QLatin1String("JavaScript"), Qt::CaseInsensitive) || why.contains(QLatin1String("challenge"), Qt::CaseInsensitive)
        || why.contains(QLatin1String("deno"), Qt::CaseInsensitive)) {
        return QStringLiteral(" · yt-dlp needs a JavaScript runtime: sudo pacman -S deno");
    }
    if (why.contains(QLatin1String("Sign in to confirm"), Qt::CaseInsensitive) || why.contains(QLatin1String("Requested format"), Qt::CaseInsensitive)
        || why.contains(QLatin1String("403"))) {
        return QStringLiteral(" · an up-to-date yt-dlp often helps: sudo pacman -Syu yt-dlp");
    }
    if (why.isEmpty()) {
        return QStringLiteral(" · is yt-dlp installed and up to date? (sudo pacman -Syu yt-dlp)");
    }
    return QString();
}

void onWakeup(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvVideo *>(ctx), "readEvents", Qt::QueuedConnection);
}

} // namespace

MpvVideo::MpvVideo(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
{
    // mpv draws top row first into the frame buffer (FLIP_Y 0), and Qt
    // shows the texture as it is: no mirroring, else the video stands on
    // its head (checked with a test video whose top is marked, GC_TEST_VIDEO).
    setMirrorVertically(false);
}

MpvVideo::~MpvVideo()
{
    if (m_mpv) {
        mpv().set_wakeup_callback(m_mpv, nullptr, nullptr);
        // Quiet at once; mpv itself ends with the renderer's render context.
        const char *args[] = {"stop", nullptr};
        mpv().command(m_mpv, args);
        m_mpv = nullptr;
    }
    m_core.reset();
}

QQuickFramebufferObject::Renderer *MpvVideo::createRenderer() const
{
    return new MpvRenderer(const_cast<MpvVideo *>(this));
}

bool MpvVideo::drawable() const
{
    // What the window really draws with (it falls back to software when
    // OpenGL can't start), else what the app asked for.
    QSGRendererInterface::GraphicsApi api = QQuickWindow::graphicsApi();
    if (window() && window()->rendererInterface()) {
        api = window()->rendererInterface()->graphicsApi();
    }
    return api == QSGRendererInterface::OpenGL;
}

bool MpvVideo::ensureStarted()
{
    if (m_mpv) {
        return true;
    }
    if (!mpv().ok) {
        setState(QStringLiteral("failed"), QStringLiteral("mpv is not installed (sudo pacman -S mpv)"));
        return false;
    }
    // libmpv wants C's number format.
    std::setlocale(LC_NUMERIC, "C");
    m_mpv = mpv().create();
    if (!m_mpv) {
        setState(QStringLiteral("failed"), QStringLiteral("mpv could not start"));
        return false;
    }
    const char *options[][2] = {
        {"config", "no"},
        {"terminal", "no"},
        {"vo", "libmpv"},
        {"input-default-bindings", "no"},
        {"input-vo-keyboard", "no"},
        {"osc", "no"},
        {"idle", "yes"},
        {"keep-open", "no"},
        {"ytdl", "yes"},
        {"cache", "yes"},
        {"demuxer-max-bytes", "64MiB"},
        // What played stays a while: jumping back needs no new download.
        {"demuxer-max-back-bytes", "48MiB"},
        {"force-seekable", "yes"},
        {"load-unsafe-playlists", "no"},
        {"audio-client-name", "Game Companion"},
        {"title", "Game Companion"},
    };
    for (const auto &o : options) {
        mpv().set_option_string(m_mpv, o[0], o[1]);
    }
    mpv().set_option_string(m_mpv, "hwdec", m_hwdec ? "auto-safe" : "no");
    if (m_local) {
        // The home network's server: mpv itself, nothing else. No yt-dlp
        // (it would try an address mpv can't open), no scripts of the
        // user's, and ffmpeg ignores http_proxy (stream-lavf-o, per video).
        mpv().set_option_string(m_mpv, "ytdl", "no");
        mpv().set_option_string(m_mpv, "load-scripts", "no");
    }
    if (!drawable()) {
        // No OpenGL here: the sound alone.
        mpv().set_option_string(m_mpv, "vo", "null");
    }
    mpv().set_option_string(m_mpv, "volume", QByteArray::number(m_volume, 'f', 0).constData());
    if (mpv().initialize(m_mpv) < 0) {
        mpv().terminate_destroy(m_mpv);
        m_mpv = nullptr;
        setState(QStringLiteral("failed"), QStringLiteral("mpv could not start"));
        return false;
    }
    // mpv's warnings and errors (yt-dlp's among them, through mpv's ytdl
    // hook): a video that doesn't play says why (as the meter's patch 0057).
    if (mpv().request_log_messages) {
        mpv().request_log_messages(m_mpv, "warn");
    }
    mpv().observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv().observe_property(m_mpv, 0, "mute", MPV_FORMAT_FLAG);
    mpv().observe_property(m_mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv().observe_property(m_mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv().observe_property(m_mpv, 0, "media-title", MPV_FORMAT_STRING);
    mpv().observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv().observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv().observe_property(m_mpv, 0, "chapter-list", MPV_FORMAT_NODE);
    mpv().observe_property(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv().set_wakeup_callback(m_mpv, onWakeup, this);
    m_core = std::make_shared<MpvCore>();
    m_core->handle = m_mpv;
    m_core->item = this;
    // A renderer made before mpv existed: a new frame buffer makes the context.
    update();
    return true;
}

void MpvVideo::setState(const QString &state, const QString &error)
{
    if (m_state == state && m_error == error) {
        return;
    }
    m_state = state;
    m_error = error;
    emit stateChanged();
}

void MpvVideo::setMpv(const char *name, const QString &value)
{
    if (m_mpv) {
        mpv().set_property_string(m_mpv, name, value.toUtf8().constData());
    }
}

bool MpvVideo::play(const QString &url, const QString &format, double start, const QString &header)
{
    if (!ensureStarted()) {
        return false;
    }
    m_pending = Pending{url, format, start, header};
    setState(QStringLiteral("loading"));
    if (m_rendering || !drawable()) {
        return loadPending();
    }
    // mpv needs its render context first: made when Qt next draws this.
    update();
    return true;
}

void MpvVideo::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickFramebufferObject::itemChange(change, value);
    if (change == ItemSceneChange && value.window) {
        update();
    }
}

void MpvVideo::renderReady()
{
    m_rendering = true;
    loadPending();
}

bool MpvVideo::loadPending()
{
    if (!m_mpv || m_pending.url.isEmpty()) {
        return false;
    }
    const Pending p = m_pending;
    m_pending = Pending{};
    const QString &url = p.url;
    const QString &format = p.format;
    const double start = p.start;
    setMpv("ytdl-format", format.isEmpty() ? QStringLiteral("bestvideo[height<=?1080]+bestaudio/best") : format);
    // YouTube hands out a stream's address a few seconds before it serves
    // it: mpv asked at once, got 403 and played nothing. ffmpeg connects
    // again, for YouTube alone (on Twitch's live segments it stalled the
    // picture), as the meter's patch 0058.
    const bool youtube = url.startsWith(QLatin1String("https://www.youtube.com/"));
    // The home network's server: straight there, never through a proxy
    // (an empty http_proxy wins over the environment's).
    setMpv("stream-lavf-o", m_local ? QStringLiteral("http_proxy=")
                           : youtube ? QStringLiteral("reconnect=1,reconnect_on_http_error=4xx,reconnect_delay_max=10")
                                     : QString());
    // Each video's own header: emptied with "clr" (a plain set to "" leaves
    // one empty field), then the one field added whole, commas and all.
    {
        const char *clr[] = {"change-list", "http-header-fields", "clr", "", nullptr};
        mpv().command(m_mpv, clr);
        if (!p.header.isEmpty()) {
            const QByteArray h = p.header.toUtf8();
            const char *add[] = {"change-list", "http-header-fields", "append", h.constData(), nullptr};
            mpv().command(m_mpv, add);
        }
    }
    setMpv("start", start > 0 ? QString::number(start, 'f', 1) : QStringLiteral("none"));
    setMpv("pause", QStringLiteral("no"));
    const QByteArray u = url.toUtf8();
    const char *args[] = {"loadfile", u.constData(), "replace", nullptr};
    const int code = mpv().command(m_mpv, args);
    if (code < 0) {
        setState(QStringLiteral("failed"), QString::fromUtf8(mpv().error_string(code)));
        return false;
    }
    m_position = 0;
    m_duration = 0;
    emit positionChanged();
    emit durationChanged();
    return true;
}

void MpvVideo::stop()
{
    m_pending = Pending{};
    if (m_mpv) {
        const char *args[] = {"stop", nullptr};
        mpv().command(m_mpv, args);
    }
    setState(QStringLiteral("idle"));
}

void MpvVideo::seek(double seconds, bool relative)
{
    if (!m_mpv) {
        return;
    }
    const QByteArray s = QByteArray::number(seconds, 'f', 1);
    const char *args[] = {"seek", s.constData(), relative ? "relative" : "absolute", nullptr};
    mpv().command(m_mpv, args);
}

void MpvVideo::setHwdec(bool on)
{
    if (m_hwdec == on) {
        return;
    }
    m_hwdec = on;
    setMpv("hwdec", on ? QStringLiteral("auto-safe") : QStringLiteral("no"));
    emit hwdecChanged();
}

void MpvVideo::setLocal(bool on)
{
    // Only before mpv starts: its options are set once.
    if (m_local == on || m_mpv) {
        return;
    }
    m_local = on;
    emit localChanged();
}

void MpvVideo::setTrack(const QString &kind, int id)
{
    const char *name = kind == QLatin1String("audio") ? "aid" : "sid";
    setMpv(name, id > 0 ? QString::number(id) : QStringLiteral("no"));
}

void MpvVideo::addSubtitle(const QString &url)
{
    if (!m_mpv || url.isEmpty()) {
        return;
    }
    const QByteArray u = url.toUtf8();
    const char *args[] = {"sub-add", u.constData(), "select", nullptr};
    mpv().command(m_mpv, args);
}

void MpvVideo::setSpeed(double speed)
{
    if (!(speed >= 0.25 && speed <= 4)) {
        return;
    }
    m_speed = speed;
    setMpv("speed", QString::number(speed, 'f', 2));
    emit speedChanged();
}

void MpvVideo::setPaused(bool paused)
{
    setMpv("pause", paused ? QStringLiteral("yes") : QStringLiteral("no"));
    if (!m_mpv && m_paused != paused) {
        m_paused = paused;
        emit pausedChanged();
    }
}

void MpvVideo::setMuted(bool muted)
{
    setMpv("mute", muted ? QStringLiteral("yes") : QStringLiteral("no"));
    if (!m_mpv && m_muted != muted) {
        m_muted = muted;
        emit mutedChanged();
    }
}

void MpvVideo::setVolume(double volume)
{
    volume = qBound(0.0, volume, 125.0);
    setMpv("volume", QString::number(volume, 'f', 0));
    if (!m_mpv && !qFuzzyCompare(m_volume, volume)) {
        m_volume = volume;
        emit volumeChanged();
    }
}

void MpvVideo::readEvents()
{
    while (m_mpv) {
        mpv_event *ev = mpv().wait_event(m_mpv, 0);
        if (!ev || ev->event_id == MPV_EVENT_NONE) {
            break;
        }
        switch (ev->event_id) {
        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(ev->data);
            if (!msg || !msg->text) {
                break;
            }
            const QString line = QString::fromUtf8(msg->text).trimmed();
            if (line.isEmpty()) {
                break;
            }
            const bool fromYtdl = msg->prefix && QByteArray(msg->prefix).contains("ytdl");
            // yt-dlp's ERROR line wins (its "youtube-dl failed" after it says
            // less), then any of its lines, then mpv's own.
            const bool hadError = m_why.contains(QLatin1String("ERROR:"));
            const bool isError = line.contains(QLatin1String("ERROR:"));
            if (isError || (!hadError && (fromYtdl || !m_why.startsWith(QLatin1String("yt-dlp"))))) {
                QString text = line.section(QStringLiteral("; please report this issue"), 0, 0).trimmed();
                m_why = (fromYtdl ? QStringLiteral("yt-dlp: ") + text : text).left(240);
            }
            break;
        }
        case MPV_EVENT_START_FILE:
            m_why.clear();
            setState(QStringLiteral("loading"));
            break;
        case MPV_EVENT_FILE_LOADED:
        case MPV_EVENT_PLAYBACK_RESTART:
            setState(QStringLiteral("playing"));
            break;
        case MPV_EVENT_END_FILE: {
            auto *end = static_cast<mpv_event_end_file *>(ev->data);
            if (end && end->reason == MPV_END_FILE_REASON_ERROR) {
                QString why = QString::fromUtf8(mpv().error_string(end->error));
                if (!m_why.isEmpty()) {
                    why += QStringLiteral(" (") + m_why + QStringLiteral(")");
                }
                setState(QStringLiteral("failed"), why + (m_local ? QString() : hintFor(m_why)));
            } else if (end && end->reason == MPV_END_FILE_REASON_EOF) {
                setState(QStringLiteral("ended"));
                emit ended();
            }
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *p = static_cast<mpv_event_property *>(ev->data);
            if (!p || !p->data) {
                if (p && qstrcmp(p->name, "duration") == 0 && m_duration != 0) {
                    m_duration = 0;
                    emit durationChanged();
                }
                break;
            }
            const QByteArray name(p->name);
            if (p->format == MPV_FORMAT_FLAG) {
                const bool v = *static_cast<int *>(p->data) != 0;
                if (name == "pause" && v != m_paused) {
                    m_paused = v;
                    emit pausedChanged();
                } else if (name == "mute" && v != m_muted) {
                    m_muted = v;
                    emit mutedChanged();
                } else if (name == "paused-for-cache" && (m_state == QLatin1String("playing") || m_state == QLatin1String("buffering"))) {
                    setState(v ? QStringLiteral("buffering") : QStringLiteral("playing"));
                }
            } else if (p->format == MPV_FORMAT_DOUBLE) {
                const double v = *static_cast<double *>(p->data);
                if (name == "volume" && !qFuzzyCompare(v, m_volume)) {
                    m_volume = v;
                    emit volumeChanged();
                } else if (name == "time-pos") {
                    m_position = v;
                    emit positionChanged();
                } else if (name == "duration") {
                    m_duration = v;
                    emit durationChanged();
                } else if (name == "speed" && !qFuzzyCompare(v, m_speed)) {
                    m_speed = v;
                    emit speedChanged();
                }
            } else if (p->format == MPV_FORMAT_NODE && name == "chapter-list") {
                // [{title, time}], read out of mpv's own list.
                QVariantList list;
                const auto *node = static_cast<mpv_node *>(p->data);
                if (node->format == MPV_FORMAT_NODE_ARRAY && node->u.list) {
                    for (int i = 0; i < node->u.list->num; ++i) {
                        const mpv_node &entry = node->u.list->values[i];
                        if (entry.format != MPV_FORMAT_NODE_MAP || !entry.u.list) {
                            continue;
                        }
                        QVariantMap chapter;
                        for (int k = 0; k < entry.u.list->num; ++k) {
                            const char *key = entry.u.list->keys ? entry.u.list->keys[k] : nullptr;
                            const mpv_node &value = entry.u.list->values[k];
                            if (!key) {
                                continue;
                            }
                            if (qstrcmp(key, "title") == 0 && value.format == MPV_FORMAT_STRING) {
                                chapter.insert(QStringLiteral("title"), QString::fromUtf8(value.u.string));
                            } else if (qstrcmp(key, "time") == 0 && value.format == MPV_FORMAT_DOUBLE) {
                                chapter.insert(QStringLiteral("time"), value.u.double_);
                            }
                        }
                        if (chapter.contains(QStringLiteral("time"))) {
                            list.append(chapter);
                        }
                    }
                }
                m_chapters = list;
                emit chaptersChanged();
            } else if (p->format == MPV_FORMAT_STRING && name == "media-title") {
                m_title = QString::fromUtf8(*static_cast<char **>(p->data));
                emit titleChanged();
            }
            break;
        }
        case MPV_EVENT_SHUTDOWN:
            return;
        default:
            break;
        }
    }
}

void gc_register_video()
{
    qmlRegisterType<MpvVideo>("GameCompanion.Video", 1, 0, "MpvVideo");
}
