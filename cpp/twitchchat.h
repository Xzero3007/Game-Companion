// Twitch chat for the overlay: one channel's chat read over Twitch's IRC
// (irc.chat.twitch.tv, TLS), anonymous, or signed in with the user's own
// twitch.tv token to write too. Exposed to QML as `TwitchChat`
// (import GameCompanion.Chat).
#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtNetwork/QSslSocket>

class TwitchChat : public QObject
{
    Q_OBJECT
    /// The channel (login) whose chat this is; "" none.
    Q_PROPERTY(QString channel READ channel NOTIFY channelChanged)
    /// idle, connecting, joined, failed.
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    /// Signed in and joined: messages can be written.
    Q_PROPERTY(bool canSend READ canSend NOTIFY stateChanged)
    /// A line about the state (why it fails, reading only, ...).
    Q_PROPERTY(QString note READ note NOTIFY stateChanged)
    /// The channel's Twitch id (for its 7TV and BTTV emotes).
    Q_PROPERTY(QString roomId READ roomId NOTIFY roomIdChanged)

public:
    explicit TwitchChat(QObject *parent = nullptr);
    ~TwitchChat() override;

    QString channel() const { return m_channel; }
    QString state() const { return m_state; }
    bool canSend() const { return m_state == QLatin1String("joined") && m_authed; }
    QString note() const { return m_note; }
    QString roomId() const { return m_roomId; }

    /// Joins a channel's chat: signed in when `user` and `token` are given
    /// (the token goes to Twitch's chat server only), else anonymous.
    Q_INVOKABLE void join(const QString &channel, const QString &user, const QString &token);
    Q_INVOKABLE void leave();
    /// Writes a message (signed in only); false if it was not sent.
    Q_INVOKABLE bool send(const QString &text);

signals:
    void channelChanged();
    void stateChanged();
    void roomIdChanged();
    /// One line: who (display name), their colour ("" none), the text, the
    /// Twitch emotes' places (the IRC tag, "" none), whether it is one's own,
    /// and whether it is a note of Twitch's (a sub, a raid, a notice).
    void message(const QString &name, const QString &colour, const QString &text, const QString &emotes, bool own, bool system);

private:
    void connectNow();
    void readLines();
    void handle(const QByteArray &line);
    void write(const QByteArray &line);
    void setState(const QString &state, const QString &note = QString());

    QSslSocket m_socket;
    QTimer m_retry;
    QByteArray m_buffer;
    QString m_channel;
    QString m_user;
    QString m_token;
    QString m_state = QStringLiteral("idle");
    QString m_note;
    QString m_roomId;
    QString m_ownName;
    QString m_ownColour;
    bool m_authed = false;
    bool m_wantAuth = false;
    int m_tries = 0;
};

void gc_register_chat();
