// Builds Game Companion's PoE 2 price check from an Exiled Exchange 2
// checkout (github.com/Kvan7/Exiled-Exchange-2, MIT):
//
//   (cd <EE2>/renderer && npm install --ignore-scripts)
//   node tools/poe2-ee2/build.mjs <EE2 checkout>
//
// Writes qml/poe2/ee2kit.js (EE2's parser, filters and trade requests in
// one file for Qt's JavaScript, which is ES2016 without Intl or BigInt) and
// copies EE2's item and stat data to data/poe2/<lang>/. Run it again when
// EE2 brings a new league's data or parser fixes.
import fs from "fs";
import path from "path";
import { createRequire } from "module";
import { fileURLToPath } from "url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const ee2 = path.resolve(process.argv[2] || "");
const renderer = path.join(ee2, "renderer");
if (!fs.existsSync(path.join(renderer, "src/parser/Parser.ts"))) {
  console.error("usage: node tools/poe2-ee2/build.mjs <Exiled-Exchange-2 checkout>");
  process.exit(1);
}
const require = createRequire(path.join(renderer, "package.json"));
const esbuild = require("esbuild");
const LANGS = ["en", "de"];

// Patches for Qt's JavaScript: regular expressions it cannot read
// (look-behind, named groups). Each must match exactly once.
const PATCHES = {
  // Look-behind: the character in front is captured instead (group 1) and
  // given back by the replacement.
  "src/parser/stat-translations.ts": [
    [
      "/(?<value>(?<!\\d|\\))[+-]?\\d+(?:\\.\\d+)?)(?:\\((?<min>.[^)-]*)(?:-(?<max>[^)]+))?\\))?/gm",
      "/(^|[^\\d)])([+-]?\\d+(?:\\.\\d+)?)(?:\\((.[^)-]*)(?:-([^)]+))?\\))?/gm",
    ],
    ["(_, roll: string, min?: string, max?: string) => {", "(_, pre: string, roll: string, min?: string, max?: string) => {"],
    [
      'return min != null ? `#(${min}-${max})` : "#";\n        } else {\n          return "#";',
      'return pre + (min != null ? `#(${min}-${max})` : "#");\n        } else {\n          return pre + "#";',
    ],
  ],
};

const ee2Version = JSON.parse(fs.readFileSync(path.join(ee2, "main/package.json"), "utf8")).version;

// `a.match(re)` / `re.exec(a)` → __gcMatch(a, re) / __gcExec(re, a) in
// files that read named groups (see shims/timers.ts).
const ts = require("typescript");
function groupsCalls(src, fileName) {
  if (!src.includes(".groups")) return src;
  const sf = ts.createSourceFile(fileName, src, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const edits = [];
  const visit = (node) => {
    if (ts.isCallExpression(node) && !node.questionDotToken && node.arguments.length === 1 &&
        ts.isPropertyAccessExpression(node.expression) && !node.expression.questionDotToken &&
        (node.expression.name.text === "match" || node.expression.name.text === "exec")) {
      edits.push(node);
      return; // the inner parts are written out as they are
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  let out = src;
  for (const node of edits.sort((a, b) => b.getStart() - a.getStart())) {
    const obj = node.expression.expression.getText(sf);
    const arg = node.arguments[0].getText(sf);
    const call = node.expression.name.text === "match" ? `__gcMatch(${obj}, ${arg})` : `__gcExec(${obj}, ${arg})`;
    out = out.slice(0, node.getStart()) + call + out.slice(node.getEnd());
  }
  return out;
}

const patchPlugin = {
  name: "gc-patches",
  setup(build) {
    build.onLoad({ filter: /\.ts$/ }, (args) => {
      if (!args.path.startsWith(path.join(renderer, "src") + path.sep)) return undefined;
      const rel = path.relative(renderer, args.path).split(path.sep).join("/");
      const list = PATCHES[rel] || [];
      let src = fs.readFileSync(args.path, "utf8");
      if (!list.length && !src.includes(".groups")) return undefined;
      for (const [from, to] of list) {
        const n = src.split(from).length - 1;
        if (n !== 1) throw new Error(`patch for ${rel} matched ${n} times: ${from}`);
        src = src.replace(from, to);
      }
      return { contents: groupsCalls(src, args.path), loader: "ts" };
    });
  },
};

const shim = (f) => path.join(here, "shims", f);
const alias = {
  "vue-i18n": shim("i18n.ts"),
  "@sindresorhus/fnv1a": shim("fnv1a.ts"),
  "object-hash": shim("object-hash.ts"),
  luxon: shim("luxon.ts"),
  vue: require.resolve("@vue/runtime-core"),
};

// EE2's own files that Game Companion replaces, however they are imported.
const replaced = {
  "src/web/Config.ts": shim("config.ts"),
  "src/web/background/IPC.ts": shim("ipc.ts"),
  "src/web/background/Prices.ts": shim("prices.ts"),
  "src/web/i18n.ts": shim("i18n.ts"),
  "src/assets/client-string-loader.ts": shim("client-strings.ts"),
};

function file(base) {
  for (const ext of ["", ".ts", "/index.ts", ".js"]) {
    if (fs.existsSync(base + ext) && fs.statSync(base + ext).isFile()) return base + ext;
  }
  return null;
}

const aliasPlugin = {
  name: "gc-alias",
  setup(build) {
    build.onResolve({ filter: /.*/ }, (args) => {
      if (alias[args.path]) return { path: alias[args.path] };
      const cs = /^gc:client-strings\/([a-z-]+)$/i.exec(args.path);
      if (cs) return { path: path.join(renderer, "public/data", cs[1], "client_strings.js") };
      let found = null;
      if (args.path.startsWith("@/")) found = file(path.join(renderer, "src", args.path.slice(2)));
      else if (args.path.startsWith(".") && args.resolveDir.startsWith(renderer)) found = file(path.resolve(args.resolveDir, args.path));
      if (!found) return undefined;
      const rel = path.relative(renderer, found).split(path.sep).join("/");
      return { path: replaced[rel] || found };
    });
  },
};

const out = path.join(repo, "qml/poe2/ee2kit.js");
const result = await esbuild.build({
  entryPoints: [path.join(here, "entry.ts")],
  bundle: true,
  format: "iife",
  globalName: "EE2",
  target: "es2016",
  platform: "neutral",
  mainFields: ["module", "main"],
  minify: false,
  legalComments: "none",
  write: false,
  plugins: [aliasPlugin, patchPlugin],
  inject: [shim("timers.ts")],
  define: {
    "process.env.NODE_ENV": '"production"',
    "import.meta.env.BASE_URL": '"/"',
    "import.meta.vitest": "undefined",
    __VUE_OPTIONS_API__: "false",
    __VUE_PROD_DEVTOOLS__: "false",
    __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: "false",
  },
  nodePaths: [path.join(renderer, "node_modules")],
  logLevel: "warning",
});

let code = result.outputFiles[0].text;
// The methods newer than Qt's JavaScript that EE2 calls.
const polyfills = fs.readFileSync(path.join(here, "polyfills.js"), "utf8");
const header = `.pragma library
// GENERATED by tools/poe2-ee2/build.mjs from Exiled Exchange 2 ${ee2Version}
// (github.com/Kvan7/Exiled-Exchange-2, MIT License, Copyright (c) 2020
// Alexander Drozdov; PoE 2 fork by Kvan7) with Vue's reactivity (MIT,
// Evan You) and neverthrow, dot-prop, fastest-levenshtein, fast-deep-equal
// (MIT). Do not edit: change tools/poe2-ee2/ and build again.
`;
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, header + polyfills + "\n" + code);

for (const lang of LANGS) {
  const dir = path.join(repo, "data/poe2", lang);
  fs.mkdirSync(dir, { recursive: true });
  for (const f of ["items.ndjson", "stats.ndjson", "app_i18n.json"]) {
    const src = path.join(renderer, "public/data", lang, f);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(dir, f));
  }
}
fs.copyFileSync(path.join(renderer, "public/data/item-drop.json"), path.join(repo, "data/poe2/item-drop.json"));
fs.copyFileSync(path.join(renderer, "public/data/patrons.json"), path.join(repo, "data/poe2/patrons.json"));
fs.writeFileSync(path.join(repo, "data/poe2/VERSION"), `Exiled Exchange 2 ${ee2Version}\n`);
console.log(`wrote ${path.relative(repo, out)} (${Math.round(code.length / 1024)} KB) and data/poe2 (${LANGS.join(", ")}) from EE2 ${ee2Version}`);
