const api = globalThis.browser ?? globalThis.chrome;
const params = new URLSearchParams(location.search);
document.getElementById("domain").textContent = params.get("domain") ?? "";
document.title = `Time Limit Reached — ${params.get("domain") ?? ""}`;
document.getElementById("close").addEventListener("click", async () => {
  const tab = await api.tabs.getCurrent();
  if (tab?.id) api.tabs.remove(tab.id);
});
