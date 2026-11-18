// A video in the overlay: the user's libmpv (loaded when the first video
// starts, so the app runs without it) plays a stream and draws each frame
// into this Qt Quick item through OpenGL. Exposed to QML as `MpvVideo`
// (import GameCompanion.Video).
#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtQuick/QQuickFramebufferObject>

#include <memory>

struct mpv_handle;
class HdrVideo;

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
    /// The name its sound has in the system's mixer (e.g. "Game Companion ·
    /// YouTube"): set before the first video.
    Q_PROPERTY(QString audioName READ audioName WRITE setAudioName NOTIFY audioNameChanged)
    /// The video's chapters: [{title, time}] (time in seconds).
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY chaptersChanged)
    /// How fast it plays (1 = as recorded).
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    /// When YouTube lets the video start (ms since the epoch, 0 = not held):
    /// it serves a stream only once its ad would have run, and mpv's ytdl
    /// hook waits that long (mpv 0.42+).
    Q_PROPERTY(qint64 heldUntil READ heldUntil NOTIFY heldChanged)
    /// mpv's or yt-dlp's last warning about the video playing now ("" none).
    Q_PROPERTY(QString why READ why NOTIFY whyChanged)
    /// yt-dlp's own options for the next video (mpv's ytdl-raw-options,
    /// "key=value,..."), "" none.
    Q_PROPERTY(QString ytdlOptions READ ytdlOptions WRITE setYtdlOptions NOTIFY ytdlOptionsChanged)
    /// No new frame is drawn and the position holds still while true (its
    /// window changes size: a frame drawn meanwhile showed the whole window
    /// stretched over the screen, MN); what was missed comes when it ends.
    Q_PROPERTY(bool frozen READ frozen WRITE setFrozen NOTIFY frozenChanged)
    /// Whether a picture is decoded (false while only sound plays: a
    /// YouTube stream whose video part failed to open).
    Q_PROPERTY(bool hasPicture READ hasPicture NOTIFY hasPictureChanged)
    /// The picture on a surface of its own (HdrVideo), so an HDR video shows
    /// in HDR (Settings → Streams → Videos "HDR video"). Taken when mpv
    /// starts; switched off it falls back at once. Anything that keeps it
    /// from working falls back to Qt's own drawing by itself.
    Q_PROPERTY(bool hdr READ hdr WRITE setHdr NOTIFY hdrChanged)
    /// For the log: "off", "unavailable: …", "fell back: …", "sdr (10 bit)"
    /// (a plain video on its own surface), "hdr (10 bit)" (PQ / BT.2020),
    /// "hdr refused: … (10 bit)".
    Q_PROPERTY(QString hdrState READ hdrState NOTIFY hdrStateChanged)
    /// For the log: the HDR surface's EGL and GL (vendor, renderer,
    /// version) and its bits ("" before it started).
    Q_PROPERTY(QString hdrInfo READ hdrInfo NOTIFY hdrStateChanged)
    /// The video playing is HDR (PQ or HLG), whichever way it is drawn.
    Q_PROPERTY(bool sourceHdr READ sourceHdr NOTIFY sourceHdrChanged)

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
    QString audioName() const { return m_audioName; }
    QVariantList chapters() const { return m_chapters; }
    double speed() const { return m_speed; }
    qint64 heldUntil() const { return m_heldUntil; }
    QString why() const { return m_why; }
    QString ytdlOptions() const { return m_ytdlOptions; }
    bool frozen() const { return m_frozen; }
    bool hasPicture() const { return m_hasPicture; }
    bool hdr() const { return m_hdr; }
    void setHdr(bool on);
    QString hdrState() const { return m_hdrState; }
    QString hdrInfo() const { return m_hdrInfo; }
    bool sourceHdr() const { return m_sourceHdr; }
    void setFrozen(bool on);
    /// mpv has a new frame: drawn unless frozen.
    void newFrame();
    void setYtdlOptions(const QString &options);
    void setSpeed(double speed);
    void setHwdec(bool on);
    void setLevelling(bool on);
    void setLocal(bool on);
    void setAudioName(const QString &name);

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
    /// For the log: codec, size, frame rate, hardware decoder, frames
    /// dropped and shown late ("" without mpv). After a file played to its
    /// end mpv has let it go: then the last values taken while it played.
    Q_INVOKABLE QString playStats() const;

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
    void audioNameChanged();
    void chaptersChanged();
    void speedChanged();
    void heldChanged();
    void whyChanged();
    void ytdlOptionsChanged();
    void frozenChanged();
    void hasPictureChanged();
    void hdrChanged();
    void hdrStateChanged();
    void sourceHdrChanged();
    /// The HDR surface fell back while a video played: mpv started anew, the
    /// window asks for the video again from `position` (a new Streamlink
    /// pipe, a new Jellyfin session).
    void reloadNeeded(double position);
    /// One of mpv's lines while the HDR surface draws (for the log).
    void hdrNote(const QString &line);

protected:
    /// Moved to another window: draw there (a video waiting for its render
    /// context asks again).
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private slots:
    void readEvents();
    /// The renderer made mpv's render context: a video can load now.
    void renderReady();
    /// The HDR surface stopped working: Qt draws the picture again.
    void hdrFailed(const QString &why);

private:
    bool ensureStarted();
    /// Starts the HDR surface for mpv (once mpv runs); false falls back.
    bool startHdr();
    /// Lets it go: Qt's renderer draws again, what played goes on.
    void dropHdr(const QString &state);
    /// Where the HDR surface goes: Qt's render thread, GUI thread waiting.
    void placeHdr();
    /// PQ output and description while an HDR video plays.
    void applyHdrPicture();
    void setHdrState(const QString &state);
    HdrVideo *m_hdrVideo = nullptr;
    bool m_hdr = true;
    QString m_hdrState = QStringLiteral("off");
    QString m_hdrInfo;
    int m_hdrNotes = 0;
    /// The HDR surface failed or was switched off: not again in this window.
    bool m_hdrBlocked = false;
    bool m_sourceHdr = false;
    QMetaObject::Connection m_syncConn;
    /// What plays now (played again from where it was after a fall back).
    QString m_currentUrl, m_currentFormat, m_currentHeader;
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
    qint64 m_heldUntil = 0;
    QString m_ytdlOptions;
    void setHeldUntil(qint64 at);
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
    QString m_audioName = QStringLiteral("Game Companion");
    QVariantList m_chapters;
    double m_speed = 1.0;
    bool m_frozen = false;
    bool m_missed = false;
    bool m_positionMissed = false;
    bool m_hasPicture = false;
    void setHasPicture(bool on);
    /// playStats() as it read while the file played (every 2 s at most).
    QString liveStats(bool *loaded = nullptr) const;
    QString m_lastStats;
    QElapsedTimer m_statsClock;
};

/// Registers MpvVideo for QML.
void gc_register_video();
