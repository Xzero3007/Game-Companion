// What Game Companion hands the kit (EE2.setup): requests, timers, data files.
export interface HostApi {
  request(url: string, method: string, body: string): Promise<{ status: number; headers: Record<string, string>; body: string }>;
  timer(ms: number, cb: () => void): number;
  cancel(id: number): void;
  readData(path: string): string;
  log(text: string): void;
}
export const host: HostApi = {
  request: () => Promise.reject(new Error("no host")),
  timer: () => 0,
  cancel: () => {},
  readData: () => "",
  log: () => {},
};
export function setHost(h: HostApi) { Object.assign(host, h); }
