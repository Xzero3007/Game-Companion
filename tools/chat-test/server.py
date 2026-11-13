import ssl, socket, threading, time, sys
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain("cert.pem","key.pem")
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(("127.0.0.1",16697)); srv.listen(5)
n = 0
log = open("server.log","w")
def handle(c, k):
    f = c.makefile("rwb")
    def send(l): f.write((l+"\r\n").encode()); f.flush()
    try:
        while True:
            line = f.readline()
            if not line: break
            line = line.decode().strip(); log.write(f"[{k}] {line}\n"); log.flush()
            if line.startswith("JOIN"):
                send(":tmi.twitch.tv 001 x :Welcome")
                send("@room-id=123 :tmi.twitch.tv ROOMSTATE #chan")
                send("@color=#1E90FF;display-name=Bob;emotes=25:0-4 :bob!bob@bob PRIVMSG #chan :Kappa hi")
                if k == 1: send(":tmi.twitch.tv RECONNECT")
    except Exception as e: log.write(f"[{k}] err {e}\n")
while True:
    s, _ = srv.accept(); n += 1
    try: c = ctx.wrap_socket(s, server_side=True)
    except Exception as e: log.write(f"tls err {e}\n"); continue
    log.write(f"connection {n}\n"); log.flush()
    threading.Thread(target=handle, args=(c, n), daemon=True).start()
