// EE2 ships binary indexes beside its .ndjson files (make-index-files.mjs);
// here they are made from the .ndjson when first asked, the same way.
import fnv1a from "./fnv1a";

function table(rows: Array<[number, number]>) {
  rows.sort((a, b) => a[0] - b[0]);
  const out = new Uint32Array(rows.length * 2);
  rows.forEach((r, i) => { out[i * 2] = r[0]; out[i * 2 + 1] = r[1]; });
  return out.buffer;
}

function lines(ndjson: string, each: (rec: any, start: number) => void) {
  let start = 0;
  while (start < ndjson.length) {
    let end = ndjson.indexOf("\n", start);
    if (end === -1) end = ndjson.length;
    if (end > start) each(JSON.parse(ndjson.slice(start, end)), start);
    start = end + 1;
  }
}

export function makeIndex(name: string, ndjson: string): ArrayBuffer {
  const rows: Array<[number, number]> = [];
  if (name === "stats-ref.index.bin") {
    lines(ndjson, (s, start) => rows.push([fnv1a(s.ref), start]));
  } else if (name === "stats-matcher.index.bin") {
    lines(ndjson, (s, start) => {
      for (const m of s.matchers) {
        rows.push([fnv1a(m.string), start]);
        if (m.advanced) rows.push([fnv1a(m.advanced), start]);
      }
    });
  } else {
    const seen: Record<string, boolean> = {};
    const byRef = name === "items-ref.index.bin";
    lines(ndjson, (it, start) => {
      const key = it.namespace + "::" + it.refName;
      if (seen[key]) return;
      seen[key] = true;
      rows.push([fnv1a(it.namespace + "::" + (byRef ? it.refName : it.name)), start]);
    });
  }
  return table(rows);
}
