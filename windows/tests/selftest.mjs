// Port of Sources/exocalc-cli/SelfTest.swift — run: node tests/selftest.mjs
import { Engine, RateStore, L10n } from "../src/engine.js";

L10n.lang = "ru";
const rates = new RateStore();
rates.setTestRates({ USD: 1, EUR: 0.5, UAH: 40, BTC: 0.00001 });
const e = new Engine(rates);
let ok = true, count = 0;
const cases = [
 [
  "2 + 3 * 4",
  "14"
 ],
 [
  "(2 + 3) * 4",
  "20"
 ],
 [
  "2^10",
  "1,024"
 ],
 [
  "-2^2",
  "-4"
 ],
 [
  "10 mod 3",
  "1"
 ],
 [
  "5!",
  "120"
 ],
 [
  "14/105",
  "0.13"
 ],
 [
  "20/72=0.2777777778",
  "0.28"
 ],
 [
  "19,480.00+2150",
  "21,630"
 ],
 [
  "800×12",
  "9,600"
 ],
 [
  "800x12",
  "9,600"
 ],
 [
  "320000/45",
  "7,111.11"
 ],
 [
  "1/3",
  "0.33"
 ],
 [
  "0.0004",
  "0.0004"
 ],
 [
  "100 + 15%",
  "115"
 ],
 [
  "250 - 20%",
  "200"
 ],
 [
  "15% of 800",
  "120"
 ],
 [
  "20% off 1500",
  "1,200"
 ],
 [
  "5% on 200",
  "210"
 ],
 [
  "50%",
  "50%"
 ],
 [
  "sqrt(144)",
  "12"
 ],
 [
  "√16",
  "4"
 ],
 [
  "sqrt 81",
  "9"
 ],
 [
  "sin(30°)",
  "0.5"
 ],
 [
  "round(3.14159; 1)",
  "3.1"
 ],
 [
  "max(3; 9; 4)",
  "9"
 ],
 [
  "2 pi",
  "6.28"
 ],
 [
  "log(1000)",
  "3"
 ],
 [
  "600 usd in uah",
  "24,000 UAH"
 ],
 [
  "$20 + €15",
  "50 USD"
 ],
 [
  "100 eur в грн",
  "8,000 UAH"
 ],
 [
  "1000 грн to usd",
  "25 USD"
 ],
 [
  "1 btc in usd",
  "100,000 USD"
 ],
 [
  "usd in uah",
  "40 UAH"
 ],
 [
  "18 Celsius in Fahrenheit",
  "64.4 °F"
 ],
 [
  "100 °F in °C",
  "37.78 °C"
 ],
 [
  "1 km + 500 m",
  "1.5 km"
 ],
 [
  "5 ft in cm",
  "152.4 cm"
 ],
 [
  "1 GB in MB",
  "1,000 MB"
 ],
 [
  "90 min in h",
  "1.5 h"
 ],
 [
  "100 km/h in m/s",
  "27.78 m/s"
 ],
 [
  "3 m * 4 m",
  "12 m²"
 ],
 [
  "120 km / 1.5 h",
  "80 km/h"
 ],
 [
  "10 соток в м2",
  "1,000 m²"
 ],
 [
  "5 in in cm",
  "12.7 cm"
 ],
 [
  "12 in",
  "12 in"
 ],
 [
  "70 kg in lb",
  "154.32 lb"
 ],
 [
  "1 gal in l",
  "3.79 l"
 ],
 [
  "255 in hex",
  "0xFF"
 ],
 [
  "0xFF + 1",
  "256"
 ],
 [
  "10 in bin",
  "0b1010"
 ],
 [
  "5k",
  "5,000"
 ],
 [
  "2.5 млн",
  "2,500,000"
 ],
 [
  "Аренда: 2000",
  "2,000"
 ],
 [
  "1/3 // треть",
  "0.33"
 ],
 [
  "300,000.00*2",
  "600,000"
 ],
 [
  "300 000,00",
  "300,000"
 ],
 [
  "30000,00*8",
  "240,000"
 ],
 [
  "1,500",
  "1,500"
 ],
 [
  "1.5 + 1,5",
  "3"
 ],
 [
  "round(3.14159,1)",
  "3.1"
 ],
 [
  "1 000 000 / 4",
  "250,000"
 ],
 [
  "18 цельсия в фаренгейтах",
  "64.4 °F"
 ],
 [
  "18 градусов цельсия в фаренгейтах",
  "64.4 °F"
 ],
 [
  "18 цельсія у фаренгейтах",
  "64.4 °F"
 ],
 [
  "100 долларов в гривнах",
  "4,000 UAH"
 ],
 [
  "600 доларів у гривнях",
  "24,000 UAH"
 ],
 [
  "100 км в милях",
  "62.14 mi"
 ],
 [
  "70 кг в фунтах",
  "154.32 lb"
 ],
 [
  "1.5 часа в минутах",
  "90 min"
 ],
 [
  "1.5 години у хвилинах",
  "90 min"
 ],
 [
  "120 км / 1.5 години",
  "80 km/h"
 ],
 [
  "15% від 800",
  "120"
 ],
 [
  "685,00-,99",
  "684.01"
 ],
 [
  "88+1=89+1=90+55+8=153",
  "153"
 ],
 [
  "88/8=11*2=22+4",
  "26"
 ],
 [
  "10=+5=*2",
  "30"
 ],
 [
  "5==",
  "5"
 ],
 [
  "1 usd in uah = 99 UAH",
  "40 UAH"
 ],
 [
  "2=^10",
  "1,024"
 ],
 [
  "685.00 - .99",
  "684.01"
 ],
 [
  ",5 * 4",
  "2"
 ],
 [
  "max(1; ,5)",
  "1"
 ],
 [
  "100 євро у грн",
  "8,000 UAH"
 ]
];
for (const [expr, want] of cases) {
  count++;
  const r = e.evaluateOne(expr);
  const got = r.display ?? "ERR: " + r.error;
  if (got !== want) { ok = false; console.log(`✗ ${expr}\n    want: ${want}\n    got:  ${got}`); }
}
const sheet = ["a = 10", "b = 5", "a * b", "", "x: 100", "y: 50", "sum", "prev * 2", "# заголовок", "avg"];
const wantSheet = ["10", "5", "50", null, "100", "50", "150", "300", null, "0"];
e.evaluate(sheet).forEach((r, i) => { count++; if (r.display !== wantSheet[i]) { ok = false; console.log(`✗ sheet «${sheet[i]}»: want ${wantSheet[i]} got ${r.display ?? r.error}`); } });
e.settings = { decimalSeparator: ",", groupingSeparator: " ", decimals: 2, trimZeros: true };
for (const [expr, want] of [["1 234,5 + 0,5", "1 235"], ["2,5 * 2", "5"], ["10/3", "3,33"], ["max(1; 2)", "2"], ["1.500", "1 500"], ["300,000.00*2", "600 000"]]) {
  count++;
  const r = e.evaluateOne(expr);
  const got = r.display ?? "ERR: " + r.error;
  if (got !== want) { ok = false; console.log(`✗ [comma] ${expr}\n    want: ${want}\n    got:  ${got}`); }
}
console.log(ok ? `✓ All ${count} tests passed` : "FAILED");
process.exit(ok ? 0 : 1);
