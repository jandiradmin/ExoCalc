// Date/time helpers shared by the engine. Keep in sync with DateTime.swift.

/** Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's algorithm). */
export function daysFromCivil(y, m, d) {
  y -= m <= 2 ? 1 : 0;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

export function civilFromDays(z) {
  z += 719468;
  const era = Math.floor(z / 146097);
  const doe = z - era * 146097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return [yoe + era * 400 + (m <= 2 ? 1 : 0), m, d];
}

export const daysInMonth = (y, m) => [31, (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];

export function validDate(y, m, d) {
  return y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m);
}

/** Calendar month addition: 31 Jan + 1 month = 28/29 Feb. */
export function addMonths(days, n) {
  const [y, m, d] = civilFromDays(days);
  const total = y * 12 + (m - 1) + n;
  const ny = Math.floor(total / 12), nm = total - ny * 12 + 1;
  return daysFromCivil(ny, nm, Math.min(d, daysInMonth(ny, nm)));
}

/** 0 = Sunday … 6 = Saturday. */
export const weekday = (days) => (((days + 4) % 7) + 7) % 7;

export const MONTHS = {
  january: 1, jan: 1, february: 2, feb: 2, march: 3, mar: 3, april: 4, apr: 4, may: 5, june: 6, jun: 6,
  july: 7, jul: 7, august: 8, aug: 8, september: 9, sep: 9, sept: 9, october: 10, oct: 10, november: 11, nov: 11,
  december: 12, dec: 12,
  "январь": 1, "января": 1, "янв": 1, "февраль": 2, "февраля": 2, "фев": 2, "март": 3, "марта": 3,
  "апрель": 4, "апреля": 4, "апр": 4, "май": 5, "мая": 5, "июнь": 6, "июня": 6, "июн": 6,
  "июль": 7, "июля": 7, "июл": 7, "август": 8, "августа": 8, "авг": 8, "сентябрь": 9, "сентября": 9, "сен": 9,
  "октябрь": 10, "октября": 10, "окт": 10, "ноябрь": 11, "ноября": 11, "ноя": 11, "декабрь": 12, "декабря": 12, "дек": 12,
  "січень": 1, "січня": 1, "лютий": 2, "лютого": 2, "березень": 3, "березня": 3, "квітень": 4, "квітня": 4,
  "травень": 5, "травня": 5, "червень": 6, "червня": 6, "липень": 7, "липня": 7, "серпень": 8, "серпня": 8,
  "вересень": 9, "вересня": 9, "жовтень": 10, "жовтня": 10, "листопад": 11, "листопада": 11, "грудень": 12, "грудня": 12,
};

export const DAY_WORDS = {
  today: 0, "сегодня": 0, "сьогодні": 0,
  tomorrow: 1, "завтра": 1,
  yesterday: -1, "вчера": -1, "вчора": -1,
};
export const NOW_WORDS = new Set(["now", "сейчас", "зараз"]);
export const UNTIL_WORDS = new Set(["until", "till", "до"]);

/** Time zones for "15:00 Kyiv in LA". alias → [IANA id, label]. */
const Z = (id, label, aliases) => aliases.map((a) => [a, [id, label]]);
export const ZONES = Object.fromEntries([
  ...Z("Europe/Kyiv", "Kyiv", ["kyiv", "kiev", "киев", "київ", "киеве", "києві",  "ukraine", "украина", "україна", "kherson", "херсон", "odesa", "odessa", "одесса", "одеса", "lviv", "львов", "львів", "kharkiv", "харьков", "харків", "dnipro", "днепр", "дніпро"]),
  ...Z("America/Los_Angeles", "LA", ["la", "los angeles", "лос анджелес", "лос-анджелес", "pst", "pdt", "pacific", "sf", "san francisco", "сан франциско", "seattle", "сиэтл", "las vegas", "лас вегас"]),
  ...Z("America/New_York", "New York", ["ny", "nyc", "new york", "нью йорк", "нью-йорк", "нью йорке", "нью-йорке", "нью-йорку", "est", "edt", "eastern", "miami", "майами", "washington", "вашингтон", "boston"]),
  ...Z("America/Chicago", "Chicago", ["chicago", "чикаго", "cdt", "central"]),
  ...Z("America/Denver", "Denver", ["denver", "денвер", "mst", "mdt", "mountain"]),
  ...Z("America/Toronto", "Toronto", ["toronto", "торонто"]),
  ...Z("UTC", "UTC", ["utc", "gmt", "zulu"]),
  ...Z("Europe/London", "London", ["london", "лондон", "лондоне", "лондоні", "uk time", "bst"]),
  ...Z("Europe/Warsaw", "Warsaw", ["warsaw", "варшава", "варшаве", "варшаві", "poland", "польша", "польща"]),
  ...Z("Europe/Berlin", "Berlin", ["berlin", "берлин", "берлін", "берлине", "берліні", "germany", "германия", "німеччина", "cet", "cest"]),
  ...Z("Europe/Paris", "Paris", ["paris", "париж", "париже", "парижі"]),
  ...Z("Europe/Madrid", "Madrid", ["madrid", "мадрид"]),
  ...Z("Europe/Rome", "Rome", ["rome", "рим"]),
  ...Z("Europe/Prague", "Prague", ["prague", "прага"]),
  ...Z("Europe/Vienna", "Vienna", ["vienna", "вена", "відень"]),
  ...Z("Europe/Bucharest", "Bucharest", ["bucharest", "бухарест"]),
  ...Z("Europe/Chisinau", "Chisinau", ["chisinau", "кишинев", "кишинів"]),
  ...Z("Europe/Istanbul", "Istanbul", ["istanbul", "стамбул", "turkey", "турция", "туреччина"]),
  ...Z("Asia/Tbilisi", "Tbilisi", ["tbilisi", "тбилиси", "тбілісі"]),
  ...Z("Asia/Jerusalem", "Tel Aviv", ["tel aviv", "тель авив", "israel", "израиль", "ізраїль"]),
  ...Z("Asia/Dubai", "Dubai", ["dubai", "дубай", "uae", "оаэ"]),
  ...Z("Asia/Kolkata", "India", ["india", "индия", "індія", "delhi", "mumbai"]),
  ...Z("Asia/Shanghai", "Beijing", ["beijing", "shanghai", "пекин", "пекін", "шанхай", "china", "китай"]),
  ...Z("Asia/Tokyo", "Tokyo", ["tokyo", "токио", "токіо", "japan", "япония", "японія"]),
  ...Z("Australia/Sydney", "Sydney", ["sydney", "сидней", "сідней"]),
]);

export function localTz() {
  try { return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"; } catch { return "UTC"; }
}

/** Seconds east of UTC for a zone at a moment. */
export function tzOffset(tz, at) {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const p = Object.fromEntries(f.formatToParts(at).map((x) => [x.type, x.value]));
  const asUTC = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second);
  return Math.round((asUTC - Math.floor(at.getTime() / 1000) * 1000) / 1000);
}
