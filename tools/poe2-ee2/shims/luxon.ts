// luxon needs Intl, which Qt's JavaScript lacks: just "3 h ago".
class DT {
  constructor(private ms: number) {}
  static fromISO(s: string) { return new DT(Date.parse(s)); }
  toRelative(_o?: unknown) {
    if (isNaN(this.ms)) return null;
    const s = Math.max(0, Math.round((Date.now() - this.ms) / 1000));
    if (s < 60) return s + " sec. ago";
    if (s < 3600) return Math.round(s / 60) + " min. ago";
    if (s < 86400) return Math.round(s / 3600) + " hr. ago";
    const d = Math.round(s / 86400);
    return d + (d === 1 ? " day ago" : " days ago");
  }
}
export const DateTime = DT;
