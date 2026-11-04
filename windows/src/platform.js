// Thin bridge to the Tauri backend. Falls back to browser APIs so the UI can be
// developed and tested in a normal browser.

const T = window.__TAURI__;
export const isTauri = !!(T && T.core);

export async function loadFile(name) {
  if (isTauri) return (await T.core.invoke("load_file", { name })) ?? null;
  try { return localStorage.getItem("exocalc:" + name); } catch { return null; }
}

export async function saveFile(name, content) {
  if (isTauri) return T.core.invoke("save_file", { name, content });
  try { localStorage.setItem("exocalc:" + name, content); } catch { /* ignore */ }
}

export async function fetchJSON(url) {
  if (isTauri) return JSON.parse(await T.core.invoke("fetch_json", { url }));
  const r = await fetch(url);
  return r.ok ? r.json() : null;
}

export async function hideWindow() { if (isTauri) await T.core.invoke("hide_window"); }
export async function setHotkey(accel) { if (isTauri) await T.core.invoke("set_hotkey", { accel }); }
export async function setAlwaysOnTop(on) { if (isTauri) await T.core.invoke("set_always_on_top", { on }); }
export async function setAutostart(on) { if (isTauri) await T.core.invoke("set_autostart", { on }); }
export async function getAutostart() { return isTauri ? !!(await T.core.invoke("get_autostart")) : false; }
export async function setTrayLabels(labels) { if (isTauri) await T.core.invoke("set_tray_labels", { labels }); }

export function onEvent(name, cb) {
  if (isTauri) T.event.listen(name, (e) => cb(e.payload));
}

export async function copyText(s) {
  try {
    await navigator.clipboard.writeText(s);
  } catch {
    const ta = document.createElement("textarea");
    ta.value = s;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
  }
}
