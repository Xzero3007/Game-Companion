// Methods newer than Qt 6.4's JavaScript (ES2016) that EE2 and Vue call;
// each is added only where it is missing.
(function () {
    function def(o, name, fn) { if (!o[name]) Object.defineProperty(o, name, { value: fn, writable: true, configurable: true }) }
    def(String.prototype, "replaceAll", function (a, b) {
        if (a instanceof RegExp) return this.replace(a, b)
        return typeof b === "function" ? this.split(a).map(function (x, i, l) { return x }).reduce(function (acc, x, i) { return i === 0 ? x : acc + b(a) + x }, "") : this.split(a).join(b)
    })
    def(String.prototype, "trimStart", function () { return this.replace(/^\s+/, "") })
    def(String.prototype, "trimEnd", function () { return this.replace(/\s+$/, "") })
    def(String.prototype, "matchAll", function (re) {
        var r = new RegExp(re.source, re.flags.indexOf("g") >= 0 ? re.flags : re.flags + "g"), s = String(this), out = [], m
        while ((m = r.exec(s)) !== null) { out.push(m); if (m[0] === "") r.lastIndex++ }
        return out[Symbol.iterator]()
    })
    def(String.prototype, "at", function (i) { i = Math.trunc(i) || 0; if (i < 0) i += this.length; return this.charAt(i) || undefined })
    def(Array.prototype, "flat", function (d) {
        d = d === undefined ? 1 : d
        return d < 1 ? this.slice() : this.reduce(function (acc, x) { return acc.concat(Array.isArray(x) ? x.flat(d - 1) : [x]) }, [])
    })
    def(Array.prototype, "flatMap", function (fn, me) { return this.map(fn, me).flat(1) })
    def(Array.prototype, "at", function (i) { i = Math.trunc(i) || 0; if (i < 0) i += this.length; return this[i] })
    def(Array.prototype, "findLast", function (fn) { for (var i = this.length - 1; i >= 0; i--) if (fn(this[i], i, this)) return this[i] })
    def(Array.prototype, "findLastIndex", function (fn) { for (var i = this.length - 1; i >= 0; i--) if (fn(this[i], i, this)) return i; return -1 })
    def(Array.prototype, "toSorted", function (fn) { return this.slice().sort(fn) })
    def(Array.prototype, "toReversed", function () { return this.slice().reverse() })
    def(Object, "fromEntries", function (l) { var o = {}; Array.from(l).forEach(function (p) { o[p[0]] = p[1] }); return o })
    def(Object, "hasOwn", function (o, k) { return Object.prototype.hasOwnProperty.call(o, k) })
    def(Promise, "allSettled", function (l) {
        return Promise.all(Array.from(l).map(function (p) {
            return Promise.resolve(p).then(function (v) { return { status: "fulfilled", value: v } }, function (e) { return { status: "rejected", reason: e } })
        }))
    })
    def(Promise.prototype, "finally", function (fn) {
        return this.then(function (v) { return Promise.resolve(fn()).then(function () { return v }) },
                         function (e) { return Promise.resolve(fn()).then(function () { throw e }) })
    })
    // ES2025's Set methods.
    def(Set.prototype, "intersection", function (o) { var r = new Set(); this.forEach(function (x) { if (o.has(x)) r.add(x) }); return r })
    def(Set.prototype, "union", function (o) { var r = new Set(this); o.forEach(function (x) { r.add(x) }); return r })
    def(Set.prototype, "difference", function (o) { var r = new Set(); this.forEach(function (x) { if (!o.has(x)) r.add(x) }); return r })
    def(Set.prototype, "symmetricDifference", function (o) { var r = new Set(this); o.forEach(function (x) { if (r.has(x)) r.delete(x); else r.add(x) }); return r })
    def(Set.prototype, "isSubsetOf", function (o) { var ok = true; this.forEach(function (x) { if (!o.has(x)) ok = false }); return ok })
    def(Set.prototype, "isSupersetOf", function (o) { var me = this, ok = true; o.forEach(function (x) { if (!me.has(x)) ok = false }); return ok })
    def(Set.prototype, "isDisjointFrom", function (o) { var ok = true; this.forEach(function (x) { if (o.has(x)) ok = false }); return ok })
})()
