#!/usr/bin/env python3
"""Takes the logic of three Clicktrough plugins (same author, GPL-3.0) over
as one QML JavaScript library, qml/aion2/lootkit.js, for the LOOT window:
Inventory (calc.js, days.js, dungeons.js, dungeon-rates.js, zones.js),
Closet (data.js, logic.js) and Shugo Cards (calc.js), and their notices
into crates/aion2/data/loot/.

    tools/aion2-loot-import.py <A2Tools-Clicktrough-Plugins>/plugins

The item catalogue is not copied: the Market's (marketkit.js, MARKET_ITEMS,
the same list as the Inventory plugin's data.js) is the one catalogue, and
the anomaly check is the Market's too. The plugins' scripts are kept as
they are; `globalThis` becomes the library's own object `G`, and esbuild
writes them for Qt 6.4's JavaScript (--target=es2017: no ||=, object
spread, optional chaining or numeric separators there). esbuild must be on
PATH or given as ESBUILD (e.g. `npx esbuild`).
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1])
root = Path(__file__).resolve().parent.parent
out_js = root / "qml" / "aion2" / "lootkit.js"
out_data = root / "crates" / "aion2" / "data" / "loot"

files = [
    ("inventory", "zones.js"), ("inventory", "dungeon-rates.js"),
    ("inventory", "calc.js"), ("inventory", "days.js"), ("inventory", "dungeons.js"),
    ("closet", "data.js"), ("closet", "logic.js"),
    ("shugo-cards", "calc.js"),
]
body = [
    "var G = {};\n",
    # The one catalogue and the anomaly check: the Market's.
    "G.INVENTORY_DATA = { items: MK.G.MARKET_ITEMS.items, tickets: {} };\n",
    "G.MarketAnomaly = MK.A;\n",
    # A shop's 64-bit numbers (prices, times) fit a double: no BigInt in Qt 6.4.
    "// Qt's JavaScript has no TextDecoder: the card rounds' player names are\n",
    '// UTF-8 (MN, 0.8.14: every round that came live stayed unread).\n',
    'var TextDecoder = function () {};\n',
    'TextDecoder.prototype.decode = function (bytes) {\n',
    '  var out = "", i = 0, b = bytes || [];\n',
    '  while (i < b.length) {\n',
    '    var c = b[i++], n = 0, cp = 0;\n',
    '    if (c < 0x80) { out += String.fromCharCode(c); continue; }\n',
    '    if (c >= 0xf0 && c < 0xf8) { n = 3; cp = c & 7; } else if (c >= 0xe0) { n = 2; cp = c & 15; } else if (c >= 0xc0) { n = 1; cp = c & 31; } else { out += "\\ufffd"; continue; }\n',
    '    if (i + n > b.length) { out += "\\ufffd"; break; }\n',
    '    var ok = true;\n',
    '    for (var k = 0; k < n; k++) { var x = b[i + k]; if ((x & 0xc0) !== 0x80) { ok = false; break; } cp = cp * 64 + (x & 63); }\n',
    '    if (!ok) { out += "\\ufffd"; continue; }\n',
    '    i += n;\n',
    '    out += String.fromCodePoint(cp);\n',
    '  }\n',
    '  return out;\n',
    '};\n',
    "if (!DataView.prototype.getBigUint64) DataView.prototype.getBigUint64 = function (o, le) {\n",
    "  var lo = this.getUint32(o + (le ? 0 : 4), le), hi = this.getUint32(o + (le ? 4 : 0), le);\n",
    "  return hi * 4294967296 + lo;\n",
    "};\n",
    "if (!Array.prototype.flat) Object.defineProperty(Array.prototype, 'flat', { value: function (d) {\n",
    "  d = d === undefined ? 1 : d;\n",
    "  return this.reduce(function (a, v) { return a.concat(Array.isArray(v) && d > 0 ? v.flat(d - 1) : [v]); }, []);\n",
    "}, writable: true, configurable: true });\n",
    "if (!Array.prototype.flatMap) Object.defineProperty(Array.prototype, 'flatMap', { value: function (f, t) {\n",
    "  return this.map(f, t).flat(1);\n",
    "}, writable: true, configurable: true });\n",
    "if (!Object.fromEntries) Object.defineProperty(Object, 'fromEntries', { value: function (it) {\n",
    "  var o = {}; for (var e of it) o[e[0]] = e[1]; return o;\n",
    "}, writable: true, configurable: true });\n",
    "G.grouped = MK.G.grouped;\n",
]
for plugin, name in files:
    text = (src / plugin / name).read_text(encoding="utf-8")
    text = text.replace("globalThis.", "G.")
    # QML's Number.toLocaleString takes a Qt locale: thousands with commas.
    text = re.sub(r'Math\.round\(([^()]*(?:\([^()]*\))?)\)\.toLocaleString\("en-US"\)', r'G.grouped(\1)', text)
    body.append(f"// ---- {plugin}/{name} ----\n{text}\n")
body.append("var C = G.InventoryCalc;\nvar F = G.InventoryDays;\nvar DG = G.InventoryDungeons;\n"
            "var L = G.ClosetLogic;\nvar CD = G.CLOSET_DATA;\nvar S = G.ShugoCalc;\n")
esbuild = shlex.split(os.environ.get("ESBUILD", "esbuild"))
lowered = subprocess.run(esbuild + ["--target=es2017", "--loader=js", "--log-level=warning"],
                         input="".join(body), capture_output=True, text=True)
if lowered.returncode != 0:
    sys.exit(lowered.stderr)
text = lowered.stdout
# A card round of a Dimensional Invasion: more players pick a card than in a
# Shugo round (the plugin allowed 8 and 10 picks each; MN's 0.8.13 rounds
# stayed unread). Wider bounds, the same layout.
for a, b in [("if (n < 1 || n > 10) return null;", "if (n < 1 || n > 16) return null;"),
             ("if (np > 8) return null;", "if (np > 64) return null;"),
             ("if (times < 1 || times > 10) return null;", "if (times < 1 || times > 100) return null;")]:
    if a not in text:
        sys.exit("shugo-cards/calc.js changed: " + a)
    text = text.replace(a, b)
left = [line[:120] for line in text.split("\n") if re.search(r"toLocaleString\(|BigInt", line)]
if left:
    sys.exit("not readable by Qt 6.4's JavaScript:\n" + "\n".join(left[:10]))
head = (".pragma library\n"
        '.import "marketkit.js" as MK\n'
        "// Generated by tools/aion2-loot-import.py from the Clicktrough Inventory,\n"
        "// Closet and Shugo Cards plugins (GPL-3.0; the data's notices in\n"
        "// crates/aion2/data/loot/). Do not edit by hand.\n")
out_js.write_text(head + text, encoding="utf-8")

out_data.mkdir(parents=True, exist_ok=True)
for plugin in ("inventory", "closet", "shugo-cards"):
    for notice in sorted((src / plugin).glob("NOTICE-*.txt")):
        shutil.copy(notice, out_data / notice.name)
    shutil.copy(src / plugin / "README.md", out_data / f"README-{plugin}.md")
print(f"{out_js} ({out_js.stat().st_size // 1024} KB), {out_data}")
