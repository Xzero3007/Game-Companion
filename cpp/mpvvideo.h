// A video in the overlay: the user's libmpv (loaded when the first video
// starts, so the app runs without it) plays a stream and draws each frame
// into this Qt Quick item through OpenGL. Exposed to QML as `MpvVideo`
// (import GameCompanion.Video).
#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
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
    /// Videos decoded by the graphics card (Settings → Streams).
    Q_PROPERTY(bool hwdec READ hwdec WRITE setHwdec NOTIFY hwdecChanged)
    /// Quiet and loud passages evened out (mpv's dynaudnorm filter).
    Q_PROPERTY(bool levelling READ levelling WRITE setLevelling NOTIFY levellingChanged)
    /// For the home network's server (Jellyfin): set before the first video.
    /// No yt-dlp, no mpv scripts, no proxy: mpv goes straight to the address.
    Q_PROPERTY(bool local READ local WRITE setLocal NOTIFY localChanged)
    /// The video's chapters: [{title, time}] (time in seconds).
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY chaptersChanged)
    /// How fast it plays (1 = as recorded).
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)

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
    bool hwdec() const { return m_hwdec; }
    bool levelling() const { return m_levelling; }
    bool local() const { return m_local; }
    QVariantList chapters() const { return m_chapters; }
    double speed() const { return m_speed; }
    void setSpeed(double speed);
    void setHwdec(bool on);
    void setLevelling(bool on);
    void setLocal(bool on);

    void setPaused(bool paused);
    void setMuted(bool muted);
    void setVolume(double volume);

    /// Plays an address (https, or fdclose:// for Streamlink's pipe). `format`
    /// is yt-dlp's format ("" lets mpv pick); `start` seconds in; `header` an
    /// HTTP header sent along (the Jellyfin server's key), or "".
    Q_INVOKABLE bool play(const QString &url, const QString &format, double start = 0, const QString &header = QString());
    /// Picks a track: kind "audio" or "subtitle", `id` mpv's number for it
    /// (1, 2, ...), 0 for none.
    Q_INVOKABLE void setTrack(const QString &kind, int id);
    /// Adds a subtitle file (an address of the server playing) and shows it.
    Q_INVOKABLE void addSubtitle(const QString &url);
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
    void hwdecChanged();
    void levellingChanged();
    void localChanged();
    void chaptersChanged();
    void speedChanged();

protected:
    /// Moved to another window: draw there (a video waiting for its render
    /// context asks again).
    void itemChange(ItemChange change, const ItemChangeData &value) override;

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
        QString header;
    };
    Pending m_pending;
    bool m_rendering = false;
    void setState(const QString &state, const QString &error = QString());
    void setMpv(const char *name, const QString &value);

    std::shared_ptr<MpvCore> m_core;
    mpv_handle *m_mpv = nullptr;
    QString m_state = QStringLiteral("idle");
    QString m_error;
    /// mpv's or yt-dlp's last warning about the file playing now.
    QString m_why;
    QString m_title;
    bool m_paused = false;
    bool m_muted = false;
    double m_volume = 70;
    double m_position = 0;
    double m_duration = 0;
    static const char *levellingFilter(bool on);
    bool m_hwdec = true;
    bool m_levelling = false;
    bool m_local = false;
    QVariantList m_chapters;
    double m_speed = 1.0;
};

/// Registers MpvVideo for QML.
void gc_register_video();
