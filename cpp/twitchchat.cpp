#include "twitchchat.h"

#include <QtCore/QHash>
#include <QtCore/QRandomGenerator>
#include <QtCore/QRegularExpression>
#include <QtQml/QQmlEngine>

namespace {

#ifdef GC_CHAT_TEST
// Only the test harness (tools/, built by hand) talks to a made-up server.
const char *const HOST = "127.0.0.1";
const quint16 PORT = 16697;
#else
const char *const HOST = "irc.chat.twitch.tv";
const quint16 PORT = 6697;
#endif

bool validLogin(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9_]{1,25}$"));
    return re.match(s).hasMatch();
}

bool validToken(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9]{20,64}$"));
    return re.match(s).hasMatch();
}

// An IRC tag's value with its escapes undone.
QString unescapeTag(const QByteArray &v)
{
    QByteArray out;
    out.reserve(v.size());
    for (int i = 0; i < v.size(); ++i) {
        if (v[i] == '\\' && i + 1 < v.size()) {
            const char c = v[++i];
            out.append(c == 's' ? ' ' : c == ':' ? ';' : c == 'r' ? '\r' : c == 'n' ? '\n' : c);
        } else {
            out.append(v[i]);
        }
    }
    return QString::fromUtf8(out);
}

struct Line
{
    QHash<QByteArray, QString> tags;
    QByteArray prefix;
    QByteArray command;
    QList<QByteArray> params;
    QString trailing;
    bool hasTrailing = false;
};

Line parse(QByteArray s)
{
    Line l;
    if (s.startsWith('@')) {
        const int sp = s.indexOf(' ');
        if (sp < 0) {
            return l;
        }
        for (const QByteArray &kv : s.mid(1, sp - 1).split(';')) {
            const int eq = kv.indexOf('=');
            if (eq > 0) {
                l.tags.insert(kv.left(eq), unescapeTag(kv.mid(eq + 1)));
            }
        }
        s = s.mid(sp + 1);
    }
    if (s.startsWith(':')) {
        const int sp = s.indexOf(' ');
        if (sp < 0) {
            return l;
        }
        l.prefix = s.mid(1, sp - 1);
        s = s.mid(sp + 1);
    }
    const int colon = s.indexOf(" :");
    QByteArray head = colon >= 0 ? s.left(colon) : s;
    if (colon >= 0) {
        l.trailing = QString::fromUtf8(s.mid(colon + 2));
        l.hasTrailing = true;
    }
    QList<QByteArray> parts = head.split(' ');
    parts.removeAll(QByteArray());
    if (!parts.isEmpty()) {
        l.command = parts.takeFirst();
    }
    l.params = parts;
    return l;
}

} // namespace

TwitchChat::TwitchChat(QObject *parent) : QObject(parent)
{
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &TwitchChat::connectNow);
    connect(&m_socket, &QSslSocket::encrypted, this, [this] {
        m_buffer.clear();
        write("CAP REQ :twitch.tv/tags twitch.tv/commands");
        if (m_wantAuth) {
            write("PASS oauth:" + m_token.toLatin1());
            write("NICK " + m_user.toLower().toLatin1());
        } else {
            // Twitch's way to read without an account.
            write("NICK justinfan" + QByteArray::number(10000 + QRandomGenerator::global()->bounded(80000)));
        }
        write("JOIN #" + m_channel.toLatin1());
    });
    connect(&m_socket, &QSslSocket::readyRead, this, &TwitchChat::readLines);
#ifdef GC_CHAT_TEST
    connect(&m_socket, &QSslSocket::sslErrors, this, [this] { m_socket.ignoreSslErrors(); });
#endif
    connect(&m_socket, &QSslSocket::disconnected, this, [this] {
        if (m_channel.isEmpty()) {
            return;
        }
        // Lost: again after a while (longer each time, at most a minute);
        // a retry already waiting (Twitch's RECONNECT) stays as it is.
        if (m_retry.isActive()) {
            return;
        }
        setState(QStringLiteral("connecting"), QStringLiteral("Reconnecting…"));
        m_retry.start(qMin(60000, 2000 * (1 << qMin(m_tries++, 5))));
    });
    connect(&m_socket, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (m_socket.state() == QAbstractSocket::UnconnectedState && !m_channel.isEmpty() && !m_retry.isActive()) {
            setState(QStringLiteral("failed"), m_socket.errorString());
            m_retry.start(qMin(60000, 2000 * (1 << qMin(m_tries++, 5))));
        }
    });
}

TwitchChat::~TwitchChat()
{
    m_channel.clear();
    m_socket.abort();
}

void TwitchChat::setState(const QString &state, const QString &note)
{
    if (state == m_state && note == m_note) {
        return;
    }
    m_state = state;
    m_note = note;
    emit stateChanged();
}

void TwitchChat::join(const QString &channel, const QString &user, const QString &token)
{
    const QString c = channel.trimmed().toLower();
    if (!validLogin(c)) {
        leave();
        return;
    }
    const bool auth = validLogin(user) && validToken(token);
    if (c == m_channel && auth == m_wantAuth && m_state != QLatin1String("failed") && m_state != QLatin1String("idle")) {
        return;
    }
    leave();
    m_channel = c;
    m_user = auth ? user : QString();
    m_token = auth ? token : QString();
    m_wantAuth = auth;
    m_tries = 0;
    emit channelChanged();
    connectNow();
}

void TwitchChat::connectNow()
{
    if (m_channel.isEmpty()) {
        return;
    }
    m_authed = false;
    m_retry.stop();
    // Dropping the old connection must not count as losing it (that would
    // start the retry again, and again).
    m_socket.blockSignals(true);
    m_socket.abort();
    m_socket.blockSignals(false);
    setState(QStringLiteral("connecting"));
    m_socket.connectToHostEncrypted(QString::fromLatin1(HOST), PORT);
}

void TwitchChat::leave()
{
    m_retry.stop();
    const bool had = !m_channel.isEmpty();
    m_channel.clear();
    m_token.clear();
    m_authed = false;
    if (m_socket.state() != QAbstractSocket::UnconnectedState) {
        m_socket.blockSignals(true);
        m_socket.abort();
        m_socket.blockSignals(false);
    }
    if (!m_roomId.isEmpty()) {
        m_roomId.clear();
        emit roomIdChanged();
    }
    if (had) {
        emit channelChanged();
    }
    setState(QStringLiteral("idle"));
}

bool TwitchChat::send(const QString &text)
{
    QString t = text.simplified();
    if (!canSend() || t.isEmpty()) {
        return false;
    }
    if (t.size() > 500) {
        t.truncate(500);
        // Never half a surrogate pair at the end.
        if (t.at(t.size() - 1).isHighSurrogate()) {
            t.chop(1);
        }
    }
    write("PRIVMSG #" + m_channel.toLatin1() + " :" + t.toUtf8());
    emit message(m_ownName.isEmpty() ? m_user : m_ownName, m_ownColour, t, QString(), true, false);
    return true;
}

void TwitchChat::write(const QByteArray &line)
{
    QByteArray l = line;
    l.replace('\r', ' ').replace('\n', ' ');
    m_socket.write(l + "\r\n");
}

void TwitchChat::readLines()
{
    m_buffer += m_socket.readAll();
    // Never more than a little unread (a broken line).
    if (m_buffer.size() > 1 << 20) {
        m_buffer.clear();
    }
    int end;
    while ((end = m_buffer.indexOf("\r\n")) >= 0) {
        const QByteArray line = m_buffer.left(end);
        m_buffer.remove(0, end + 2);
        if (!line.isEmpty()) {
            handle(line);
        }
    }
}

void TwitchChat::handle(const QByteArray &raw)
{
    const Line l = parse(raw);
    if (l.command == "PING") {
        write("PONG :" + l.trailing.toUtf8());
        return;
    }
    if (l.command == "RECONNECT") {
        m_retry.start(1000);
        return;
    }
    if (l.command == "001") {
        m_authed = m_wantAuth;
        return;
    }
    if (l.command == "ROOMSTATE") {
        const QString id = l.tags.value("room-id");
        if (!id.isEmpty() && id != m_roomId) {
            m_roomId = id;
            emit roomIdChanged();
        }
        m_tries = 0;
        setState(QStringLiteral("joined"), m_authed ? QString() : QStringLiteral("Reading only: sign in to Twitch in Settings → Streams to write."));
        return;
    }
    if (l.command == "USERSTATE" || l.command == "GLOBALUSERSTATE") {
        m_ownName = l.tags.value("display-name", m_ownName);
        m_ownColour = l.tags.value("color", m_ownColour);
        return;
    }
    if (l.command == "PRIVMSG") {
        QString name = l.tags.value("display-name");
        if (name.isEmpty()) {
            name = QString::fromUtf8(l.prefix.left(l.prefix.indexOf('!')));
        }
        QString text = l.trailing;
        // "/me" lines.
        if (text.startsWith(QLatin1String("\x01" "ACTION ")) && text.endsWith(QLatin1Char('\x01'))) {
            text = text.mid(8, text.size() - 9);
        }
        emit message(name, l.tags.value("color"), text, l.tags.value("emotes"), false, false);
        return;
    }
    if (l.command == "USERNOTICE") {
        const QString sys = l.tags.value("system-msg");
        if (!sys.isEmpty()) {
            emit message(QString(), QString(), sys + (l.trailing.isEmpty() ? QString() : QStringLiteral(" · ") + l.trailing), QString(), false, true);
        }
        return;
    }
    if (l.command == "NOTICE") {
        if (m_wantAuth && (l.trailing.contains(QLatin1String("authentication failed")) || l.trailing.contains(QLatin1String("Improperly formatted auth")))) {
            // The token is refused for chat: read without it.
            m_wantAuth = false;
            m_token.clear();
            emit message(QString(), QString(), QStringLiteral("Twitch did not take the sign-in for chat: reading only."), QString(), false, true);
            m_retry.start(500);
            return;
        }
        emit message(QString(), QString(), l.trailing, QString(), false, true);
    }
}

void gc_register_chat()
{
    qmlRegisterType<TwitchChat>("GameCompanion.Chat", 1, 0, "TwitchChat");
}
