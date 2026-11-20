const api = globalThis.browser ?? globalThis.chrome;
const params = new URLSearchParams(location.search);
const domain = params.get("domain") ?? "";
const $ = (id) => document.getElementById(id);

$("domain").textContent = domain;
document.title = `Time Limit Reached — ${domain}`;
$("close").addEventListener("click", async () => {
  const tab = await api.tabs.getCurrent();
  if (tab?.id) api.tabs.remove(tab.id);
});

// Extra time: the background relays these to the Screen Limiter app, which decides.
let timeStatus = null;
let statusTimer = null;

function setStatus(text, error = false) {
  $("status").textContent = text;
  $("status").classList.toggle("error", error);
}

function ask(message) {
  api.runtime.sendMessage({ ...message, domain }).catch(() => {
    setStatus("Couldn't reach the Screen Limiter extension.", true);
  });
}

function showMenu() {
  $("main-actions").hidden = true;
  $("more").hidden = false;
  $("one-minute").hidden = !timeStatus.oneMinuteAvailable;
  $("enter-passcode").hidden = !timeStatus.passcodeRequired;
  $("choices").hidden = false;
  // Without a passcode there is nothing to enter: offer the durations straight away.
  $("durations").hidden = timeStatus.passcodeRequired;
  $("passcode-form").hidden = true;
}

function showPasscode() {
  $("choices").hidden = true;
  $("passcode-form").hidden = false;
  $("durations").hidden = false;
  $("passcode").value = "";
  $("passcode").focus();
}

function reset() {
  $("main-actions").hidden = false;
  $("more").hidden = true;
  setStatus("");
}

function request(option) {
  for (const button of document.querySelectorAll("#more button")) button.disabled = true;
  setStatus("Asking…");
  ask({ type: "requestTime", option, passcode: option === "oneMinute" ? null : $("passcode").value });
}

$("ask").addEventListener("click", () => {
  setStatus("Asking Screen Limiter…");
  ask({ type: "timeStatus" });
  // The app may still be launching; ask once more before giving up.
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => {
    ask({ type: "timeStatus" });
    statusTimer = setTimeout(() => setStatus("Screen Limiter isn't responding. Is the app running?", true), 3000);
  }, 1500);
});
$("one-minute").addEventListener("click", () => request("oneMinute"));
$("enter-passcode").addEventListener("click", showPasscode);
// Return shouldn't pick a duration for you.
$("passcode-form").addEventListener("submit", (event) => event.preventDefault());
for (const button of document.querySelectorAll("#durations button")) {
  button.addEventListener("click", () => request(button.dataset.option));
}
$("back").addEventListener("click", reset);

api.runtime.onMessage.addListener((message) => {
  if (message?.domain !== domain) return;
  for (const button of document.querySelectorAll("#more button")) button.disabled = false;
  if (message.type === "timeStatus") {
    clearTimeout(statusTimer);
    timeStatus = message;
    setStatus("");
    showMenu();
  } else if (message.type === "timeDenied") {
    clearTimeout(statusTimer);
    setStatus(message.reason ?? "Not allowed.", true);
    if (!$("passcode-form").hidden) $("passcode").select();
  } else if (message.type === "timeGranted") {
    const until = new Date(message.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    setStatus(`Extra time until ${until}. Reopening…`);
    // The background navigates this tab back to the site.
  }
});
