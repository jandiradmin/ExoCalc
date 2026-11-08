// ExoCalc engine — JavaScript port of the macOS ExoCalcCore (Swift).
// Pure ES module: runs in the app (WebView2) and in Node for tests.

import { UNIT_DEFS, CURRENCY_ALIASES, CRYPTO_IDS, COMMON_CODES, STRINGS } from "./data.js";
import { daysFromCivil, civilFromDays, validDate, addMonths, weekday, MONTHS, DAY_WORDS, NOW_WORDS, UNTIL_WORDS, ZONES, localTz, tzOffset } from "./datetime.js";

// ───────────────────────── Localization ─────────────────────────

export const L10n = { lang: "ru" };
const LANG_INDEX = { ru: 0, en: 1, uk: 2 };

export function resolveLang(code, preferred = []) {
  if (code === "ru" || code === "en" || code === "uk") return code;
  for (const p of preferred) {
    if (p.startsWith("uk")) return "uk";
    if (p.startsWith("ru")) return "ru";
    if (p.startsWith("en")) return "en";
  }
  return "en";
}

const extraStrings = {};
export function addStrings(table) { Object.assign(extraStrings, table); }

export function tr(key, ...args) {
  const row = extraStrings[key] || STRINGS[key];
  if (!row) return key;
  let s = row[LANG_INDEX[L10n.lang] ?? 0];
  args.forEach((a, i) => { s = s.split(`{${i}}`).join(String(a)); });
  return s;
}

export class CalcError extends Error {}

// ───────────────────────── Units ─────────────────────────

export function makeUnit(id, dim, factor, offset = 0, isCrypto = false) {
  return { id, dim, factor, offset, isCrypto };
}
const sameUnit = (a, b) => a.id === b.id && a.dim === b.dim;

const ENDINGS = [
  "ами", "ями", "ією", "ах", "ях", "ов", "ев", "ей", "ів", "їв", "ам", "ям", "ом", "ем", "ою", "ею",
  "ий", "ій", "ия", "ія", "ию", "ію", "ые", "ых", "и", "ы", "і", "а", "я", "у", "ю", "е", "є", "о", "ь", "й",
];
const hasCyrillic = (s) => /[Ѐ-ӿ]/.test(s);
function stem(s) {
  return s.toLowerCase().split(" ").filter((p) => p.length).map((w) => {
    if ([...w].length < 4 || !hasCyrillic(w)) return w;
    for (const e of ENDINGS) {
      if (w.endsWith(e) && [...w].length - [...e].length >= 3) return w.slice(0, w.length - e.length);
    }
    return w;
  }).join(" ");
}
const isCodeLike = (s) => /^[A-Za-z]{3,5}$/.test(s);

export class RateStore {
  constructor() {
    this.market = {}; this.nbu = {}; this.crypto = {};
    this.updated = null; this.nbuDate = null;
    this.useNBU = true;
    this.lastAttempt = 0;
    this.perUSD = { USD: 1 };
  }
  knows(code) { return this.perUSD[code] !== undefined || COMMON_CODES.includes(code) || CRYPTO_IDS[code] !== undefined; }
  get isStale() {
    if (this.lastAttempt && Date.now() - this.lastAttempt < 5 * 60 * 1000) return false;
    if (!this.updated) return true;
    if (!Object.keys(this.crypto).length || !Object.keys(this.market).length) return true;
    return Date.now() - this.updated > 4 * 3600 * 1000;
  }
  rate(from, to) {
    const a = this.perUSD[from], b = this.perUSD[to];
    return a > 0 && b !== undefined ? b / a : null;
  }
  setUseNBU(v) { if (this.useNBU !== v) { this.useNBU = v; this.rebuild(); } }
  setTestRates(r) { this.market = { ...r }; this.nbu = {}; this.crypto = {}; this.rebuild(); }
  rebuild() {
    const r = { ...this.market };
    const usd = this.nbu.USD;
    if (this.useNBU && usd > 0) {
      r.UAH = usd;
      for (const [code, uahPer] of Object.entries(this.nbu)) if (uahPer > 0 && code !== "UAH") r[code] = usd / uahPer;
    }
    for (const [code, price] of Object.entries(this.crypto)) if (price > 0) r[code] = 1 / price;
    r.USD = 1;
    this.perUSD = r;
  }
  toJSON() {
    return { market: this.market, nbu: this.nbu, crypto: this.crypto, updated: this.updated, nbuDate: this.nbuDate };
  }
  load(obj) {
    if (!obj) return;
    this.market = obj.market || {}; this.nbu = obj.nbu || {}; this.crypto = obj.crypto || {};
    this.updated = obj.updated || null; this.nbuDate = obj.nbuDate || null;
    this.rebuild();
  }
  /** fetchJSON(url) → parsed JSON or null. Returns true if anything was updated. */
  async refresh(fetchJSON) {
    this.lastAttempt = Date.now();
    const ids = [...new Set(Object.values(CRYPTO_IDS))].sort().join(",");
    const [m, n, c, cb] = await Promise.all([
      fetchJSON("https://open.er-api.com/v6/latest/USD").catch(() => null),
      fetchJSON("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json").catch(() => null),
      fetchJSON(`https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd`).catch(() => null),
      fetchJSON("https://api.coinbase.com/v2/exchange-rates?currency=USD").catch(() => null),
    ]);
    let ok = false;
    if (m && m.rates && Object.keys(m.rates).length) { this.market = m.rates; ok = true; }
    if (Array.isArray(n) && n.length) {
      const map = {};
      for (const it of n) if (it.cc && typeof it.rate === "number") map[it.cc] = it.rate;
      this.nbu = map; this.nbuDate = n[0].exchangedate || null; ok = true;
    }
    if (c && typeof c === "object") {
      const map = {};
      for (const [code, id] of Object.entries(CRYPTO_IDS)) if (c[id] && typeof c[id].usd === "number") map[code] = c[id].usd;
      if (Object.keys(map).length) { this.crypto = map; ok = true; }
    }
    if (!Object.keys(this.crypto).length || !(c && Object.keys(c).length)) {
      // Backup crypto source (Coinbase): rates are "coins per 1 USD".
      const r = cb && cb.data && cb.data.rates;
      if (r) {
        const map = {};
        for (const code of Object.keys(CRYPTO_IDS)) { const v = Number(r[code]); if (v > 0) map[code] = 1 / v; }
        if (Object.keys(map).length) { this.crypto = map; ok = true; }
      }
    }
    if (ok) { this.updated = Date.now(); this.rebuild(); }
    return ok;
  }
}

export class UnitRegistry {
  constructor(rates) {
    this.rates = rates;
    this.exact = new Map(); this.lower = new Map();
    this.curExact = new Map(); this.curLower = new Map();
    this.stemUnit = new Map(); this.stemCur = new Map();
    const words = new Set();
    for (const [id, dim, f, aliases, off] of UNIT_DEFS) {
      const u = makeUnit(id, dim, f, off);
      for (const a of [id, ...aliases]) {
        if (!this.exact.has(a)) this.exact.set(a, u);
        const l = a.toLowerCase();
        if (!this.lower.has(l)) this.lower.set(l, u);
        if (hasCyrillic(a)) { const st = stem(a); if (!this.stemUnit.has(st)) this.stemUnit.set(st, u); }
        words.add(a);
      }
    }
    for (const [code, aliases] of CURRENCY_ALIASES) {
      words.add(code);
      for (const a of aliases) {
        if (!this.curExact.has(a)) this.curExact.set(a, code);
        const l = a.toLowerCase();
        if (!this.curLower.has(l)) this.curLower.set(l, code);
        if (hasCyrillic(a)) { const st = stem(a); if (!this.stemCur.has(st)) this.stemCur.set(st, code); }
        words.add(a);
      }
    }
    for (const c of COMMON_CODES) words.add(c);
    this.completionWords = [...words].filter((w) => /^\p{L}/u.test(w)).sort();
  }
  currency(code) { return makeUnit(code, "currency", 1, 0, CRYPTO_IDS[code] !== undefined); }
  lookup(s) {
    if (this.exact.has(s)) return this.exact.get(s);
    if (this.curExact.has(s)) return this.currency(this.curExact.get(s));
    const codeLike = isCodeLike(s);
    if (codeLike && s === s.toUpperCase() && this.rates.knows(s)) return this.currency(s);
    const l = s.toLowerCase();
    if (this.lower.has(l)) return this.lower.get(l);
    if (this.curLower.has(l)) return this.currency(this.curLower.get(l));
    const up = s.toUpperCase();
    if (codeLike && this.rates.knows(up)) return this.currency(up);
    if (hasCyrillic(s)) {
      const st = stem(s);
      if (this.stemUnit.has(st)) return this.stemUnit.get(st);
      if (this.stemCur.has(st)) return this.currency(this.stemCur.get(st));
    }
    return null;
  }
  convert(v, from, to) {
    if (sameUnit(from, to)) return v;
    if (from.dim !== to.dim) throw new CalcError(tr("cantConvert", from.id, to.id));
    if (from.dim === "currency") {
      const a = this.rates.perUSD[from.id], b = this.rates.perUSD[to.id];
      if (!(a > 0) || b === undefined) {
        if (Object.keys(this.rates.perUSD).length <= 1) throw new CalcError(tr("noRates"));
        throw new CalcError(tr("noRate", this.rates.perUSD[from.id] === undefined ? from.id : to.id));
      }
      return (v / a) * b;
    }
    // Inverse units (l/100km): base = |factor| / value
    if (from.factor < 0 || to.factor < 0) {
      if (v === 0) throw new CalcError(tr("divZero"));
      const base = from.factor < 0 ? -from.factor / v : v * from.factor + from.offset;
      return to.factor < 0 ? -to.factor / base : (base - to.offset) / to.factor;
    }
    const base = v * from.factor + from.offset;
    return (base - to.offset) / to.factor;
  }
}

// ───────────────────────── Lexer ─────────────────────────

const isDigit = (c) => c >= 48 && c <= 57;
function isLetter(c) {
  if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95) return true;
  if (c < 0xb0) return false;
  if (c === 0xb0 || c === 0xb5) return true;
  if (c === 0xb2 || c === 0xb3 || c === 0xb7 || c === 0xd7 || c === 0xf7) return false;
  if (c >= 0xd800 && c <= 0xdfff) return false;
  return /\p{L}/u.test(String.fromCharCode(c));
}
const isIdentCont = (c) => isLetter(c) || isDigit(c) || c === 0xb2 || c === 0xb3;

class Lexer {
  constructor(text, base, settings) {
    this.s = text; this.base = base;
    this.decimal = settings.decimalSeparator === "," ? 44 : 46;
  }
  code(i) { return this.s.charCodeAt(i); }

  tokenize() {
    const s = this.s, n = s.length, toks = [];
    let i = 0, space = false;
    const push = (kind, text, a, b, num = 0) => {
      toks.push({ kind, text, num, start: this.base + a, end: this.base + b, spaceBefore: space });
      space = false;
    };
    while (i < n) {
      const c = this.code(i);
      if (c === 32 || c === 9 || c === 0xa0 || c === 0x202f || c === 0x2009) { space = true; i++; continue; }
      const p = toks[toks.length - 1];
      const prevAllows = !p || p.kind === "op" || p.kind === "lparen" || p.kind === "sep";
      const leadingSep = (c === 44 || c === 46) && i + 1 < n && isDigit(this.code(i + 1)) && prevAllows;
      if (isDigit(c)) {
        const dt = this.lexDateTime(i);
        if (dt) { push(dt.kind, s.slice(i, dt.end), i, dt.end, dt.num); i = dt.end; continue; }
      }
      if (isDigit(c) || leadingSep) {
        const [v, e] = this.lexNumber(i);
        push("num", s.slice(i, e), i, e, v);
        i = e;
        if (i + 1 < n) {
          const x = this.code(i);
          if ((x === 120 || x === 88 || x === 0x445) && isDigit(this.code(i + 1))) { push("op", "*", i, i + 1); i++; }
        }
        continue;
      }
      if (isLetter(c)) {
        let j = i + 1;
        while (j < n && isIdentCont(this.code(j))) j++;
        push("ident", s.slice(i, j), i, j);
        i = j;
        continue;
      }
      const ch = s[i];
      switch (ch) {
        case "$": case "€": case "£": case "₴": case "¥": case "₿": case "√": case "℃": case "℉":
          push("ident", ch, i, i + 1); i++; break;
        case "(": case "[": push("lparen", "(", i, i + 1); i++; break;
        case ")": case "]": push("rparen", ")", i, i + 1); i++; break;
        case ";": case ",": push("sep", ",", i, i + 1); i++; break;
        case "-": case "−": case "–":
          if (i + 1 < n && s[i + 1] === ">") { push("op", "->", i, i + 2); i += 2; } else { push("op", "-", i, i + 1); i++; }
          break;
        case "*":
          if (i + 1 < n && s[i + 1] === "*") { push("op", "^", i, i + 2); i += 2; } else { push("op", "*", i, i + 1); i++; }
          break;
        case "×": case "·": case "∙": push("op", "*", i, i + 1); i++; break;
        case "÷": push("op", "/", i, i + 1); i++; break;
        case "→": push("op", "->", i, i + 1); i++; break;
        case "+": case "/": case "^": case "%": case "!": case "=": push("op", ch, i, i + 1); i++; break;
        default: throw new CalcError(tr("unknownChar", ch));
      }
    }
    toks.push({ kind: "eof", text: "", num: 0, start: this.base + n, end: this.base + n, spaceBefore: space });
    return toks;
  }

  /** 23:30, 23:30:15, 12.12.2026, 2026-12-12, 12/31/2026 (US order). */
  lexDateTime(i) {
    const rest = this.s.slice(i);
    let m = rest.match(/^(\d{1,3}):(\d{2})(?::(\d{2}))?(?![\d:])/);
    if (m) {
      const h = +m[1], mi = +m[2], se = m[3] ? +m[3] : 0;
      if (mi < 60 && se < 60) return { kind: "clock", num: h * 3600 + mi * 60 + se, end: i + m[0].length };
    }
    const date = (y, mo, d, len) => (validDate(y, mo, d) ? { kind: "date", num: daysFromCivil(y, mo, d), end: i + len } : null);
    if ((m = rest.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})(?![\d.])/))) {
      const r = date(+m[3], +m[2], +m[1], m[0].length);
      if (!r) throw new CalcError(tr("badDate"));
      return r;
    }
    if ((m = rest.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)/))) return date(+m[1], +m[2], +m[3], m[0].length);
    if ((m = rest.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?!\d)/))) return date(+m[3], +m[1], +m[2], m[0].length);
    return null;
  }

  lexNumber(start) {
    const s = this.s, n = s.length;
    let i = start;
    // 0xFF, 0b1010, 0o17
    if (s[i] === "0" && i + 2 < n) {
      const p = s[i + 1].toLowerCase();
      const radix = p === "x" ? 16 : p === "b" ? 2 : p === "o" ? 8 : 0;
      if (radix) {
        let j = i + 2;
        while (j < n && !isNaN(parseInt(s[j], radix)) && /[0-9a-fA-F]/.test(s[j])) j++;
        if (j > i + 2) return [parseInt(s.slice(i + 2, j), radix), j];
      }
    }
    const groups = [], seps = [], ends = [];
    const readDigits = () => { let g = ""; while (i < n && isDigit(this.code(i))) { g += s[i]; i++; } return g; };
    groups.push(readDigits()); ends.push(i);
    while (i + 1 < n) {
      const c = this.code(i);
      const last = groups[groups.length - 1];
      if (c === 44 || c === 46 || c === 39) {
        if (!isDigit(this.code(i + 1))) break;
        i++; seps.push(c); groups.push(readDigits()); ends.push(i);
      } else if (c === 32 || c === 0xa0 || c === 0x202f) {
        const ok = i + 3 < n && isDigit(this.code(i + 1)) && isDigit(this.code(i + 2)) && isDigit(this.code(i + 3)) &&
          (i + 4 >= n || !isDigit(this.code(i + 4))) && last.length >= 1 && last.length <= 3 &&
          (!seps.some((x) => x === 44 || x === 46) || seps.every((x) => x === 32));
        if (!ok) break;
        i++; seps.push(32); groups.push(readDigits()); ends.push(i);
      } else break;
    }
    let digits = "", chosen = 0;
    for (let k = groups.length; k >= 1; k--) {
      const d = this.interpret(groups.slice(0, k), seps.slice(0, k - 1));
      if (d !== null) { digits = d; chosen = k; break; }
    }
    if (!chosen) throw new CalcError(tr("badNumber"));
    i = ends[chosen - 1];
    // exponent
    if (i < n && (s[i] === "e" || s[i] === "E")) {
      let j = i + 1;
      if (j < n && (s[j] === "+" || s[j] === "-")) j++;
      if (j < n && isDigit(this.code(j))) {
        let k = j;
        while (k < n && isDigit(this.code(k))) k++;
        if (k >= n || !isLetter(this.code(k))) { digits += "e" + s.slice(i + 1, k); i = k; }
      }
    }
    const v = Number(digits);
    if (!isFinite(v) && !/e/.test(digits)) throw new CalcError(tr("badNumber"));
    return [v, i];
  }

  interpret(g, seps) {
    if (!seps.length) return g[0] ? g[0] : null;
    const punct = seps.map((e, offset) => ({ e, offset })).filter((x) => x.e === 44 || x.e === 46);
    let decimalIndex = null;
    const kinds = new Set(punct.map((x) => x.e));
    if (kinds.size === 2) {
      const lastP = punct[punct.length - 1];
      decimalIndex = lastP.offset;
      if (punct.filter((x) => x.e === lastP.e).length > 1) return null;
    } else if (punct.length === 1) {
      const p = punct[0];
      const after = g[p.offset + 1], before = g[p.offset];
      const couldGroup = after.length === 3 && before.length >= 1 && before.length <= 3;
      decimalIndex = (couldGroup && p.e !== this.decimal && p.offset === seps.length - 1) ? null : p.offset;
    } else if (punct.length > 1) {
      decimalIndex = null;
    }
    if (decimalIndex !== null && decimalIndex !== seps.length - 1) return null;
    const lastGroupIdx = decimalIndex ?? seps.length;
    if (lastGroupIdx > 0) {
      if (!(g[0].length >= 1 && g[0].length <= 3)) return null;
      for (let k = 1; k <= lastGroupIdx; k++) if (g[k].length !== 3) return null;
    }
    let out = g.slice(0, lastGroupIdx + 1).join("");
    if (decimalIndex !== null) { if (!out) out = "0"; out += "." + g[decimalIndex + 1]; }
    return out || null;
  }
}

// ───────────────────────── Parser ─────────────────────────

const CONV_WORDS = new Set(["in", "to", "as", "into", "в", "во", "у"]);
const FORMAT_WORDS = { hex: "hex", bin: "bin", binary: "bin", oct: "oct", octal: "oct", sci: "sci", scientific: "sci", dec: "dec", decimal: "dec" };
const SCALES = {
  k: 1e3, "тис": 1e3, "тисяч": 1e3, "тисячі": 1e3, "мільйон": 1e6, "мільйонів": 1e6, "мільярд": 1e9, "мільярдів": 1e9,
  thousand: 1e3, thousands: 1e3, "тыс": 1e3, "тысяча": 1e3, "тысячи": 1e3, "тысяч": 1e3,
  M: 1e6, mln: 1e6, million: 1e6, millions: 1e6, "млн": 1e6, "миллион": 1e6, "миллиона": 1e6, "миллионов": 1e6,
  bn: 1e9, billion: 1e9, billions: 1e9, "млрд": 1e9, "миллиард": 1e9, "миллиарда": 1e9, "миллиардов": 1e9,
};
const CONSTANTS = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI };
export const FUNC_ALIASES = {
  sqrt: "sqrt", "√": "sqrt", "корень": "sqrt", "корінь": "sqrt", cbrt: "cbrt",
  abs: "abs", "модуль": "abs", round: "round", floor: "floor", ceil: "ceil", trunc: "trunc",
  sin: "sin", cos: "cos", tan: "tan", tg: "tan",
  asin: "asin", acos: "acos", atan: "atan", arcsin: "asin", arccos: "acos", arctan: "atan",
  sinh: "sinh", cosh: "cosh", tanh: "tanh",
  ln: "ln", log: "log", lg: "log", log10: "log", log2: "log2", exp: "exp",
  min: "min", max: "max", avg: "avg", average: "avg", sum: "sum", fact: "fact", root: "root",
};
const PREFIX_FUNCS = new Set(["sqrt", "cbrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "ln", "log", "log2", "exp", "fact"]);
const PREV_WORDS = new Set(["prev", "ans", "пред", "попер"]);
const SUM_WORDS = new Set(["sum", "total", "итого", "сумма", "всего", "разом", "підсумок", "усього", "всього"]);
const AVG_WORDS = new Set(["avg", "average", "среднее", "середнє"]);

const V = (num, unit = null, isPercent = false, format = "dec", kind = "plain", tz = null) => ({ num, unit, isPercent, format, kind, tz });
const CLOCK = (sec, tz = null) => V(sec, null, false, "dec", "clock", tz);
const DATE = (days) => V(days, null, false, "dec", "date");
const HMS = (sec, showSec = false) => ({ ...V(sec, null, false, "hms"), showSec });
const isHMS = (v) => v.kind === "plain" && v.format === "hms";
const isTimeUnit = (v) => v.kind === "plain" && v.unit && v.unit.dim === "time" && !v.isPercent;
const isPlainNum = (v) => v.kind === "plain" && !v.unit && !v.isPercent;
const copy = (v) => ({ ...v });

class Parser {
  constructor(tokens, reg, ctx) {
    this.t = tokens; this.i = 0; this.reg = reg; this.ctx = ctx; this.marks = []; this.warnings = [];
    this.fmt = String; this.fmtValue = (v) => String(v.num); this.decimals = 2; this.override = null;
  }
  matches(typed, actual) {
    const str = String(typed);
    let digits = 0;
    if (/e/.test(str)) digits = 12;
    else if (str.includes(".")) digits = str.split(".")[1].length;
    const tol = 0.5 * Math.pow(10, -Math.max(digits, this.decimals)) + 1e-9 * Math.max(1, Math.abs(actual));
    return Math.abs(typed - actual) <= tol;
  }
  get cur() { return this.t[this.i]; }
  at(k) { return this.t[Math.min(k, this.t.length - 1)]; }
  isOp(tok, s) { return tok.kind === "op" && tok.text === s; }
  mark(a, b, kind) { if (a < this.t.length && b < this.t.length && a <= b) this.marks.push({ start: this.t[a].start, end: this.t[b].end, kind }); }
  isConvWord(tok) { return (tok.kind === "ident" && CONV_WORDS.has(tok.text.toLowerCase())) || this.isOp(tok, "->"); }
  startsOperand(tok) {
    if (tok.kind === "num" || tok.kind === "lparen") return true;
    if (tok.kind === "ident") return !CONV_WORDS.has(tok.text.toLowerCase());
    return false;
  }
  isImplicitFactor(tok) {
    if (tok.kind === "lparen") return true;
    if (tok.kind !== "ident") return false;
    const low = tok.text.toLowerCase();
    if (this.ctx.vars.has(tok.text)) return true;
    if (CONSTANTS[low] !== undefined) return true;
    if (tok.text === "√") return true;
    if (FUNC_ALIASES[low] && this.at(this.i + 1).kind === "lparen") return true;
    return false;
  }
  isVarName(s) {
    const f = s.charCodeAt(0);
    if (!isLetter(f) || f === 0xb0) return false;
    return CONSTANTS[s.toLowerCase()] === undefined;
  }
  matchUnit(j) {
    const t = this.t;
    if (j >= t.length || t[j].kind !== "ident") return null;
    // "sq feet", "кв футов", "cubic inches": square/cubic word + any length unit
    const w = t[j].text.toLowerCase();
    const SQ = ["sq", "square", "кв", "квадратных", "квадратный", "квадратного", "квадратних", "квадратний"];
    const CU = ["cu", "cubic", "куб", "кубических", "кубический", "кубічних", "кубічний"];
    if ((SQ.includes(w) || CU.includes(w)) && j + 1 < t.length) {
      const m = this.matchUnit(j + 1);
      if (m && m[0].dim === "length") {
        const u = this.reg.lookup(m[0].id + (SQ.includes(w) ? "²" : "³"));
        if (u) return [u, m[1] + 1];
      }
    }
    const cands = [];
    let acc = "";
    for (let k = j; k < t.length && k < j + 5; k++) {
      const tk = t[k];
      let ok = false;
      if (k === j) ok = true;
      else if (tk.kind === "ident") ok = true;
      else if (tk.kind === "op" && (tk.text === "/" || tk.text === "^")) ok = !tk.spaceBefore;
      else if (tk.kind === "num") {
        // "m^2", "l/100km", "литров на 100 км", "l per 100 km"
        const prev = t[k - 1];
        ok = ((this.isOp(prev, "^") || this.isOp(prev, "/")) && !tk.spaceBefore)
          || (prev.kind === "ident" && ["на", "per"].includes(prev.text.toLowerCase()));
      }
      if (!ok) break;
      acc += (k > j && tk.spaceBefore ? " " : "") + tk.text;
      if (tk.kind === "ident" || tk.kind === "num") cands.push([acc, k - j + 1]);
    }
    for (let x = cands.length - 1; x >= 0; x--) {
      const u = this.reg.lookup(cands[x][0]);
      if (u) return [u, cands[x][1]];
    }
    return null;
  }

  parseLine() {
    if (this.cur.kind === "eof") return null;
    if (this.cur.kind === "ident" && this.isOp(this.at(this.i + 1), "=") && this.at(this.i + 2).kind !== "eof" && this.isVarName(this.cur.text)) {
      const name = this.cur.text;
      this.mark(this.i, this.i, "variable");
      this.i += 2;
      const v = this.parseConversion();
      this.finish();
      this.ctx.vars.set(name, v);
      return v;
    }
    let v = this.parseConversion();
    // Chains: "88+1=89+1=90+55+8=153" → answer of the last link (see Parser.swift).
    while (this.isOp(this.cur, "=")) {
      this.i++;
      if (this.cur.kind === "eof") break;
      let j = this.i;
      while (this.t[j].kind !== "eof" && !this.isOp(this.t[j], "=")) j++;
      if (j === this.i) continue;
      const seg = this.t.slice(this.i, j);
      const noteTok = (x, k) => ["num", "ident", "clock", "date", "sep", "lparen", "rparen"].includes(x.kind) ||
        (x.kind === "op" && (x.text === "+" || x.text === "-") && k > 0 && seg[k - 1].kind === "lparen");
      const isNote = this.t[j].kind === "eof" && ["num", "clock", "date"].includes(seg[0].kind) && seg.every(noteTok);
      if (isNote) {
        const differs = seg[0].kind === "num"
          ? v.kind === "plain" && !v.isPercent && v.format !== "hms" && !this.matches(seg[0].num, v.num)
          : seg[0].kind === "clock" && isHMS(v) ? Math.abs(seg[0].num - Math.abs(v.num)) > 0.5
          : seg[0].kind !== v.kind || (v.kind === "date" ? seg[0].num !== v.num : (((seg[0].num - v.num) % 86400) + 86400) % 86400 !== 0);
        if (differs) {
          this.warnings.push(tr("noteFix", seg.map((x) => x.text).join(" "), this.fmtValue(v)));
          this.marks.push({ start: seg[0].start, end: seg[seg.length - 1].end, kind: "error" });
        }
        this.i = j;
        break;
      }
      if (this.cur.kind === "op" && ["+", "-", "*", "/", "^"].includes(this.cur.text)) v = this.continueOps(v, true);
      else {
        // Always continue from the exact answer (the text may show it rounded).
        if (this.cur.kind === "num" && !v.isPercent && v.kind === "plain") {
          if (!this.matches(this.cur.num, v.num)) {
            this.warnings.push(tr("chainFix", this.cur.text, this.fmt(v.num)));
            this.marks.push({ start: this.cur.start, end: this.cur.end, kind: "error" });
          }
          this.override = { index: this.i, value: v.num };
        }
        v = this.parseConversion();
        this.override = null;
      }
    }
    this.finish();
    return v;
  }
  finish() {
    if (this.cur.kind !== "eof") throw new CalcError(tr("unclear", this.cur.text));
  }
  parseConversion() { return this.continueOps(this.parseExpr(), false); }
  continueOps(start, allowPower) {
    let v = start;
    for (;;) {
      if (allowPower && this.isOp(this.cur, "^")) { this.i++; v = this.power(v, this.parseUnary()); continue; }
      const tok = this.cur;
      if (this.isConvWord(tok)) {
        const j = this.i + 1, nt = this.at(j);
        if (nt.kind === "ident" && FORMAT_WORDS[nt.text.toLowerCase()]) {
          this.mark(this.i, j, "keyword");
          this.i = j + 1;
          v = copy(v); v.format = FORMAT_WORDS[nt.text.toLowerCase()];
          continue;
        }
        if (v.kind === "clock") {
          const z = this.matchZone(j);
          if (z) {
            this.mark(this.i, this.i, "keyword");
            this.mark(j, j + z.n - 1, "unit");
            this.i = j + z.n;
            v = this.toZone(v, z);
            continue;
          }
        }
        const m = this.matchUnit(j);
        if (!m) {
          if (nt.kind === "eof") throw new CalcError(tr("convertTo"));
          throw new CalcError(tr("unknownUnit", nt.text));
        }
        this.mark(this.i, this.i, "keyword");
        this.mark(j, j + m[1] - 1, "unit");
        this.i = j + m[1];
        if (v.unit && ((v.unit.dim === "flow" && m[0].dim === "speed") || (v.unit.dim === "speed" && m[0].dim === "flow"))) {
          v = this.pipeConvert(v, v.unit, m[0]);
          continue;
        }
        v = this.convert(v, m[0]);
        continue;
      }
      if (tok.kind === "op" && (tok.text === "+" || tok.text === "-")) {
        this.i++;
        v = this.addSub(v, this.parseTerm(), tok.text === "-");
        continue;
      }
      if (tok.kind === "op" && (tok.text === "*" || tok.text === "/")) {
        this.i++;
        const r = this.parseUnary();
        v = tok.text === "*" ? this.mul(v, r) : this.div(v, r);
        continue;
      }
      break;
    }
    return v;
  }
  parseExpr() {
    let l = this.parseTerm();
    while (this.cur.kind === "op" && (this.cur.text === "+" || this.cur.text === "-")) {
      const sub = this.cur.text === "-";
      this.i++;
      l = this.addSub(l, this.parseTerm(), sub);
    }
    return l;
  }
  parseTerm() {
    let l = this.parseUnary();
    for (;;) {
      const tok = this.cur;
      if (tok.kind === "op" && (tok.text === "*" || tok.text === "/")) {
        this.i++;
        const r = this.parseUnary();
        l = tok.text === "*" ? this.mul(l, r) : this.div(l, r);
        continue;
      }
      if (tok.kind === "ident") {
        const low = tok.text.toLowerCase();
        if ((low === "x" || low === "х") && !this.ctx.vars.has(tok.text) && this.startsOperand(this.at(this.i + 1))) {
          this.i++; l = this.mul(l, this.parseUnary()); continue;
        }
        if (low === "mod") { this.mark(this.i, this.i, "keyword"); this.i++; l = this.modulo(l, this.parseUnary()); continue; }
        if (l.isPercent && ["of", "от", "від", "off", "on"].includes(low)) {
          this.mark(this.i, this.i, "keyword");
          this.i++;
          const r = this.parseUnary();
          if (r.isPercent) throw new CalcError(tr("pctOfPct"));
          const res = copy(r), p = l.num / 100;
          res.num = low === "off" ? r.num * (1 - p) : low === "on" ? r.num * (1 + p) : r.num * p;
          l = res;
          continue;
        }
      }
      break;
    }
    return l;
  }
  parseUnary() {
    if (this.isOp(this.cur, "-")) { this.i++; const v = copy(this.parseUnary()); v.num = -v.num; return v; }
    if (this.isOp(this.cur, "+")) { this.i++; return this.parseUnary(); }
    return this.parsePower();
  }
  parsePower() {
    const b = this.parsePostfix();
    if (this.isOp(this.cur, "^")) { this.i++; return this.power(b, this.parseUnary()); }
    return b;
  }
  parsePostfix() {
    let v = copy(this.parsePrimary());
    for (;;) {
      if (this.isOp(this.cur, "!") && !v.isPercent) { this.i++; v.num = factorial(v.num); continue; }
      if (this.isOp(this.cur, "%") && !v.isPercent) { this.i++; v.isPercent = true; continue; }
      break;
    }
    v = this.dateTimePostfix(v);
    if (v.kind === "plain" && !v.unit && !v.isPercent) {
      if (this.cur.kind === "ident" && SCALES[this.cur.text] !== undefined) {
        this.mark(this.i, this.i, "keyword");
        v.num *= SCALES[this.cur.text];
        this.i++;
      }
      const m = this.matchUnit(this.i);
      if (m) {
        const low = this.cur.text.toLowerCase();
        const isConv = m[1] === 1 && CONV_WORDS.has(low);
        const next = this.at(this.i + 1);
        const nextIsTarget = (this.matchUnit(this.i + 1) !== null || FORMAT_WORDS[next.text.toLowerCase()] !== undefined) &&
          !CONV_WORDS.has(next.text.toLowerCase());
        if (!(isConv && nextIsTarget)) {
          this.mark(this.i, this.i + m[1] - 1, "unit");
          this.i += m[1];
          v.unit = m[0];
          v = this.compoundUnits(v);
        }
      }
    }
    if (this.isImplicitFactor(this.cur)) v = this.mul(v, this.parsePostfix());
    return v;
  }
  parsePrimary() {
    const tok = this.cur;
    switch (tok.kind) {
      case "clock": {
        this.i++;
        const showSec = (tok.text.match(/:/g) || []).length > 1;
        // more than 24 hours can only be a duration: 36:30
        if (tok.num > 24 * 3600) { const v = HMS(tok.num, showSec); v.unit = this.reg.lookup("s"); return v; }
        const v = CLOCK(tok.num); v.showSec = showSec; return v;
      }
      case "date": this.i++; return DATE(tok.num);
      case "num":
        if (this.override && this.override.index === this.i) { this.i++; return V(this.override.value); }
        this.i++; return V(tok.num);
      case "lparen": {
        this.i++;
        const v = this.parseConversion();
        if (this.cur.kind === "rparen") this.i++;
        else if (this.cur.kind !== "eof") throw new CalcError(tr("expectedParen"));
        return v;
      }
      case "ident": return this.parseIdent();
      case "eof": throw new CalcError(tr("incomplete"));
      default: throw new CalcError(tr("unexpected", tok.text));
    }
  }
  parseIdent() {
    const tok = this.cur, name = tok.text, low = name.toLowerCase();
    if (this.ctx.vars.has(name)) { this.mark(this.i, this.i, "variable"); this.i++; return this.ctx.vars.get(name); }
    if (DAY_WORDS[low] !== undefined) { this.mark(this.i, this.i, "keyword"); this.i++; return DATE(this.ctx.today + DAY_WORDS[low]); }
    if (NOW_WORDS.has(low)) { this.mark(this.i, this.i, "keyword"); this.i++; return CLOCK(this.ctx.nowSec); }
    if (UNTIL_WORDS.has(low) && ["date", "num"].includes(this.at(this.i + 1).kind)) {
      this.mark(this.i, this.i, "keyword");
      this.i++;
      const target = this.upcomingDate();
      return V(target - this.ctx.today, this.reg.lookup("day"));
    }
    if (MONTHS[low] && this.at(this.i + 1).kind === "num") {
      // "December 12, 2026"
      const month = MONTHS[low];
      this.mark(this.i, this.i, "unit");
      this.i++;
      const day = this.cur.num;
      this.i++;
      if (this.cur.kind === "sep") this.i++;
      let year = civilFromDays(this.ctx.today)[0];
      if (this.cur.kind === "num" && Number.isInteger(this.cur.num) && this.cur.num >= 1000) { year = this.cur.num; this.i++; }
      if (!Number.isInteger(day) || !validDate(year, month, day)) throw new CalcError(tr("badDate"));
      return DATE(daysFromCivil(year, month, day));
    }
    const f = FUNC_ALIASES[low];
    if (f) {
      if (this.at(this.i + 1).kind === "lparen") {
        this.mark(this.i, this.i, "function");
        this.i += 2;
        const args = [];
        if (this.cur.kind === "rparen") this.i++;
        else for (;;) {
          args.push(this.parseConversion());
          if (this.cur.kind === "sep") { this.i++; continue; }
          if (this.cur.kind === "rparen") { this.i++; break; }
          if (this.cur.kind === "eof") break;
          throw new CalcError(tr("expectedParen"));
        }
        return this.callFunc(f, args);
      }
      if (PREFIX_FUNCS.has(f) && this.startsOperand(this.at(this.i + 1))) {
        this.mark(this.i, this.i, "function");
        this.i++;
        return this.callFunc(f, [this.parsePostfix()]);
      }
    }
    if (CONSTANTS[low] !== undefined) { this.mark(this.i, this.i, "keyword"); this.i++; return V(CONSTANTS[low]); }
    if (PREV_WORDS.has(low)) {
      this.mark(this.i, this.i, "keyword"); this.i++;
      if (!this.ctx.prev) throw new CalcError(tr("noPrev"));
      return this.ctx.prev;
    }
    if (SUM_WORDS.has(low)) { this.mark(this.i, this.i, "keyword"); this.i++; return this.blockAggregate()[0]; }
    if (AVG_WORDS.has(low)) {
      this.mark(this.i, this.i, "keyword"); this.i++;
      const [s, n] = this.blockAggregate();
      const r = copy(s); r.num = n > 0 ? s.num / n : 0; return r;
    }
    const m = this.matchUnit(this.i);
    if (m) {
      this.mark(this.i, this.i + m[1] - 1, "unit");
      this.i += m[1];
      if (m[0].dim === "currency" && (this.cur.kind === "num" || this.cur.kind === "lparen")) {
        const v = copy(this.parsePostfix());
        if (v.isPercent) throw new CalcError(tr("curPct"));
        if (v.unit) v.num = this.reg.convert(v.num, v.unit, m[0]);
        v.unit = m[0];
        return v;
      }
      return V(1, m[0]);
    }
    throw new CalcError(tr("unknown", name));
  }
  blockAggregate() {
    let acc = null, n = 0;
    for (const v of this.ctx.block) {
      if (v.isPercent) continue;
      if (acc) { try { acc = this.addSub(acc, v, false); n++; } catch { /* skip */ } }
      else { acc = v; n = 1; }
    }
    return [acc || V(0), n];
  }

  // ───── Dates and times ─────
  dateTimePostfix(v) {
    const low = () => (this.cur.kind === "ident" ? this.cur.text.toLowerCase() : "");
    // "12 December 2026", "12 декабря"
    if (isPlainNum(v) && Number.isInteger(v.num) && v.num >= 1 && v.num <= 31 && MONTHS[low()]) {
      const month = MONTHS[low()];
      this.mark(this.i, this.i, "unit");
      this.i++;
      let year = civilFromDays(this.ctx.today)[0];
      if (this.cur.kind === "num" && Number.isInteger(this.cur.num) && this.cur.num >= 1000 && this.cur.num <= 9999) { year = this.cur.num; this.i++; }
      if (!validDate(year, month, v.num)) throw new CalcError(tr("badDate"));
      return DATE(daysFromCivil(year, month, v.num));
    }
    // "3pm", "11 am"
    if (isPlainNum(v) && Number.isInteger(v.num) && v.num >= 1 && v.num <= 12 && (low() === "am" || low() === "pm")) {
      v = CLOCK(v.num * 3600);
    }
    if (v.kind === "clock") {
      if (low() === "am" || low() === "pm") {
        const h = Math.floor(v.num / 3600), rest = v.num - h * 3600;
        const h24 = low() === "pm" ? (h % 12) + 12 : h % 12;
        this.mark(this.i, this.i, "unit");
        this.i++;
        v = CLOCK(h24 * 3600 + rest, v.tz);
      }
      if (!v.tz && !this.isConvWord(this.cur)) {
        const z = this.matchZone(this.i);
        if (z) { this.mark(this.i, this.i + z.n - 1, "unit"); this.i += z.n; v = CLOCK(v.num, z); }
      }
    }
    return v;
  }
  /** "8 h 35 min", "1 day 2 h": add following number+unit of the same kind. */
  compoundUnits(v) {
    while (this.cur.kind === "num" && ["time", "length", "mass"].includes(v.unit.dim)) {
      let m = this.matchUnit(this.i + 1);
      if (m && v.unit.dim === "time" && m[0].dim !== "time" && this.at(this.i + 1).text === "m") m = [this.reg.lookup("min"), 1];
      if (!m || m[0].dim !== v.unit.dim || CONV_WORDS.has(this.at(this.i + 1).text.toLowerCase())) break;
      const n = this.cur.num;
      this.mark(this.i + 1, this.i + m[1], "unit");
      this.i += 1 + m[1];
      v = this.addSub(v, V(n, m[0]), false);
    }
    return v;
  }
  matchZone(j) {
    if (this.at(j).kind !== "ident") return null;
    for (const n of [2, 1]) {
      const toks = this.t.slice(j, j + n);
      if (toks.length < n || toks.some((x) => x.kind !== "ident" && !(x.kind === "op" && x.text === "-"))) continue;
      const key = toks.map((x) => x.text).join(" ").toLowerCase();
      if (ZONES[key]) return { id: ZONES[key][0], label: ZONES[key][1], n };
    }
    return null;
  }
  zoneOffset(z) { return tzOffset(z ? z.id : this.ctx.localTz, this.ctx.now); }
  toZone(v, z) { return CLOCK(v.num + this.zoneOffset(z) - this.zoneOffset(v.tz), z); }
  upcomingDate() {
    const tok = this.cur;
    if (tok.kind === "date") { this.i++; return tok.num; }
    const m = tok.text.match(/^(\d{1,2})[.,](\d{1,2})$/);
    if (!m) throw new CalcError(tr("badDate"));
    this.i++;
    const d = +m[1], mo = +m[2];
    let y = civilFromDays(this.ctx.today)[0];
    if (!validDate(y, mo, d)) throw new CalcError(tr("badDate"));
    if (daysFromCivil(y, mo, d) < this.ctx.today) y++;
    return daysFromCivil(y, mo, d);
  }
  addSubDT(a, b, sub) {
    const sign = sub ? -1 : 1;
    if (a.isPercent || b.isPercent) throw new CalcError(tr("dateOp"));
    const sec = this.reg.lookup("s");
    const showSec = !!(a.showSec || b.showSec);
    const asDur = (n) => { const v = HMS(n, showSec); v.unit = sec; return v; };
    // time ± time → duration: 0:45+0:30, 18:45-9:30
    if (a.kind === "clock" && b.kind === "clock") {
      const bn = sub && (a.tz || b.tz) ? this.toZone(b, a.tz).num : b.num;
      return asDur(a.num + sign * bn);
    }
    if ((a.kind === "clock" && isHMS(b)) || (isHMS(a) && b.kind === "clock")) return asDur(a.num + sign * b.num);
    // clock ± duration in units (h, min) → time of day
    if (a.kind === "clock" && isTimeUnit(b)) { const c = CLOCK(a.num + sign * this.reg.convert(b.num, b.unit, sec), a.tz); c.showSec = showSec; return c; }
    if (b.kind === "clock" && isTimeUnit(a) && !sub) return CLOCK(b.num + this.reg.convert(a.num, a.unit, this.reg.lookup("s")), b.tz);
    if (a.kind === "clock" && isPlainNum(b)) throw new CalcError(tr("timeNeedsUnit"));
    // date ± duration
    if (a.kind === "date" && isTimeUnit(b)) return DATE(this.shiftDate(a.num, sign * b.num, b.unit));
    if (b.kind === "date" && isTimeUnit(a) && !sub) return DATE(this.shiftDate(b.num, a.num, a.unit));
    if (a.kind === "date" && b.kind === "date" && sub) return V(a.num - b.num, this.reg.lookup("day"));
    if (a.kind === "date" && isPlainNum(b)) throw new CalcError(tr("dateNeedsUnit"));
    throw new CalcError(tr("dateOp"));
  }
  shiftDate(days, n, unit) {
    if (unit.id === "month" || unit.id === "year") {
      const months = n * (unit.id === "year" ? 12 : 1);
      if (!Number.isInteger(Math.round(months * 1e9) / 1e9)) throw new CalcError(tr("dateWholeDays"));
      return addMonths(days, Math.round(months));
    }
    const d = this.reg.convert(n, unit, this.reg.lookup("day"));
    if (Math.abs(d - Math.round(d)) > 1e-9) throw new CalcError(tr("dateWholeDays"));
    return days + Math.round(d);
  }

  convert(v, u) {
    if (v.kind === "clock" && u.dim === "time") return V(this.reg.convert(v.num, this.reg.lookup("s"), u), u);
    if (v.kind !== "plain") throw new CalcError(tr("dateOp"));
    if (v.isPercent) throw new CalcError(tr("pctConvert", u.id));
    const r = copy(v);
    r.format = "dec";
    if (v.unit) r.num = this.reg.convert(v.num, v.unit, u);
    r.unit = u;
    return r;
  }
  addSub(a, b, sub) {
    if (a.kind !== "plain" || b.kind !== "plain") return this.addSubDT(a, b, sub);
    if ((isHMS(a) && isPlainNum(b)) || (isHMS(b) && isPlainNum(a))) throw new CalcError(tr("timeNeedsUnit"));
    const sign = sub ? -1 : 1;
    if (b.isPercent && !a.isPercent) { const r = copy(a); r.num = a.num * (1 + (sign * b.num) / 100); return r; }
    if (a.isPercent !== b.isPercent) throw new CalcError(tr("pctAdd"));
    const r = copy(a);
    if (a.unit && b.unit) r.num = a.num + sign * this.reg.convert(b.num, b.unit, a.unit);
    else if (!a.unit && b.unit) { r.num = a.num + sign * b.num; r.unit = b.unit; }
    else r.num = a.num + sign * b.num;
    return r;
  }
  mul(a, b) {
    const sec = this.reg.lookup("s");
    const toDur = (c) => { if (c.kind !== "clock") return c; const v = HMS(c.num, c.showSec); v.unit = sec; return v; };
    a = toDur(a); b = toDur(b);
    if (a.kind !== "plain" || b.kind !== "plain") throw new CalcError(tr("dateOp"));
    // hours × rate: 8:30 * $25, 8 h * 25 usd
    const timeMoney = (t, m) => t.unit && t.unit.dim === "time" && m.unit && m.unit.dim === "currency" && !t.isPercent && !m.isPercent;
    if (timeMoney(a, b)) return V(this.reg.convert(a.num, a.unit, this.reg.lookup("h")) * b.num, b.unit);
    if (timeMoney(b, a)) return V(this.reg.convert(b.num, b.unit, this.reg.lookup("h")) * a.num, a.unit);
    if (a.isPercent && b.isPercent) return V((a.num * b.num) / 100, null, true);
    if (b.isPercent) { const r = copy(a); r.num = (a.num * b.num) / 100; return r; }
    if (a.isPercent) { const r = copy(b); r.num = (b.num * a.num) / 100; return r; }
    if (a.unit && b.unit) {
      if ((a.unit.dim === "flow" && b.unit.dim === "time") || (a.unit.dim === "time" && b.unit.dim === "flow")) {
        const [q, t] = a.unit.dim === "flow" ? [a, b] : [b, a];
        return V(this.reg.convert(q.num, q.unit, this.reg.lookup("m³/s")) * this.reg.convert(t.num, t.unit, this.reg.lookup("s")), this.reg.lookup("m³"));
      }
      // area × length → volume: 2 ft * 3 ft * 4 ft
      if ((a.unit.dim === "area" && b.unit.dim === "length") || (a.unit.dim === "length" && b.unit.dim === "area")) {
        const [ar, ln] = a.unit.dim === "area" ? [a, b] : [b, a];
        const R = this.reg, m3 = R.lookup("m³");
        const v = R.convert(ar.num, ar.unit, R.lookup("m²")) * R.convert(ln.num, ln.unit, R.lookup("m"));
        const cu = R.lookup(ln.unit.id + "³");
        return cu ? V(R.convert(v, m3, cu), cu) : V(v, m3);
      }
      if (a.unit.dim === "length" && b.unit.dim === "length") {
        const bv = this.reg.convert(b.num, b.unit, a.unit);
        const area = this.reg.lookup(a.unit.id + "²");
        if (area) return V(a.num * bv, area);
      }
      throw new CalcError(tr("mulUnits", a.unit.id, b.unit.id));
    }
    if (!a.unit && b.unit) return V(a.num * b.num, b.unit);
    const r = copy(a); r.num = a.num * b.num; return r;
  }
  div(a, b) {
    if (b.num === 0) throw new CalcError(tr("divZero"));
    if (a.kind === "clock") { const v = HMS(a.num, a.showSec); v.unit = this.reg.lookup("s"); a = v; }
    if (b.kind === "clock") { const v = HMS(b.num, b.showSec); v.unit = this.reg.lookup("s"); b = v; }
    if (a.kind !== "plain" || b.kind !== "plain") throw new CalcError(tr("dateOp"));
    if (a.isPercent && b.isPercent) return V(a.num / b.num);
    if (b.isPercent) { const r = copy(a); r.num = a.num / (b.num / 100); return r; }
    if (a.isPercent) return V(a.num / b.num, null, true);
    if (a.unit && b.unit) {
      const ua = a.unit, ub = b.unit;
      if (ua.dim === ub.dim) {
        const bv = this.reg.convert(b.num, ub, ua);
        if (bv === 0) throw new CalcError(tr("divZero"));
        return V(a.num / bv);
      }
      if (ua.dim === "volume" && ub.dim === "time") {
        const base = this.reg.lookup("m³/s"), q = (a.num * ua.factor) / (b.num * ub.factor);
        const d = this.reg.lookup(ua.id + "/" + ub.id), tu = d && d.dim === "flow" ? d : base;
        return V(this.reg.convert(q, base, tu), tu);
      }
      if (ua.dim === "flow" && ub.dim === "area") {
        const area = this.reg.convert(b.num, ub, this.reg.lookup("m²"));
        if (area === 0) throw new CalcError(tr("divZero"));
        return V(this.reg.convert(a.num, ua, this.reg.lookup("m³/s")) / area, this.reg.lookup("m/s"));
      }
      if (ua.dim === "length" && ub.dim === "time") {
        const direct = this.reg.lookup(ua.id + "/" + ub.id);
        if (direct && direct.dim === "speed") return V(this.reg.convert((a.num * ua.factor) / (b.num * ub.factor), this.reg.lookup("m/s"), direct), direct);
      }
      if (ua.dim === "length" && ub.dim === "time") {
        const mps = (a.num * ua.factor) / (b.num * ub.factor);
        let target = "m/s";
        if (ub.id === "h" && ua.id === "km") target = "km/h";
        if (ub.id === "h" && ua.id === "mi") target = "mph";
        const ms = this.reg.lookup("m/s"), tu = this.reg.lookup(target);
        if (ms && tu) return V(this.reg.convert(mps, ms, tu), tu);
      }
      throw new CalcError(tr("divUnits", ua.id, ub.id));
    }
    if (!a.unit && b.unit) throw new CalcError(tr("divNumUnit", b.unit.id));
    const r = copy(a); r.num = a.num / b.num; return r;
  }
  // Flow ↔ speed in a round pipe: "1500 m3/h in m/s at 500 mm".
  pipeConvert(v, from, to) {
    const AT = ["at", "при", "для", "for", "d", "dn", "ø", "⌀"];
    if (!(this.cur.kind === "ident" && AT.includes(this.cur.text.toLowerCase()))) throw new CalcError(tr("needDiameter"));
    this.mark(this.i, this.i, "keyword"); this.i++;
    while (this.cur.kind === "ident" && ["диаметре", "діаметрі", "diameter", "трубе", "трубі", "pipe", "dn", "d"].includes(this.cur.text.toLowerCase())) {
      this.mark(this.i, this.i, "keyword"); this.i++;
    }
    const d = this.parseTerm();
    const R = this.reg, m = R.lookup("m"), m3s = R.lookup("m³/s"), ms = R.lookup("m/s");
    if (!d.unit || d.unit.dim !== "length") throw new CalcError(tr("needDiameter"));
    const dm = R.convert(d.num, d.unit, m);
    if (!(dm > 0)) throw new CalcError(tr("divZero"));
    const area = (Math.PI * dm * dm) / 4;
    if (from.dim === "flow") return V(R.convert(R.convert(v.num, from, m3s) / area, ms, to), to);
    return V(R.convert(R.convert(v.num, from, ms) * area, m3s, to), to);
  }
  modulo(a, b) {
    let bv = b.num;
    if (a.unit && b.unit) bv = this.reg.convert(b.num, b.unit, a.unit);
    if (bv === 0) throw new CalcError(tr("divZero"));
    const r = copy(a); r.num = a.num % bv; return r;
  }
  power(b, e) {
    if (e.unit || e.isPercent) throw new CalcError(tr("powNum"));
    if (b.unit) {
      if (b.unit.dim === "length" && (e.num === 2 || e.num === 3)) {
        const nu = this.reg.lookup(b.unit.id + (e.num === 2 ? "²" : "³"));
        if (nu) return V(Math.pow(b.num, e.num), nu);
      }
      throw new CalcError(tr("powUnit", b.unit.id));
    }
    const r = Math.pow(b.num, e.num);
    if (Number.isNaN(r)) throw new CalcError(tr("noReal"));
    return V(r);
  }
  callFunc(f, args) {
    const one = () => { if (args.length !== 1) throw new CalcError(tr("oneArg", f)); return args[0]; };
    const plain = (v) => { if (v.unit) throw new CalcError(tr("plainArg", f)); return v.isPercent ? v.num / 100 : v.num; };
    const radians = (v) => {
      if (v.unit) { if (v.unit.dim !== "angle") throw new CalcError(tr("angleArg", f)); return v.num * v.unit.factor; }
      return v.num;
    };
    const logPos = (x) => { if (!(x > 0)) throw new CalcError(tr("logPos")); return x; };
    switch (f) {
      case "sqrt": { const x = plain(one()); if (x < 0) throw new CalcError(tr("sqrtNeg")); return V(Math.sqrt(x)); }
      case "cbrt": return V(Math.cbrt(plain(one())));
      case "root": {
        if (args.length !== 2) throw new CalcError(tr("rootUsage"));
        const x = plain(args[0]), n = plain(args[1]);
        if (n === 0) throw new CalcError(tr("rootZero"));
        return V(Math.pow(x, 1 / n));
      }
      case "abs": case "round": case "floor": case "ceil": case "trunc": {
        if (args.length < 1 || args.length > 2) throw new CalcError(tr("oneTwoArgs", f));
        const v = copy(args[0]);
        const m = Math.pow(10, args.length === 2 ? plain(args[1]) : 0);
        const x = v.num * m;
        if (f === "abs") v.num = Math.abs(v.num);
        else if (f === "round") v.num = (x < 0 ? -Math.round(-x) : Math.round(x)) / m;
        else if (f === "floor") v.num = Math.floor(x) / m;
        else if (f === "ceil") v.num = Math.ceil(x) / m;
        else v.num = Math.trunc(x) / m;
        return v;
      }
      case "sin": return V(Math.sin(radians(one())));
      case "cos": return V(Math.cos(radians(one())));
      case "tan": return V(Math.tan(radians(one())));
      case "asin": return V(Math.asin(plain(one())));
      case "acos": return V(Math.acos(plain(one())));
      case "atan": return V(Math.atan(plain(one())));
      case "sinh": return V(Math.sinh(plain(one())));
      case "cosh": return V(Math.cosh(plain(one())));
      case "tanh": return V(Math.tanh(plain(one())));
      case "ln": return V(Math.log(logPos(plain(one()))));
      case "log": {
        if (args.length < 1 || args.length > 2) throw new CalcError(tr("logUsage"));
        const x = logPos(plain(args[0]));
        if (args.length === 2) {
          const b = plain(args[1]);
          if (!(b > 0) || b === 1) throw new CalcError(tr("badBase"));
          return V(Math.log(x) / Math.log(b));
        }
        return V(Math.log10(x));
      }
      case "log2": return V(Math.log2(logPos(plain(one()))));
      case "exp": return V(Math.exp(plain(one())));
      case "fact": return V(factorial(plain(one())));
      case "min": case "max": case "avg": case "sum": {
        if (!args.length) throw new CalcError(tr("needArgs", f));
        const first = args[0];
        const vals = args.map((a) => (first.unit && a.unit ? this.reg.convert(a.num, a.unit, first.unit) : a.num));
        const r = copy(first);
        if (f === "min") r.num = Math.min(...vals);
        else if (f === "max") r.num = Math.max(...vals);
        else { const s = vals.reduce((x, y) => x + y, 0); r.num = f === "sum" ? s : s / vals.length; }
        return r;
      }
      default: throw new CalcError(tr("unknownFunc", f));
    }
  }
}

function factorial(x) {
  if (!(x >= 0) || x !== Math.round(x) || x > 170) throw new CalcError(tr("factorial"));
  let r = 1;
  for (let k = 2; k <= x; k++) r *= k;
  return r;
}

// ───────────────────────── Engine ─────────────────────────

export function defaultSettings() {
  return { decimalSeparator: ".", groupingSeparator: ",", decimals: 2, trimZeros: true, dateFormat: "dmy" };
}

export class Engine {
  constructor(rates) {
    this.rates = rates;
    this.registry = new UnitRegistry(rates);
    this.settings = defaultSettings();
    this.lastVariables = [];
    this.now = () => new Date();       // overridable in tests
    this.timeZone = null;              // null = system zone
  }

  evaluate(lines, recordVariables = false) {
    const now = this.now(), tz = this.timeZone || localTz();
    const off = tzOffset(tz, now), t = Math.floor(now.getTime() / 1000) + off;
    const ctx = { vars: new Map(), prev: null, block: [], now, localTz: tz,
      today: Math.floor(t / 86400), nowSec: Math.floor((((t % 86400) + 86400) % 86400) / 60) * 60 };
    const res = lines.map((l) => this.evalLine(l, ctx));
    if (recordVariables) this.lastVariables = [...ctx.vars.keys()];
    return res;
  }
  evaluateOne(expr) { return this.evaluate([expr])[0]; }

  evalLine(line, ctx) {
    const res = { value: null, display: null, error: null, warning: null, highlights: [] };
    const n = line.length;
    let start = 0;
    while (start < n && (line[start] === " " || line[start] === "\t")) start++;
    if (start === n) { ctx.block = []; return res; }
    if (line[start] === "#" || line.startsWith("//", start)) {
      res.highlights.push({ start, end: n, kind: "comment" });
      ctx.block = [];
      return res;
    }
    let end = n;
    const ci = line.indexOf("//", start);
    if (ci >= 0) { end = ci; res.highlights.push({ start: ci, end: n, kind: "comment" }); }
    let colon = line.indexOf(":", start);
    while (colon > 0 && /\d/.test(line[colon - 1] || "") && /\d/.test(line[colon + 1] || "")) colon = line.indexOf(":", colon + 1);
    if (colon >= 0 && colon < end) {
      const pre = line.slice(start, colon);
      const hasLetter = [...pre].some((ch) => isLetter(ch.charCodeAt(0)));
      if (hasLetter && !/[=(]/.test(pre)) {
        res.highlights.push({ start, end: colon + 1, kind: "label" });
        start = colon + 1;
      }
    }
    const body = line.slice(start, end);
    let parser = null;
    try {
      const toks = new Lexer(body, start, this.settings).tokenize();
      for (const t of toks) if (t.kind === "num" || t.kind === "clock" || t.kind === "date") res.highlights.push({ start: t.start, end: t.end, kind: "number" });
      parser = new Parser(toks, this.registry, ctx);
      parser.decimals = this.settings.decimals;
      parser.fmt = (x) => this.number(x, this.settings.decimals);
      parser.fmtValue = (v) => { try { return this.format(v); } catch { return String(v.num); } };
      const v = parser.parseLine();
      if (v) {
        res.value = v;
        res.display = this.format(v);
        ctx.prev = v;
        ctx.block.push(v);
      }
      res.highlights.push(...parser.marks);
      res.warning = parser.warnings[0] || null;
    } catch (e) {
      res.value = null; res.display = null;
      res.error = e instanceof CalcError ? e.message : String(e && e.message || e);
      if (parser) res.highlights.push(...parser.marks);
    }
    return res;
  }

  format(v) {
    if (v.kind === "clock") return this.formatClock(v);
    if (v.kind === "date") return this.formatDate(v.num);
    if (v.format === "hms") return this.formatDuration(v.num, v.showSec);
    if (!isFinite(v.num)) throw new CalcError(Number.isNaN(v.num) ? tr("noResult") : tr("tooBig"));
    const suffix = v.unit ? (v.unit.id === "°" ? "°" : " " + v.unit.id) : "";
    if (v.format === "hex" || v.format === "bin" || v.format === "oct") {
      if (v.num !== Math.round(v.num) || Math.abs(v.num) >= 9e15) throw new CalcError(tr("intOnly"));
      const radix = v.format === "hex" ? 16 : v.format === "bin" ? 2 : 8;
      const prefix = v.format === "hex" ? "0x" : v.format === "bin" ? "0b" : "0o";
      return (v.num < 0 ? "-" : "") + prefix + Math.abs(v.num).toString(radix).toUpperCase() + suffix;
    }
    if (v.format === "sci") return this.sci(v.num, Math.max(this.settings.decimals, 3)) + suffix;
    const dec = v.unit && v.unit.isCrypto ? Math.max(this.settings.decimals, 8) : this.settings.decimals;
    let s = this.number(v.num, dec);
    if (v.isPercent) s += "%";
    if (v.unit && ["day", "week", "month", "year"].includes(v.unit.id) && Math.abs(v.num) !== 1) return s + suffix + "s";
    return s + suffix;
  }

  formatClock(v) {
    const total = Math.round(v.num);
    const dayOff = Math.floor(total / 86400), sec = total - dayOff * 86400;
    const two = (n) => String(n).padStart(2, "0");
    let s = `${two(Math.floor(sec / 3600))}:${two(Math.floor((sec % 3600) / 60))}`;
    if (sec % 60 || v.showSec) s += ":" + two(sec % 60);
    if (v.tz) s += " " + v.tz.label;
    if (dayOff) s += " " + tr("dayOff", (dayOff > 0 ? "+" : "−") + Math.abs(dayOff));
    return s;
  }
  formatDate(days) {
    const [y, m, d] = civilFromDays(days);
    const two = (n) => String(n).padStart(2, "0");
    const f = this.settings.dateFormat;
    const s = f === "mdy" ? `${two(m)}/${two(d)}/${y}` : f === "ymd" ? `${y}-${two(m)}-${two(d)}` : `${two(d)}.${two(m)}.${y}`;
    return s + ", " + tr("wd" + weekday(days));
  }
  /** Durations as H:MM (H:MM:SS when seconds matter): 9:15, -9:15, 22:00:00, 36:30. */
  formatDuration(sec, showSec = false) {
    const sign = sec < 0 ? "-" : "";
    const t = Math.round(Math.abs(sec));
    const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    const two = (n) => String(n).padStart(2, "0");
    return sign + `${h}:${two(m)}` + (s || showSec ? ":" + two(s) : "");
  }

  get groupSep() {
    const g = this.settings.groupingSeparator;
    if (g === this.settings.decimalSeparator) return this.settings.decimalSeparator === "," ? " " : ",";
    return g;
  }

  number(x, decimals) {
    if (!isFinite(x)) return Number.isNaN(x) ? "—" : x > 0 ? "∞" : "-∞";
    const ax = Math.abs(x);
    if (ax >= 1e15) return this.sci(x, 6);
    let d = Math.max(0, Math.min(decimals, 12));
    let trim = this.settings.trimZeros;
    if (ax !== 0 && ax < Math.pow(10, -d) / 2) {
      if (ax < 1e-9) return this.sci(x, 4);
      d = Math.floor(-Math.log10(ax)) + 4;
      trim = true;
    }
    const s = ax.toFixed(d);
    let [intPart, frac = ""] = s.split(".");
    if (trim) frac = frac.replace(/0+$/, "");
    const g = this.groupSep;
    if (g && intPart.length > 3) intPart = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, g);
    let res = intPart + (frac ? this.settings.decimalSeparator + frac : "");
    if (x < 0 && Number(s) !== 0) res = "-" + res;
    return res;
  }

  sci(x, digits) {
    let [mant, exp] = x.toExponential(digits).split("e");
    if (mant.includes(".")) mant = mant.replace(/0+$/, "").replace(/\.$/, "");
    return mant.replace(".", this.settings.decimalSeparator) + "e" + Number(exp);
  }

  completions(prefix) {
    const p = prefix.toLowerCase();
    if (!p) return [];
    const words = new Set([...this.registry.completionWords, ...Object.keys(FUNC_ALIASES),
      "in", "to", "sum", "prev", "avg", "hex", "bin", "oct", "sci", "pi", "mod", "of", "off", "итого", "разом", ...this.lastVariables]);
    return [...words].filter((w) => w.toLowerCase().startsWith(p) && w.length > prefix.length)
      .sort((a, b) => a.length - b.length || a.localeCompare(b));
  }
}
