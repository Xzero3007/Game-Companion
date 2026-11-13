#include <QtCore/QCoreApplication>
#include <QtCore/QTimer>
#include <cstdio>
#include "twitchchat.h"
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    TwitchChat chat;
    QObject::connect(&chat, &TwitchChat::message, [](const QString &n, const QString &c, const QString &t, const QString &e, bool, bool s) {
        printf("msg %s %s '%s' %s %d\n", qPrintable(n), qPrintable(c), qPrintable(t), qPrintable(e), s); fflush(stdout); });
    QObject::connect(&chat, &TwitchChat::stateChanged, [&] { printf("state %s %s\n", qPrintable(chat.state()), qPrintable(chat.note())); fflush(stdout); });
    chat.join("chan", "", "");
    QTimer::singleShot(15000, &app, &QCoreApplication::quit);
    return app.exec();
}
