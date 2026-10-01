// Reports the active tab to the Screen Limiter Mac app (via the native host),
// and redirects tabs the app says Screen Time has blocked.

const HOST = "dev.screenlimiter.host";
// Firefox's promise-based `browser` namespace; Chrome's `chrome` (promise-based in MV3).
const api = globalThis.browser ?? globalThis.chrome;
const BROWSER = globalThis.browser?.runtime?.getBrowserInfo ? "firefox" : "chrome";
const BLOCKED_PAGE = api.runtime.getURL("blocked.html");

let port = null;
let idleState = "active";
let lastSent = "";

function connect() {
  if (port) return;
  try {
    port = api.runtime.connectNative(HOST);
  } catch (error) {
    console.warn("connectNative failed", error);
    port = null;
    return;
  }
  port.onMessage.addListener(onHostMessage);
  port.onDisconnect.addListener(() => {
    console.warn("Native host disconnected", api.runtime.lastError?.message);
    port = null;
    lastSent = "";
  });
  report(true);
}

async function currentState() {
  const win = await api.windows.getLastFocused().catch(() => null);
  const [tab] = await api.tabs.query({ active: true, lastFocusedWindow: true });
  return {
    type: "tab",
    browser: BROWSER,
    url: tab?.url ?? null,
    title: tab?.title ?? null,
    tabId: tab?.id ?? null,
    windowFocused: Boolean(win?.focused),
    audible: Boolean(tab?.audible),
    idle: idleState,
  };
}

async function report(force = false) {
  connect();
  if (!port) return;
  const state = await currentState();
  const key = JSON.stringify(state);
  if (!force && key === lastSent) return;
  lastSent = key;
  port.postMessage(state);
}

function hostOf(url) {
  try {
    return new URL(url).hostname.replace(/^(www|m|mobile)\./, "");
  } catch {
    return null;
  }
}

async function onHostMessage(message) {
  if (message?.type === "hello") {
    report(true);
    return;
  }
  if (message?.type !== "blocked") return;
  const domain = message.domain ?? hostOf(message.url);
  const tabs = await api.tabs.query({});
  for (const tab of tabs) {
    if (!tab.url || hostOf(tab.url) !== domain) continue;
    const target = `${BLOCKED_PAGE}?domain=${encodeURIComponent(domain)}&url=${encodeURIComponent(tab.url)}`;
    api.tabs.update(tab.id, { url: target });
  }
}

api.tabs.onActivated.addListener(() => report());
api.tabs.onUpdated.addListener((_id, change) => {
  if (change.url || change.audible !== undefined || change.status === "complete") report();
});
api.windows.onFocusChanged.addListener(() => report());
api.idle.setDetectionInterval(60);
api.idle.onStateChanged.addListener((state) => {
  idleState = state;
  report();
});

// Heartbeat: keeps the app's "connected" state fresh and reconnects if needed.
api.alarms.create("heartbeat", { periodInMinutes: 0.5 });
api.alarms.onAlarm.addListener(() => report(true));
api.runtime.onStartup.addListener(() => report(true));
api.runtime.onInstalled.addListener(() => report(true));

report(true);
