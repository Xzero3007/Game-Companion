#!/usr/bin/env python3
"""Takes the Clicktrough Armory plugin's logic (same author, GPL-3.0) over
as one QML JavaScript library, qml/aion2/armorykit.js, and its data as
crates/aion2/data/armory/data.json (with its notices and README).

    tools/aion2-armory-import.py <A2Tools-Clicktrough-Plugins>/plugins

calc.js (the sums: gear score, enhancing, plans, soul bindings, skills,
Daevanion, references) and nc.js (NC's character pages read) are kept as
they are. `globalThis` becomes the library's own object `G`; the data
(1 MB) is not in the library: `G.load(data)` runs calc.js once with the
data the Armory reads from the package. QML's Number.toLocaleString takes
a Qt locale, so `fmt` is written out here, and `short` (a reserved word in
QML's JavaScript) is called `brief`. esbuild writes it all for Qt 6.4's
JavaScript (--target=es2017). esbuild must be on PATH or given as ESBUILD
(e.g. `npx esbuild`).
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1]) / "armory"
root = Path(__file__).resolve().parent.parent
out_js = root / "qml" / "aion2" / "armorykit.js"
out_data = root / "crates" / "aion2" / "data" / "armory"

# ---- the data: data.js is one assignment of a JSON object ----
text = (src / "data.js").read_text(encoding="utf-8")
start = text.index("globalThis.ARMORY_DATA = ") + len("globalThis.ARMORY_DATA = ")
data = json.loads(text[start:].rstrip().rstrip(";"))
out_data.mkdir(parents=True, exist_ok=True)
(out_data / "data.json").write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
for notice in sorted(src.glob("NOTICE-*.txt")):
    shutil.copy(notice, out_data / notice.name)
shutil.copy(src / "README.md", out_data / "README-armory.md")

# ---- the logic ----
calc = (src / "calc.js").read_text(encoding="utf-8")
nc = (src / "nc.js").read_text(encoding="utf-8")

FMT = '''const fmt = (v, digits = 0) => {
    if (v == null || !Number.isFinite(v)) return "—";
    const neg = v < 0;
    let s = Math.abs(Number(v)).toFixed(digits);
    if (digits > 0) s = s.replace(/\\.?0+$/, "");
    const parts = s.split(".");
    // Qt's JS doubled the commas of a lookahead replace: grouped by hand.
    let g = "";
    for (let i = 0; i < parts[0].length; i++) g += (i && (parts[0].length - i) % 3 === 0 ? "," : "") + parts[0][i];
    parts[0] = g;
    return (neg ? "-" : "") + parts.join(".");
  };'''
calc, n = re.subn(r"const fmt = \(v, digits = 0\) => \(v == null[^;]*;", lambda m: FMT, calc, flags=re.S)
if n != 1:
    sys.exit("calc.js: fmt not found")
calc = re.sub(r"\bshort\b(?=\s*[(,])", "brief", calc)
calc = calc.replace("globalThis.", "G.")
# The data comes later, by G.load.
calc = calc.replace("(() => {\n  const D = G.ARMORY_DATA;", "G.load = (data) => {\n  G.ARMORY_DATA = data;\n  const D = data;", 1)
if not calc.rstrip().endswith("})();"):
    sys.exit("calc.js: its ending changed")
calc = calc.rstrip()[: -len("})();")] + "  return G.ArmoryCalc;\n};\n"

body = [
    "var G = {};\n",
    # QML's JavaScript has no URLSearchParams: the addresses' query in order.
    "var URLSearchParams = function (o) { this.o = o; };\n",
    "URLSearchParams.prototype.toString = function () {\n",
    "  var o = this.o; return Object.keys(o).filter(function (k) { return o[k] !== undefined && o[k] !== null; })\n",
    "    .map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(String(o[k])).replace(/%20/g, '+'); }).join('&');\n",
    "};\n",
    "if (!Object.fromEntries) Object.defineProperty(Object, 'fromEntries', { value: function (it) {\n",
    "  var o = {}; for (var e of it) o[e[0]] = e[1]; return o;\n",
    "}, writable: true, configurable: true });\n",
    "if (!Array.prototype.flat) Object.defineProperty(Array.prototype, 'flat', { value: function (d) {\n",
    "  d = d === undefined ? 1 : d;\n",
    "  return this.reduce(function (a, v) { return a.concat(Array.isArray(v) && d > 0 ? v.flat(d - 1) : [v]); }, []);\n",
    "}, writable: true, configurable: true });\n",
    "if (!Array.prototype.flatMap) Object.defineProperty(Array.prototype, 'flatMap', { value: function (f, t) {\n",
    "  return this.map(f, t).flat(1);\n",
    "}, writable: true, configurable: true });\n",
    f"// ---- armory/calc.js ----\n{calc}\n",
    f"// ---- armory/nc.js ----\n{nc.replace('globalThis.', 'G.')}\n",
    "var NC = G.ArmoryNC;\n",
    "var C = null;\n",
    "function load(data) { if (!C) C = G.load(data); return C; }\n",
]
esbuild = shlex.split(os.environ.get("ESBUILD", "esbuild"))
lowered = subprocess.run(esbuild + ["--target=es2017", "--loader=js", "--log-level=warning"],
                         input="".join(body), capture_output=True, text=True)
if lowered.returncode != 0:
    sys.exit(lowered.stderr)
out = lowered.stdout
left = [line[:120] for line in out.split("\n") if re.search(r"toLocaleString\(|BigInt|\bshort\(", line)]
if left:
    sys.exit("not readable by Qt 6.4's JavaScript:\n" + "\n".join(left[:10]))
head = (".pragma library\n"
        "// Generated by tools/aion2-armory-import.py from the Clicktrough Armory\n"
        "// plugin (GPL-3.0; the data's notices in crates/aion2/data/armory/).\n"
        "// Do not edit by hand. C is the plugin's ArmoryCalc once load(data) ran,\n"
        "// NC its reading of NC's character pages.\n")
out_js.write_text(head + out, encoding="utf-8")
print(f"{out_js} ({out_js.stat().st_size // 1024} KB), {out_data / 'data.json'} ({(out_data / 'data.json').stat().st_size // 1024} KB)")
