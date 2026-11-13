#!/bin/sh
# Checks the Twitch chat client against a made-up IRC server on 127.0.0.1
# (one RECONNECT must lead to exactly one new connection). Run from this
# folder; builds into ./build. Nothing goes to Twitch.
set -e
mkdir -p build && cd build
[ -f cert.pem ] || openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=127.0.0.1 2>/dev/null
G=../../../cpp
/usr/lib/qt6/libexec/moc $G/twitchchat.h -o moc_twitchchat.cpp
g++ -std=c++17 -fPIC -DGC_CHAT_TEST -I$G ../main.cpp $G/twitchchat.cpp moc_twitchchat.cpp $(pkg-config --cflags --libs Qt6Network Qt6Qml) -o chattest
python3 -I ../server.py & server=$!
sleep 1
timeout 20 ./chattest || true
kill $server
echo "connections: $(grep -c connection server.log) (2 expected)"
