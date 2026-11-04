import { Engine, RateStore, L10n, tr, addStrings, resolveLang } from "./engine.js";
import * as P from "./platform.js";

// Windows-specific texts (keys differ from macOS: Ctrl instead of ⌘).
addStrings({
  stDefault: ["F1 — справка · {0} — показать/скрыть · Ctrl+, — настройки · курсы: {1}",
              "F1 — help · {0} — show/hide · Ctrl+, — settings · rates: {1}",
              "F1 — довідка · {0} — показати/сховати · Ctrl+, — налаштування · курси: {1}"],
  stResult: ["Клик по результату — копировать · Shift+клик или Ctrl+Shift+C — «выражение = результат» · Ctrl+Shift+A — весь лист",
             "Click a result to copy · Shift+click or Ctrl+Shift+C — “expression = result” · Ctrl+Shift+A — whole sheet",
             "Клік по результату — копіювати · Shift+клік або Ctrl+Shift+C — «вираз = результат» · Ctrl+Shift+A — весь аркуш"],
  cleared: ["Лист очищен (Ctrl+Z — вернуть, строки сохранены в истории)", "Sheet cleared (Ctrl+Z to undo, lines saved to history)",
            "Аркуш очищено (Ctrl+Z — повернути, рядки збережено в історії)"],
  fontSize: ["Размер (Ctrl+= / Ctrl+-)", "Size (Ctrl+= / Ctrl+-)", "Розмір (Ctrl+= / Ctrl+-)"],
  decimalsW: ["Знаков после запятой", "Decimal places", "Знаків після коми"],
  launchAtLogin: ["Запускать вместе с Windows", "Start with Windows", "Запускати разом з Windows"],
  hideOnDeactivate: ["Прятать окно при переходе в другое окно", "Hide when switching to another window", "Ховати вікно при переході в інше вікно"],
  btnHelp: ["Справка (F1)", "Help (F1)", "Довідка (F1)"],
  btnHistory: ["История (Ctrl+H)", "History (Ctrl+H)", "Історія (Ctrl+H)"],
  btnSettings: ["Настройки (Ctrl+,)", "Settings (Ctrl+,)", "Налаштування (Ctrl+,)"],
  tShiftClickKey: ["Shift+клик, Ctrl+Shift+C", "Shift+click, Ctrl+Shift+C", "Shift+клік, Ctrl+Shift+C"],
  tAltCKey: ["Ctrl+Shift+A", "Ctrl+Shift+A", "Ctrl+Shift+A"],
  tTab: ["дополнить слово (единицы, валюты, функции); ещё раз — следующий вариант", "complete a word (units, currencies, functions); press again for the next match", "доповнити слово (одиниці, валюти, функції); ще раз — наступний варіант"],
  tExamples: ["вставить примеры в лист", "insert examples into the sheet", "вставити приклади в аркуш"],
  tHelpComma: ["настройки: язык, разделители, знаки, шрифт, горячая клавиша", "settings: language, separators, decimals, font, hotkey", "налаштування: мова, роздільники, знаки, шрифт, гаряча клавіша"],
  clearAllQ: ["Очистить всю историю?", "Clear the whole history?", "Очистити всю історію?"],
  trayShow: ["Показать / скрыть", "Show / Hide", "Показати / сховати"],
  trayQuit: ["Выйти", "Quit", "Вийти"],
  copied: ["Скопировано: {0}", "Copied: {0}", "Скопійовано: {0}"],
});

const $ = (id) => document.getElementById(id);
const ta = $("ta"), hl = $("hl"), resultsEl = $("results"), wrap = $("wrap"), statusEl = $("status");

const rates = new RateStore();
const engine = new Engine(rates);
let results = [];
let lineStarts = [0];
let history = [];
let statusUntil = 0;

const settings = {
  language: "", decimalSeparator: ".", groupingSeparator: ",", decimals: 2, trimZeros: true,
  fontFamily: "", fontSize: 15, hotkey: "Ctrl+Alt+C", useNBU: true, showHints: true,
  alwaysOnTop: false, hideOnBlur: false,
};

// ───────────────────────── Persistence ─────────────────────────

async function loadJSON(name) {
  try { const s = await P.loadFile(name); return s ? JSON.parse(s) : null; } catch { return null; }
}
const saveJSON = (name, obj) => P.saveFile(name, JSON.stringify(obj)).catch(() => {});

let saveTimer = null;
function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveSheet, 700);
}
function saveSheet() {
  clearTimeout(saveTimer);
  saveJSON("sheet.json", { text: ta.value, selection: ta.selectionStart, scrollY: wrap.scrollTop });
}
const saveSettings = () => saveJSON("settings.json", settings);

// ───────────────────────── Evaluation & rendering ─────────────────────────

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function lineHTML(line, highlights) {
  if (!line.length) return "​";
  const kinds = new Array(line.length).fill(null);
  for (const h of highlights) {
    for (let i = Math.max(0, h.start); i < Math.min(line.length, h.end); i++) kinds[i] = h.kind;
  }
  let out = "", i = 0;
  while (i < line.length) {
    const k = kinds[i];
    let j = i + 1;
    while (j < line.length && kinds[j] === k) j++;
    const text = esc(line.slice(i, j));
    out += k ? `<span class="k-${k}">${text}</span>` : text;
    i = j;
  }
  return out;
}

const measureCtx = document.createElement("canvas").getContext("2d");
function textWidth(s) {
  const cs = getComputedStyle(ta);
  measureCtx.font = `500 ${cs.fontSize} ${cs.fontFamily}`;
  return measureCtx.measureText(s).width;
}

function recalc() {
  const text = ta.value;
  const lines = text.split("\n");
  lineStarts = [];
  let pos = 0;
  for (const l of lines) { lineStarts.push(pos); pos += l.length + 1; }
  results = engine.evaluate(lines, true);

  // result column width
  let maxW = 0;
  for (const r of results) if (r.display) maxW = Math.max(maxW, textWidth(r.display));
  const total = wrap.clientWidth || 700;
  let col = Math.ceil((maxW + 40) / 40) * 40;
  col = Math.min(Math.max(col, 120), Math.max(120, total * 0.55));
  document.documentElement.style.setProperty("--rescol", col + "px");

  hl.innerHTML = lines.map((l, i) => `<div class="ln">${lineHTML(l, results[i].highlights)}</div>`).join("");
  layout();
  updateStatus();
}

function layout() {
  const h = hl.offsetHeight;
  ta.style.height = Math.max(h, wrap.clientHeight) + "px";
  const divs = hl.children;
  let html = "";
  results.forEach((r, i) => {
    const d = divs[i];
    if (!d) return;
    const top = d.offsetTop;
    if (r.display) {
      html += `<div class="res" data-i="${i}" style="top:${top}px">${esc(r.display)}</div>`;
    } else if (r.error && settings.showHints && /\d/.test(ta.value.slice(lineStarts[i], (lineStarts[i + 1] ?? ta.value.length + 1) - 1))) {
      html += `<div class="res hint" style="top:${top}px">?</div>`;
    }
  });
  resultsEl.innerHTML = html;
}

function currentLine() {
  const p = ta.selectionStart;
  let idx = 0;
  for (let i = 0; i < lineStarts.length; i++) if (lineStarts[i] <= p) idx = i;
  return idx;
}

function lineText(i) {
  const lines = ta.value.split("\n");
  return lines[i] ?? "";
}

function expressionOf(i) {
  let expr = lineText(i);
  const c = expr.indexOf("//");
  if (c >= 0) expr = expr.slice(0, c);
  const eq = expr.lastIndexOf("=");
  if (eq > 0) { const before = expr.slice(0, eq).trim(); if (before) expr = before; }
  return expr.trim();
}

function ensureCaretVisible() {
  const d = hl.children[currentLine()];
  if (!d) return;
  const top = d.offsetTop, bottom = top + d.offsetHeight;
  if (top < wrap.scrollTop) wrap.scrollTop = top - 8;
  else if (bottom > wrap.scrollTop + wrap.clientHeight) wrap.scrollTop = bottom - wrap.clientHeight + 8;
}

// ───────────────────────── Status bar ─────────────────────────

function ratesTimeText() {
  if (!rates.updated) return tr("never");
  const d = new Date(rates.updated), now = new Date();
  const hm = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  return d.toDateString() === now.toDateString() ? hm : d.toLocaleDateString([], { day: "2-digit", month: "2-digit" }) + " " + hm;
}

function flashStatus(text) {
  statusUntil = Date.now() + 2500;
  statusEl.className = "ok";
  statusEl.textContent = text;
  setTimeout(updateStatus, 2600);
}

function updateStatus() {
  if (Date.now() < statusUntil) return;
  const i = currentLine(), r = results[i];
  if (r && r.error && settings.showHints && lineText(i).trim()) {
    statusEl.className = "err"; statusEl.textContent = "⚠ " + r.error; return;
  }
  statusEl.className = "";
  statusEl.textContent = r && r.display ? tr("stResult") : tr("stDefault", settings.hotkey, ratesTimeText());
}

// ───────────────────────── Copy, history, editing ─────────────────────────

async function copyLine(i, full) {
  const r = results[i];
  if (!r || !r.display) return;
  const s = full ? `${expressionOf(i)} = ${r.display}` : r.display;
  await P.copyText(s);
  flashStatus(tr("copied", s));
  const el = resultsEl.querySelector(`.res[data-i="${i}"]`);
  if (el) { el.classList.add("flash"); setTimeout(() => el.classList.remove("flash"), 350); }
}

async function copyAll() {
  const out = ta.value.split("\n").map((l, i) => (results[i] && results[i].display ? `${expressionOf(i)} = ${results[i].display}` : l.trim()));
  await P.copyText(out.join("\n"));
  flashStatus(tr("copiedAll"));
}

function addHistory(i) {
  const r = results[i];
  if (!r || !r.display) return;
  const expr = expressionOf(i);
  if (!expr) return;
  if (history[0] && history[0].expr === expr && history[0].result === r.display) return;
  history = history.filter((h) => !(h.expr === expr && h.result === r.display));
  history.unshift({ id: crypto.randomUUID(), date: Date.now(), expr, result: r.display });
  if (history.length > 2000) history.length = 2000;
  saveJSON("history.json", history);
}

/** Replace a range keeping native undo (Ctrl+Z). */
function replaceRange(start, end, text) {
  ta.focus();
  ta.setSelectionRange(start, end);
  if (!document.execCommand("insertText", false, text)) ta.setRangeText(text, start, end, "end");
  onInput();
}

function insertLine(s) {
  let text = s;
  if (ta.value.length && !ta.value.endsWith("\n")) text = "\n" + s;
  replaceRange(ta.value.length, ta.value.length, text);
  ensureCaretVisible();
}

function clearSheet() {
  results.forEach((_, i) => addHistory(i));
  replaceRange(0, ta.value.length, "");
  flashStatus(tr("cleared"));
}

let completion = null;   // {start, list, idx}
function complete() {
  const p = ta.selectionStart;
  if (completion && completion.end === p) {
    completion.idx = (completion.idx + 1) % completion.list.length;
  } else {
    const before = ta.value.slice(0, p);
    const m = before.match(/[\p{L}_°µ][\p{L}\p{N}_²³]*$/u);
    if (!m) return false;
    const list = engine.completions(m[0]);
    if (!list.length) return false;
    completion = { start: p - m[0].length, list, idx: 0, end: p };
  }
  const word = completion.list[completion.idx];
  replaceRange(completion.start, completion.end, word);
  completion.end = completion.start + word.length;
  return true;
}

function onInput() {
  recalc();
  ensureCaretVisible();
  scheduleSave();
}

// ───────────────────────── Examples (first run) ─────────────────────────

function welcomeLines() {
  const hk = settings.hotkey;
  if (L10n.lang === "ru") return [
    "# Добро пожаловать в ExoCalc! Пишите выражение — ответ появится справа.",
    `# F1 — справка · Esc — спрятать · ${hk} — вызвать из любого окна`,
    "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
    "# Проценты", "20% от 1500", "1500 - 20%", "",
    "# Валюты (курсы обновляются сами)", "600 долларов в гривнах", "100 евро в грн", "0.01 btc в usd", "",
    "# Единицы измерения", "18 цельсия в фаренгейтах", "100 км в милях", "1 галлон в литрах", "70 кг в фунтах", "",
    "# Числа в любом формате", "300 000,00 * 2", "300,000.00 * 2", "685,00 - ,99", "",
    "# Переменные и итоги", "цена = 1250", "цена * 3", "",
    "Аренда: 2000", "Свет: 150", "итого",
  ];
  if (L10n.lang === "uk") return [
    "# Ласкаво просимо до ExoCalc! Пишіть вираз — відповідь з’явиться праворуч.",
    `# F1 — довідка · Esc — сховати · ${hk} — викликати з будь-якого вікна`,
    "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
    "# Відсотки", "20% від 1500", "1500 - 20%", "",
    "# Валюти (курси оновлюються самі)", "600 доларів у гривнях", "100 євро у грн", "0.01 btc у usd", "",
    "# Одиниці виміру", "18 цельсія у фаренгейтах", "100 км у милях", "1 галон у літрах", "70 кг у фунтах", "",
    "# Числа в будь-якому форматі", "300 000,00 * 2", "300,000.00 * 2", "685,00 - ,99", "",
    "# Змінні та підсумки", "ціна = 1250", "ціна * 3", "",
    "Оренда: 2000", "Світло: 150", "разом",
  ];
  return [
    "# Welcome to ExoCalc! Type an expression — the answer appears on the right.",
    `# F1 — help · Esc — hide · ${hk} — open from any window`,
    "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
    "# Percentages", "20% of 1500", "1500 - 20%", "",
    "# Currencies (rates update automatically)", "600 usd in uah", "100 eur in usd", "0.01 btc in usd", "",
    "# Units", "18 celsius in fahrenheit", "100 km in miles", "1 gallon in liters", "70 kg in lb", "",
    "# Numbers in any format", "300 000,00 * 2", "300,000.00 * 2", "685,00 - ,99", "",
    "# Variables and totals", "price = 1250", "price * 3", "",
    "Rent: 2000", "Power: 150", "total",
  ];
}

function welcomeText() {
  const lines = welcomeLines();
  const res = engine.evaluate(lines);
  return lines.map((l, i) => {
    const t = l.trim();
    if (!t || t.startsWith("#") || t.includes("=") || /^\p{L}+$/u.test(t) || !res[i].display) return l;
    return `${l} = ${res[i].display}`;
  }).join("\n");
}

// ───────────────────────── Panels: help, history, settings ─────────────────────────

let panel = null;
function openPanel(kind) {
  if (panel === kind) { closePanel(); return; }
  panel = kind;
  $("modal").hidden = false;
  $("panelTitle").textContent = tr(kind === "help" ? "helpTitle" : kind === "history" ? "historyTitle" : "settingsTitle");
  renderPanel();
}
function closePanel() {
  panel = null;
  $("modal").hidden = true;
  stopRecording();
  ta.focus();
}
function renderPanel() {
  const body = $("panelBody");
  if (panel === "help") body.innerHTML = helpHTML();
  else if (panel === "history") renderHistory(body);
  else if (panel === "settings") renderSettings(body);
}

function helpSections() {
  const ru = L10n.lang === "ru", uk = L10n.lang === "uk";
  const conv = ru ? "в" : uk ? "у" : "in";
  return [
    [tr("hArith"), ["2 + 3 * 4", "(2 + 3) * 4", "2^10", "10 mod 3", "5!", "800 * 12", "800x12", "1/3"]],
    [tr("hNumbers"), ["300,000.00 * 2", "300 000,00 * 2", "30000,00 * 8", "685,00 - ,99", "1.5 + 1,5"]],
    [tr("hPercent"), ["100 + 15%", "250 - 20%", ru ? "15% от 800" : uk ? "15% від 800" : "15% of 800", "20% off 1500", "5% on 200"]],
    [tr("hFunc"), ["sqrt(144)", "sqrt 2", "sin(30 deg)", "cos(pi)", "log(1000)", "round(3.14159; 1)", "max(3; 9; 4)", "avg(10; 20; 60)", "2 pi"]],
    [tr("hCurrency"), ru ? ["600 долларов в гривнах", "$20 + €15", "100 евро в грн", "1000 грн в долларах", "0.05 btc в usd", "1 eth в гривнах"]
      : uk ? ["600 доларів у гривнях", "$20 + €15", "100 євро у грн", "1000 грн у доларах", "0.05 btc у usd", "1 eth у гривнях"]
      : ["600 usd in uah", "$20 + €15", "100 eur in uah", "1000 uah in usd", "0.05 btc in usd", "1 eth in uah"]],
    [tr("hUnits"), ru ? ["18 цельсия в фаренгейтах", "100 км в милях", "5 футов в см", "70 кг в фунтах", "1.5 часа в минутах", "1 GB в MB", "120 км / 1.5 ч", "10 соток в м2"]
      : uk ? ["18 цельсія у фаренгейтах", "100 км у милях", "5 футів у см", "70 кг у фунтах", "1.5 години у хвилинах", "1 GB у MB", "120 км / 1.5 години"]
      : ["18 celsius in fahrenheit", "100 km in miles", "5 ft in cm", "70 kg in lb", "1.5 hours in minutes", "1 GB in MB", "120 km / 1.5 h"]],
    [tr("hBases"), [`255 ${conv} hex`, "0xFF + 1", `10 ${conv} bin`, ru ? "5k + 2.5 млн" : uk ? "5k + 2.5 мільйон" : "5k + 2.5 million", `1234567 ${conv} sci`]],
    [tr("hVars"), ru ? ["цена = 1250", "кол = 3", "цена * кол", "пред + 100"] : uk ? ["ціна = 1250", "кількість = 3", "ціна * кількість", "попер + 100"] : ["price = 1250", "qty = 3", "price * qty", "prev + 100"]],
    [tr("hTotals"), ru ? ["Аренда: 2000", "Свет: 150", "Интернет: 30", "итого"] : uk ? ["Оренда: 2000", "Світло: 150", "Інтернет: 30", "разом"] : ["Rent: 2000", "Power: 150", "Internet: 30", "total"]],
  ];
}

function helpHTML() {
  let h = `<p class="muted">${esc(tr("helpIntro"))}</p>`;
  for (const [title, lines] of helpSections()) {
    const res = engine.evaluate(lines);
    h += `<div class="sec">${esc(title)}</div>`;
    lines.forEach((l, i) => {
      const r = res[i];
      const out = r.display ? `<span class="r">${esc(r.display)}</span>` : r.error ? `<span class="r e">⚠ ${esc(r.error)}</span>` : "";
      h += `<div class="ex" data-ex="${esc(l)}"><span>${esc(l)}</span>${out}</div>`;
    });
  }
  const tips = [
    [settings.hotkey, tr("tHotkey")], ["Esc", tr("tEsc")], [tr("tClickKey"), tr("tClick")],
    [tr("tShiftClickKey"), tr("tShiftClick")], [tr("tAltCKey"), tr("tAltC")], ["Ctrl+K", tr("tK")], ["Ctrl+H", tr("tY")],
    ["Tab", tr("tTab")], ["Ctrl+Shift+E", tr("tExamples")], ["Ctrl+= / Ctrl+- / Ctrl+0", tr("tFont")], ["Ctrl+R", tr("tR")],
    ["Ctrl+,", tr("tHelpComma")], [tr("tConvKey"), tr("tConv")], [tr("tCommentKey"), tr("tComment")],
    [tr("tTotalsKey"), tr("tTotals")], [";", tr("tArgs")],
  ];
  h += `<div class="sec">${esc(tr("hKeys"))}</div><div class="tips">`;
  for (const [k, v] of tips) h += `<span class="k">${esc(k)}</span><span>${esc(v)}</span>`;
  return h + "</div>";
}

function renderHistory(body) {
  const q = body.querySelector("#hq")?.value ?? "";
  const list = q ? history.filter((h) => `${h.expr} = ${h.result}`.toLowerCase().includes(q.toLowerCase())) : history;
  const fmt = (t) => new Date(t).toLocaleString([], { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  let rows = list.slice(0, 500).map((h) => `<div class="hrow" data-id="${h.id}" title="${esc(tr("insertToSheet"))}">
      <span class="e">${esc(h.expr)}</span><span class="r">= ${esc(h.result)}</span><span class="d">${fmt(h.date)}</span>
      <button class="icon" data-copy="${h.id}" title="${esc(tr("copy"))}">⧉</button>
      <button class="icon" data-del="${h.id}" title="${esc(tr("delete"))}">✕</button></div>`).join("");
  if (!body.querySelector("#hq")) {
    body.innerHTML = `<div class="hist-top"><input id="hq" type="search" placeholder="${esc(tr("searchHistory"))}">
      <button class="btn" id="hclear">${esc(tr("clearAll"))}</button></div><div class="hist" id="hlist"></div>
      <p class="muted" id="hcount"></p>`;
    body.querySelector("#hq").addEventListener("input", () => renderHistory(body));
    body.querySelector("#hclear").addEventListener("click", () => {
      if (history.length && confirm(tr("clearAllQ"))) { history = []; saveJSON("history.json", history); renderHistory(body); }
    });
    body.querySelector("#hlist").addEventListener("click", async (e) => {
      const c = e.target.closest("[data-copy]"), d = e.target.closest("[data-del]"), row = e.target.closest(".hrow");
      if (c) { const h = history.find((x) => x.id === c.dataset.copy); if (h) { await P.copyText(`${h.expr} = ${h.result}`); flashStatus(tr("copied", `${h.expr} = ${h.result}`)); } return; }
      if (d) { history = history.filter((x) => x.id !== d.dataset.del); saveJSON("history.json", history); renderHistory(body); return; }
      if (row) { const h = history.find((x) => x.id === row.dataset.id); if (h) { closePanel(); insertLine(h.expr); } }
    });
    return renderHistory(body);
  }
  body.querySelector("#hlist").innerHTML = rows;
  body.querySelector("#hcount").textContent = tr("historyCount", list.length).replace(/ · .*/, "");
}

let recording = false;
function stopRecording() { recording = false; }

function accelFromEvent(e) {
  const mods = [];
  if (e.ctrlKey) mods.push("Ctrl");
  if (e.altKey) mods.push("Alt");
  if (e.shiftKey) mods.push("Shift");
  if (e.metaKey) mods.push("Super");
  const c = e.code;
  let key = null;
  if (/^Key[A-Z]$/.test(c)) key = c.slice(3);
  else if (/^Digit\d$/.test(c)) key = c.slice(5);
  else if (/^F\d{1,2}$/.test(c)) key = c;
  else key = { Space: "Space", Equal: "=", Minus: "-", Backquote: "`", Comma: ",", Period: ".", Slash: "/", Semicolon: ";", Quote: "'", BracketLeft: "[", BracketRight: "]", Backslash: "\\" }[c] || null;
  if (!key) return null;
  if (!mods.length && !/^F\d/.test(key)) return null;
  return [...mods, key].join("+");
}

function renderSettings(body) {
  const s = settings;
  const fonts = ["Cascadia Mono", "Cascadia Code", "Consolas", "JetBrains Mono", "Fira Code", "Courier New", "Lucida Console"];
  const opt = (v, label, cur) => `<option value="${esc(v)}" ${v === cur ? "selected" : ""}>${esc(label)}</option>`;
  const chk = (id, label, on) => `<div class="row"><label for="${id}">${esc(label)}</label><input type="checkbox" id="${id}" ${on ? "checked" : ""}></div>`;
  body.innerHTML = `
    <div class="group">${esc(tr("behavior"))}</div>
    <div class="row"><label>${esc(tr("language"))}</label><select id="sLang">
      ${opt("", tr("langSystem"), s.language)}${opt("ru", "Русский", s.language)}${opt("uk", "Українська", s.language)}${opt("en", "English", s.language)}</select></div>
    <div class="row"><label>${esc(tr("hotkey"))}</label><button class="btn" id="sHotkey">${esc(s.hotkey)}</button></div>
    ${chk("sAuto", tr("launchAtLogin"), false)}
    ${chk("sTop", tr("alwaysOnTop"), s.alwaysOnTop)}
    ${chk("sBlur", tr("hideOnDeactivate"), s.hideOnBlur)}
    ${chk("sHints", tr("showHints"), s.showHints)}
    <div class="group">${esc(tr("numbers"))}</div>
    <div class="row"><label>${esc(tr("decimalSep"))}</label><select id="sDec">${opt(".", tr("dot"), s.decimalSeparator)}${opt(",", tr("comma"), s.decimalSeparator)}</select></div>
    <div class="row"><label>${esc(tr("groupSep"))}</label><select id="sGroup">
      ${opt("", tr("gNone"), s.groupingSeparator)}${opt(" ", tr("gSpace"), s.groupingSeparator)}${opt(",", tr("gComma"), s.groupingSeparator)}${opt(".", tr("gDot"), s.groupingSeparator)}${opt("'", tr("gApos"), s.groupingSeparator)}</select></div>
    <div class="row"><label>${esc(tr("decimalsW"))}</label><input type="number" id="sDecimals" min="0" max="10" value="${s.decimals}"></div>
    ${chk("sTrim", tr("trimZeros"), s.trimZeros)}
    <p class="muted">${esc(tr("inputNote"))}</p>
    <div class="row"><label>${esc(tr("example"))}</label><span id="sPreview" style="color:var(--res);font-family:var(--font)"></span></div>
    <div class="group">${esc(tr("font"))}</div>
    <div class="row"><label>${esc(tr("font"))}</label><input type="text" id="sFont" list="fontList" placeholder="Cascadia Mono" value="${esc(s.fontFamily)}">
      <datalist id="fontList">${fonts.map((f) => `<option value="${esc(f)}">`).join("")}</datalist></div>
    <div class="row"><label>${esc(tr("fontSize"))}</label><input type="number" id="sSize" min="10" max="40" value="${s.fontSize}"></div>
    <div class="group">${esc(tr("rates"))}</div>
    ${chk("sNBU", tr("useNBU"), s.useNBU)}
    <div class="row"><label id="sRates">${esc(ratesStatusText())}</label><button class="btn" id="sRefresh">${esc(tr("refreshNow"))}</button></div>
    <p class="muted">${esc(tr("ratesSources"))}</p>`;
  const preview = () => { $("sPreview").textContent = engine.number(1234567.5, s.decimals) + "   ·   " + engine.number(0.125, s.decimals); };
  preview();
  P.getAutostart().then((on) => { const el = $("sAuto"); if (el) el.checked = on; });

  const changed = () => { applySettings(); saveSettings(); preview(); };
  $("sLang").onchange = (e) => { s.language = e.target.value; changed(); renderPanel(); };
  $("sDec").onchange = (e) => { s.decimalSeparator = e.target.value; if (s.groupingSeparator === s.decimalSeparator) { s.groupingSeparator = s.decimalSeparator === "," ? " " : ","; $("sGroup").value = s.groupingSeparator; } changed(); };
  $("sGroup").onchange = (e) => { s.groupingSeparator = e.target.value; if (s.groupingSeparator === s.decimalSeparator) { s.groupingSeparator = s.decimalSeparator === "," ? " " : ","; e.target.value = s.groupingSeparator; } changed(); };
  $("sDecimals").oninput = (e) => { s.decimals = Math.max(0, Math.min(10, parseInt(e.target.value) || 0)); changed(); };
  $("sTrim").onchange = (e) => { s.trimZeros = e.target.checked; changed(); };
  $("sFont").oninput = (e) => { s.fontFamily = e.target.value.trim(); changed(); };
  $("sSize").oninput = (e) => { s.fontSize = Math.max(10, Math.min(40, parseInt(e.target.value) || 15)); changed(); };
  $("sTop").onchange = (e) => { s.alwaysOnTop = e.target.checked; P.setAlwaysOnTop(s.alwaysOnTop); saveSettings(); };
  $("sBlur").onchange = (e) => { s.hideOnBlur = e.target.checked; saveSettings(); };
  $("sHints").onchange = (e) => { s.showHints = e.target.checked; changed(); };
  $("sAuto").onchange = (e) => { P.setAutostart(e.target.checked).catch(() => { e.target.checked = !e.target.checked; }); };
  $("sNBU").onchange = (e) => { s.useNBU = e.target.checked; rates.setUseNBU(s.useNBU); changed(); $("sRates").textContent = ratesStatusText(); };
  $("sRefresh").onclick = () => refreshRates(true);
  $("sHotkey").onclick = (e) => {
    recording = !recording;
    e.target.classList.toggle("rec", recording);
    e.target.textContent = recording ? tr("pressKeys") : s.hotkey;
  };
}

document.addEventListener("keydown", async (e) => {
  if (!recording) return;
  e.preventDefault();
  e.stopPropagation();
  const btn = $("sHotkey");
  if (e.key === "Escape") { recording = false; if (btn) { btn.classList.remove("rec"); btn.textContent = settings.hotkey; } return; }
  const accel = accelFromEvent(e);
  if (!accel) return;
  recording = false;
  const old = settings.hotkey;
  try {
    await P.setHotkey(accel);
    settings.hotkey = accel;
    saveSettings();
  } catch {
    await P.setHotkey(old).catch(() => {});
    flashStatus(tr("hotkeyBusy", accel));
  }
  if (btn) { btn.classList.remove("rec"); btn.textContent = settings.hotkey; }
  updateStatus();
}, true);

// ───────────────────────── Settings application ─────────────────────────

function applySettings() {
  L10n.lang = resolveLang(settings.language, navigator.languages || []);
  document.documentElement.lang = L10n.lang;
  engine.settings = {
    decimalSeparator: settings.decimalSeparator, groupingSeparator: settings.groupingSeparator,
    decimals: settings.decimals, trimZeros: settings.trimZeros,
  };
  const root = document.documentElement.style;
  root.setProperty("--size", settings.fontSize + "px");
  if (settings.fontFamily) root.setProperty("--font", `"${settings.fontFamily}", "Cascadia Mono", Consolas, monospace`);
  else root.removeProperty("--font");
  $("btnHelp").title = tr("btnHelp");
  $("btnHistory").title = tr("btnHistory");
  $("btnSettings").title = tr("btnSettings");
  P.setTrayLabels([tr("trayShow"), tr("settings…"), tr("trayQuit")]).catch(() => {});
  recalc();
}

function ratesStatusText() {
  let s = rates.updated ? tr("ratesUpdated", ratesTimeText()) : tr("ratesNotLoaded");
  if (settings.useNBU && rates.nbuDate) s += " · " + tr("nbuOn", rates.nbuDate);
  const r = rates.rate("USD", "UAH");
  if (r) s += ` · 1 USD = ${engine.number(r, 4)} UAH`;
  return s;
}

let refreshing = false;
async function refreshRates(manual = false) {
  if (refreshing) return;
  refreshing = true;
  if (manual && $("sRates")) $("sRates").textContent = tr("updating");
  const ok = await rates.refresh(P.fetchJSON).catch(() => false);
  refreshing = false;
  if (ok) saveJSON("rates.json", rates.toJSON());
  else if (manual) flashStatus(tr("ratesFailed"));
  if ($("sRates")) $("sRates").textContent = ratesStatusText();
  recalc();
}

// ───────────────────────── Events ─────────────────────────

ta.addEventListener("input", () => { completion = null; onInput(); });
ta.addEventListener("keyup", updateStatus);
ta.addEventListener("click", updateStatus);
ta.addEventListener("scroll", () => { ta.scrollTop = 0; });
new ResizeObserver(() => { recalc(); }).observe(wrap);

resultsEl.addEventListener("mousedown", (e) => {
  const el = e.target.closest(".res[data-i]");
  if (!el) return;
  e.preventDefault();
  copyLine(Number(el.dataset.i), e.shiftKey || e.ctrlKey);
});

$("btnHelp").onclick = () => openPanel("help");
$("btnHistory").onclick = () => openPanel("history");
$("btnSettings").onclick = () => openPanel("settings");
$("panelClose").onclick = closePanel;
$("modal").addEventListener("mousedown", (e) => { if (e.target.id === "modal") closePanel(); });
$("panelBody").addEventListener("click", (e) => {
  const ex = e.target.closest(".ex");
  if (ex) { closePanel(); insertLine(ex.dataset.ex); }
});

document.addEventListener("keydown", (e) => {
  if (recording) return;
  const ctrl = e.ctrlKey && !e.altKey;
  const k = e.key;
  // Block browser shortcuts (reload, print, find, zoom…)
  if (k === "F5" || (ctrl && ["r", "R", "p", "P", "f", "F", "g", "G", "j", "J", "u", "U"].includes(k) && !e.shiftKey) || (ctrl && e.shiftKey && (k === "I" || k === "R"))) {
    e.preventDefault();
    if (ctrl && (k === "r" || k === "R")) refreshRates(true);
    return;
  }
  if (k === "F1" || (ctrl && k === "/")) { e.preventDefault(); openPanel("help"); return; }
  if (k === "Escape") { e.preventDefault(); if (panel) closePanel(); else { addHistory(currentLine()); saveSheet(); P.hideWindow(); } return; }
  if (ctrl && k === ",") { e.preventDefault(); openPanel("settings"); return; }
  if (ctrl && (k === "h" || k === "H") && !e.shiftKey) { e.preventDefault(); openPanel("history"); return; }
  if (ctrl && e.shiftKey && e.code === "KeyC") { e.preventDefault(); copyLine(currentLine(), true); return; }
  if (ctrl && e.shiftKey && e.code === "KeyA") { e.preventDefault(); copyAll(); return; }
  if (ctrl && e.shiftKey && e.code === "KeyE") { e.preventDefault(); closePanel(); insertLine("\n" + welcomeText()); return; }
  if (ctrl && (k === "k" || k === "K") && !e.shiftKey) { e.preventDefault(); clearSheet(); return; }
  if (ctrl && (k === "=" || k === "+")) { e.preventDefault(); settings.fontSize = Math.min(40, settings.fontSize + 1); applySettings(); saveSettings(); return; }
  if (ctrl && k === "-") { e.preventDefault(); settings.fontSize = Math.max(10, settings.fontSize - 1); applySettings(); saveSettings(); return; }
  if (ctrl && k === "0") { e.preventDefault(); settings.fontSize = 15; applySettings(); saveSettings(); return; }
  if (document.activeElement !== ta || panel) return;
  if (k === "Tab" && !e.shiftKey) { if (complete()) e.preventDefault(); else { e.preventDefault(); replaceRange(ta.selectionStart, ta.selectionEnd, "    "); } return; }
  if (k === "Enter") addHistory(currentLine());
});

window.addEventListener("blur", () => {
  saveSheet();
  if (settings.hideOnBlur && P.isTauri) setTimeout(() => { if (!document.hasFocus()) P.hideWindow(); }, 150);
});
document.addEventListener("contextmenu", (e) => { if (e.target !== ta) e.preventDefault(); });

P.onEvent("shown", () => { ta.focus(); recalc(); });
P.onEvent("open-settings", () => openPanel("settings"));
P.onEvent("open-help", () => openPanel("help"));

// ───────────────────────── Startup ─────────────────────────

(async function start() {
  const st = await loadJSON("settings.json");
  if (st) Object.assign(settings, st);
  rates.useNBU = settings.useNBU;
  rates.load(await loadJSON("rates.json"));
  history = (await loadJSON("history.json")) || [];
  applySettings();

  const sheet = await loadJSON("sheet.json");
  if (sheet && typeof sheet.text === "string") {
    ta.value = sheet.text;
    recalc();
    const p = Math.min(sheet.selection || 0, ta.value.length);
    ta.setSelectionRange(p, p);
    requestAnimationFrame(() => { wrap.scrollTop = sheet.scrollY || 0; });
  } else {
    if (rates.isStale) await Promise.race([refreshRates(), new Promise((r) => setTimeout(r, 4000))]);
    ta.value = welcomeText();
    recalc();
    ta.setSelectionRange(ta.value.length, ta.value.length);
  }
  ta.focus();

  P.setHotkey(settings.hotkey).catch(() => flashStatus(tr("hotkeyBusy", settings.hotkey)));
  if (settings.alwaysOnTop) P.setAlwaysOnTop(true);
  if (rates.isStale) refreshRates();
  setInterval(() => { if (rates.isStale) refreshRates(); }, 30 * 60 * 1000);
})();
