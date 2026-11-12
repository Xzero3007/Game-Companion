// A video in the overlay: the user's libmpv (loaded when the first video
// starts, so the app runs without it) plays a stream and draws each frame
// into this Qt Quick item through OpenGL. Exposed to QML as `MpvVideo`
// (import GameCompanion.Video).
#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtQuick/QQuickFramebufferObject>

#include <memory>

struct mpv_handle;

/// One mpv, shared by the item and its renderer (on Qt's render thread): it
/// ends when both are gone, after the renderer freed its render context.
struct MpvCore;

class MpvVideo : public QQuickFramebufferObject
{
    Q_OBJECT
    /// idle, loading, playing, buffering, ended, failed.
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    /// Why it failed, in mpv's or yt-dlp's words.
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    /// 0 to 125 as mpv counts it (the app maps its bar onto it).
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    /// Seconds; duration 0 for a live stream.
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    /// Whether frames can be drawn here (OpenGL; not the software renderer).
    Q_PROPERTY(bool drawable READ drawable NOTIFY drawableChanged)

public:
    explicit MpvVideo(QQuickItem *parent = nullptr);
    ~MpvVideo() override;

    Renderer *createRenderer() const override;

    QString state() const { return m_state; }
    QString error() const { return m_error; }
    QString title() const { return m_title; }
    bool paused() const { return m_paused; }
    bool muted() const { return m_muted; }
    double volume() const { return m_volume; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool drawable() const;

    void setPaused(bool paused);
    void setMuted(bool muted);
    void setVolume(double volume);

    /// Plays an address (https, or fdclose:// for Streamlink's pipe). `format`
    /// is yt-dlp's format ("" lets mpv pick); `start` seconds in.
    Q_INVOKABLE bool play(const QString &url, const QString &format, double start = 0);
    Q_INVOKABLE void stop();
    /// Jumps to `seconds` (absolute) or by `seconds` (relative).
    Q_INVOKABLE void seek(double seconds, bool relative);

    std::shared_ptr<MpvCore> core() const { return m_core; }

signals:
    void stateChanged();
    void titleChanged();
    void pausedChanged();
    void mutedChanged();
    void volumeChanged();
    void positionChanged();
    void durationChanged();
    void ended();
    void frameReady();
    void drawableChanged();

private slots:
    void readEvents();
    /// The renderer made mpv's render context: a video can load now.
    void renderReady();

private:
    bool ensureStarted();
    bool loadPending();
    struct Pending
    {
        QString url;
        QString format;
        double start = 0;
    };
    Pending m_pending;
    bool m_rendering = false;
    void setState(const QString &state, const QString &error = QString());
    void setMpv(const char *name, const QString &value);

    std::shared_ptr<MpvCore> m_core;
    mpv_handle *m_mpv = nullptr;
    QString m_state = QStringLiteral("idle");
    QString m_error;
    QString m_title;
    bool m_paused = false;
    bool m_muted = false;
    double m_volume = 70;
    double m_position = 0;
    double m_duration = 0;
};

/// Registers MpvVideo for QML.
void gc_register_video();
