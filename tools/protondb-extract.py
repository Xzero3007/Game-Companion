#!/usr/bin/env python3
"""Builds the app's ProtonDB extract from a ProtonDB data export (ODbL).

Usage: python3 -I tools/protondb-extract.py reports_piiremoved.json out.json [months]
       gzip -9 -n -c out.json > data/protondb.json.gz

For every Steam game with at least MIN_REPORTS working reports (verdict
"yes") in the last `months` months (default 24): how many, the Proton
variants they used and the launch-option parts they wrote (environment
variables by name with their most common value, and wrapper programs),
each with its count. Only option parts are kept, never notes or system
details; values longer than MAX_VALUE, values naming a folder in a home
or on a mounted disk, and values of LD_PRELOAD and *_PATH, *_RUNTIME,
*_FILE, *_DIR settings are left out (name and count stay); each count also by system group: GPU maker (nvidia, amd,
intel, deck), distribution family (cachyos, arch, steamos, bazzite, fedora,
debian, nixos, suse, gentoo, other) and CPU maker (amd, intel, deck), so
the app can weigh what people with a system like this one use. The result
is a derived database under the ODbL (see NOTICE-ProtonDB.txt).
"""
import collections
import json
import re
import shlex
import sys
import time

MIN_REPORTS = 3
TOP_OPTIONS = 16
TOP_PROTON = 4
ENV = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
WRAPPER = re.compile(r"^[A-Za-z0-9_./+-]+$")
MAX_VALUE = 120
# Values that may show a reporter's own folders or files: dropped (the
# option's name and count stay).
PRIVATE_VALUE = re.compile(r"/home/|/mnt/|/run/media|/media/|/var/home|~/")
PRIVATE_NAME = re.compile(r"^LD_PRELOAD$|_PATH$|_RUNTIME$|_FILE$|_DIR$|CONFIG_FILE$")
GE = re.compile(r"\bge\b|proton-ge|ge-proton|glorious")
KNOWN_WRAPPERS = {
    "gamemoderun", "mangohud", "gamescope", "game-performance", "prime-run",
    "dlss-swapper", "obs-gamecapture", "strangle", "taskset", "nice",
    "env", "pw-jack", "firejail", "proton-launch", "vkbasalt",
}


def gpu_of(s):
    g = (s.get("gpu") or "").lower()
    if "vangogh" in g or "custom gpu 0405" in g or "sephiroth" in g:
        return "deck"
    if "nvidia" in g or "geforce" in g or "rtx" in g or "gtx" in g:
        return "nvidia"
    if "amd" in g or "radeon" in g or "radv" in g:
        return "amd"
    if "intel" in g:
        return "intel"
    return ""


def os_of(s):
    o = (s.get("os") or "").lower()
    for key, names in (
        ("cachyos", ("cachyos",)),
        ("steamos", ("steamos",)),
        ("bazzite", ("bazzite",)),
        ("arch", ("arch linux", "endeavouros", "manjaro", "garuda", "artix")),
        ("fedora", ("fedora", "nobara")),
        ("debian", ("ubuntu", "mint", "pop!_os", "debian", "zorin", "pikaos", "kubuntu", "elementary")),
        ("nixos", ("nixos",)),
        ("suse", ("opensuse",)),
        ("gentoo", ("gentoo",)),
    ):
        if any(n in o for n in names):
            return key
    return "other" if o else ""


def cpu_of(s):
    c = (s.get("cpu") or "").lower()
    if "custom apu 0405" in c or "custom apu 0932" in c:
        return "deck"
    if "amd" in c or "ryzen" in c:
        return "amd"
    if "intel" in c:
        return "intel"
    return ""


def value_of(name, value):
    """The value to keep, or "" (cut at the length limit, or private)."""
    if len(value) > MAX_VALUE or PRIVATE_NAME.search(name) or PRIVATE_VALUE.search(value):
        return ""
    return value


def parts(text):
    """The env vars and wrappers before %command% (the args after it count too
    as "arg:<word>")."""
    try:
        words = shlex.split(text, posix=True)
    except ValueError:
        words = text.split()
    out = []
    seen_cmd = False
    for w in words:
        if "%command%" in w:
            seen_cmd = True
            continue
        if not seen_cmd:
            m = ENV.match(w)
            if m:
                out.append(("env", m.group(1), value_of(m.group(1), m.group(2))))
                continue
            base = w.rsplit("/", 1)[-1]
            if base in KNOWN_WRAPPERS:
                out.append(("wrapper", base, ""))
            continue
        if w.startswith("-") and len(w) <= 40 and WRAPPER.match(w.split("=")[0]):
            out.append(("arg", w.split("=")[0], ""))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    months = int(sys.argv[3]) if len(sys.argv) > 3 else 24
    since = time.time() - months * 30.5 * 86400
    reports = json.load(open(src, encoding="utf-8"))
    games = {}
    newest = 0
    for r in reports:
        ts = r.get("timestamp") or 0
        newest = max(newest, ts)
        if ts < since:
            continue
        resp = r.get("responses") or {}
        if resp.get("verdict") != "yes":
            continue
        app = ((r.get("app") or {}).get("steam") or {}).get("appId")
        if not app or not str(app).isdigit():
            continue
        g = games.setdefault(str(app), {
            "title": (r.get("app") or {}).get("title") or "",
            "n": 0, "proton": collections.Counter(),
            "opts": collections.Counter(), "values": collections.defaultdict(collections.Counter),
            "groups": collections.Counter(), "by": collections.defaultdict(collections.Counter),
        })
        g["n"] += 1
        system = r.get("systemInfo") or {}
        groups = [f"{k}:{v}" for k, v in (("gpu", gpu_of(system)), ("os", os_of(system)), ("cpu", cpu_of(system))) if v]
        for group in groups:
            g["groups"][group] += 1
        variant = resp.get("variant") or ""
        if variant in ("ge", "notListed", "older") and resp.get("customProtonVersion"):
            name = str(resp["customProtonVersion"]).strip()[:40]
            low = name.lower()
            variant = "cachyos" if "cachyos" in low else "ge" if GE.search(low) else variant
        if variant:
            g["proton"][variant] += 1
        opts = resp.get("launchOptions")
        if isinstance(opts, str) and opts.strip():
            for kind, name, value in set(parts(opts)):
                key = f"{kind}:{name}"
                g["opts"][key] += 1
                for group in groups:
                    g["by"][key][group] += 1
                if value:
                    g["values"][key][value] += 1
    out = {}
    for app, g in games.items():
        if g["n"] < MIN_REPORTS:
            continue
        options = []
        for key, count in g["opts"].most_common(TOP_OPTIONS):
            if count < 2:
                break
            kind, name = key.split(":", 1)
            item = {"kind": kind, "name": name, "count": count}
            if g["values"][key]:
                item["value"] = g["values"][key].most_common(1)[0][0]
            # By system group ("gpu:nvidia", "os:cachyos", "cpu:amd" ...).
            item["by"] = dict(g["by"][key])
            options.append(item)
        out[app] = {
            "title": g["title"],
            "reports": g["n"],
            "groups": dict(g["groups"]),
            "proton": [{"variant": v, "count": c} for v, c in g["proton"].most_common(TOP_PROTON)],
            "options": options,
        }
    doc = {
        "source": "ProtonDB data export (github.com/bdefore/protondb-data), ODbL 1.0",
        "export": time.strftime("%Y-%m-%d", time.gmtime(newest)),
        "months": months,
        "games": out,
    }
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print(f"{len(out)} games, export {doc['export']}")


if __name__ == "__main__":
    main()
