.pragma library

// Pure helpers shared by the data singletons and the views.

function clamp01(v) { return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0 }

function zeros(n) {
    var a = [];
    for (var i = 0; i < n; i++) a.push(0);
    return a;
}

// Returns a NEW array (so QML bindings notice), oldest sample first.
function push(arr, v, n) {
    var out = arr.slice(Math.max(0, arr.length - n + 1));
    out.push(clamp01(v));
    while (out.length < n) out.unshift(0);
    return out;
}

// "1.5 MiB/s", "340K", "0B" -> bytes/s. Tolerant of net-status.sh's units.
function parseRate(str) {
    var m = /([\d.]+)\s*([kmgt]?)/i.exec(String(str).replace(/ /g, " "));
    if (!m) return 0;
    var n = parseFloat(m[1]);
    var p = m[2] ? "kmgt".indexOf(m[2].toLowerCase()) + 1 : 0;
    return isFinite(n) ? n * Math.pow(1024, p) : 0;
}

// Log scale so idle chatter stays flat: 1 KiB/s -> 0, ~10 MiB/s -> full
function rateLevel(b) {
    if (b <= 1024) return 0;
    return clamp01((Math.log(b) / Math.LN10 - 3) / 4);
}

// Latency on a log scale: 5 ms -> 0, 300 ms -> full. Timeouts read as full.
function latencyLevel(ms) {
    if (ms < 0) return 1;
    if (ms <= 5) return 0;
    return clamp01(Math.log(ms / 5) / Math.log(60));
}

// 1288490188 -> "1.20 GiB"
function bytes(b) {
    var units = ["B", "KiB", "MiB", "GiB", "TiB"], i = 0;
    b = Math.max(0, b || 0);
    while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
    return (i === 0 ? Math.round(b) : b.toFixed(b < 10 ? 2 : 1)) + " " + units[i];
}

function pad(n, w) { return String(n).padStart(w, "0") }

// 83 -> "1:23", 3723 -> "1:02:03"
function clock(t) {
    var s = Math.max(0, Math.floor(t || 0));
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
    return h > 0 ? h + ":" + pad(m, 2) + ":" + pad(sec, 2) : m + ":" + pad(sec, 2);
}

// Minutes -> "3h 12m" / "12m"
function minutes(min) {
    if (!(min >= 0)) return "";
    var h = Math.floor(min / 60), m = min % 60;
    return h > 0 ? h + "h " + pad(m, 2) + "m" : m + "m";
}

// Seconds -> "2d 4h" / "4h 12m" / "12m"
function span(sec) {
    var s = Math.max(0, Math.floor(sec || 0));
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + pad(m, 2) + "m" : m + "m";
}

// Seconds since boot -> "MET 002/04:12:33", the way NASA counts it.
function met(sec) {
    var s = Math.max(0, Math.floor(sec || 0));
    return "MET " + pad(Math.floor(s / 86400), 3) + "/" + pad(Math.floor(s % 86400 / 3600), 2)
         + ":" + pad(Math.floor(s % 3600 / 60), 2) + ":" + pad(s % 60, 2);
}

// Linear mix of two QML colors -> "#rrggbb" (assignable to any color property).
function mix(a, b, t) {
    function ch(x, y) {
        var v = Math.round((x + (y - x) * t) * 255);
        return Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0");
    }
    return "#" + ch(a.r, b.r) + ch(a.g, b.g) + ch(a.b, b.b);
}

// QML color -> CSS string for Canvas, with explicit alpha.
function css(c, alpha) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
         + Math.round(c.b * 255) + "," + (alpha === undefined ? 1 : alpha) + ")";
}

// Monday-first month grid: [0,0,1,2,...] where 0 = blank cell.
function monthGrid(year, month) {
    var lead = (new Date(year, month, 1).getDay() + 6) % 7;
    var days = new Date(year, month + 1, 0).getDate();
    var out = [];
    for (var i = 0; i < lead; i++) out.push(0);
    for (var d = 1; d <= days; d++) out.push(d);
    while (out.length % 7) out.push(0);
    return out;
}

// =====================================================================
//  Physics. Constants are CODATA 2018 exact/recommended values.
// =====================================================================

var C = 299792458;                 // speed of light, m/s
var H = 6.62607015e-34;            // Planck, J·s
var KB = 1.380649e-23;             // Boltzmann, J/K
var WIEN = 2.897771955e-3;         // Wien displacement constant, m·K
var AU = 1.495978707e11;           // astronomical unit, m
var MOON_DIST = 3.844e8;           // mean Earth–Moon distance, m
var PROTON = 1.67262192369e-27;    // proton mass, kg
var SUN_T = 5772;                  // solar effective temperature, K

// "1.5e-10" -> "1.5×10⁻¹⁰"
function sci(x, digits) {
    if (x === 0 || !isFinite(x)) return String(x);
    var e = Math.floor(Math.log(Math.abs(x)) / Math.LN10);
    var m = x / Math.pow(10, e);
    if (Number(m.toFixed(digits)) >= 10) { m /= 10; e += 1; }
    var sup = "⁰¹²³⁴⁵⁶⁷⁸⁹", s = "";
    var es = String(Math.abs(e));
    for (var i = 0; i < es.length; i++) s += sup[Number(es[i])];
    return m.toFixed(digits) + "×10" + (e < 0 ? "⁻" : "") + s;
}

// 12345.6 -> "12,346"
function grouped(n) { return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ","); }

// ---------------- stars ----------------

// CPU load 0..1 -> surface temperature on a log scale:
// idle = 2,000 K (an L-type brown dwarf), flat out = 40,000 K (an O star).
function loadToKelvin(load) { return 2000 * Math.pow(20, clamp01(load)); }

// Harvard classes with their temperature ranges (K). Subclass 0 is the hot end.
var CLASSES = [
    ["O", 30000, 50000], ["B", 10000, 30000], ["A", 7500, 10000], ["F", 6000, 7500],
    ["G", 5200, 6000],   ["K", 3700, 5200],   ["M", 2400, 3700],  ["L", 1300, 2400]
];
function spectralClass(T) {
    for (var i = 0; i < CLASSES.length; i++) {
        var c = CLASSES[i];
        if (T >= c[1] || i === CLASSES.length - 1) {
            var sub = Math.floor(10 * (c[2] - T) / (c[2] - c[1]));
            return c[0] + Math.max(0, Math.min(9, sub));
        }
    }
}
// Luminosity class: a busy CPU swells off the main sequence.
function luminosityClass(load) { return load < 0.6 ? "V" : load < 0.85 ? "III" : "Ia"; }
function luminosityName(lc) {
    return lc === "V" ? "main sequence" : lc === "III" ? "giant" : "supergiant";
}

// Blackbody temperature -> sRGB, Tanner Helland's fit to the CIE result.
// Good to a few percent over 1,000–40,000 K, which is plenty for a status bar.
function blackbody(T) {
    var t = Math.max(1000, Math.min(40000, T)) / 100, r, g, b;
    r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
    g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661
                : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
    function hx(v) { return Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0"); }
    return "#" + hx(r) + hx(g) + hx(b);
}

// Planck's law, spectral radiance per unit wavelength (W·sr⁻¹·m⁻³).
function planck(lambda, T) {
    var x = H * C / (lambda * KB * T);
    if (x > 700) return 0;
    return 2 * H * C * C / Math.pow(lambda, 5) / (Math.exp(x) - 1);
}
// n samples of B(λ,T) over [lo, hi] meters, normalized to their own peak.
function planckCurve(T, lo, hi, n) {
    var out = [], max = 0;
    for (var i = 0; i < n; i++) {
        var v = planck(lo + (hi - lo) * i / (n - 1), T);
        out.push(v);
        if (v > max) max = v;
    }
    return out.map(v => max > 0 ? v / max : 0);
}
function wienPeakNm(T) { return WIEN / T * 1e9; }

// ---------------- light ----------------

// meters -> "2,099 km" / "0.17 AU" / "1.3 light-hours"
function distance(m) {
    if (m < 1e3) return Math.round(m) + " m";
    if (m < 0.01 * AU) return grouped(m / 1000) + " km";
    return (m / AU).toFixed(m < AU ? 2 : 1) + " AU";
}
// How far light gets in `sec` seconds.
function lightDistance(sec) { return C * Math.max(0, sec); }

// The outermost planet whose orbit a distance (m) has passed, or "".
var PLANETS = [
    { name: "mercury", a: 0.387,  tint: "#a8a29a", r: 2.5 },
    { name: "venus",   a: 0.723,  tint: "#e8cf98", r: 3.5 },
    { name: "earth",   a: 1.000,  tint: "#6fa8dc", r: 3.5 },
    { name: "mars",    a: 1.524,  tint: "#d9774f", r: 2.5 },
    { name: "jupiter", a: 5.203,  tint: "#d8b48a", r: 5.5 },
    { name: "saturn",  a: 9.537,  tint: "#e3cf8d", r: 4.5, ring: true },
    { name: "uranus",  a: 19.19,  tint: "#9fd8df", r: 4.0 },
    { name: "neptune", a: 30.07,  tint: "#5b7fd6", r: 4.0 },
    { name: "pluto",   a: 39.48,  tint: "#c9b7a3", r: 2.0 },
    { name: "eris",    a: 67.86,  tint: "#e6e6e6", r: 2.0 }
];
function pastOrbit(m) {
    var au = m / AU, last = "";
    for (var i = 0; i < PLANETS.length; i++) if (PLANETS[i].a <= au) last = PLANETS[i].name;
    return last;
}
// Kepler's third law around one solar mass: T[yr] = a[AU]^1.5
function orbitalPeriod(aAU) { return Math.pow(aAU, 1.5); }
function years(y) {
    return y < 1 ? Math.round(y * 365.25) + " days" : y.toFixed(y < 10 ? 2 : 1) + " yr";
}
// seconds -> "8m 19s" / "4h 10m"
function hm(sec) {
    var s = Math.round(sec), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
    return h > 0 ? h + "h " + pad(m, 2) + "m" : m + "m " + pad(s % 60, 2) + "s";
}

// ---------------- information ----------------

// Landauer: erasing one bit at temperature T dissipates at least kT·ln2.
function landauerJoules(bytes, T) { return bytes * 8 * KB * (T || 300) * Math.LN2; }

// ---------------- time & sky ----------------

function julian(ms) { return ms / 86400000 + 2440587.5; }

function mod(a, n) { return ((a % n) + n) % n; }

// Greenwich mean sidereal time in hours (IAU 1982, low precision).
function gmst(jd) { return mod(18.697374558 + 24.06570982441908 * (jd - 2451545.0), 24); }
function lst(jd, lonDeg) { return mod(gmst(jd) + lonDeg / 15, 24); }

// hours -> "22:14" (or "22:14:03" with seconds)
function hours(h, withSeconds) {
    var s = Math.floor(mod(h, 24) * 3600);
    return pad(Math.floor(s / 3600), 2) + ":" + pad(Math.floor(s % 3600 / 60), 2)
         + (withSeconds ? ":" + pad(s % 60, 2) : "");
}

// Sun position, Astronomical Almanac low-precision formulae (~0.01°).
function sun(jd, latDeg, lonDeg) {
    var R = Math.PI / 180, n = jd - 2451545.0;
    var L = mod(280.460 + 0.9856474 * n, 360);
    var g = mod(357.528 + 0.9856003 * n, 360) * R;
    var lam = (L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * R;
    var eps = (23.439 - 0.0000004 * n) * R;
    var ra = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam));
    var dec = Math.asin(Math.sin(eps) * Math.sin(lam));
    var ha = lst(jd, lonDeg) * 15 * R - ra;
    var phi = latDeg * R;
    var alt = Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(ha));
    return { alt: alt / R, dec: dec / R };
}
function twilight(alt) {
    return alt > -0.833 ? "daylight"
         : alt > -6 ? "civil twilight"
         : alt > -12 ? "nautical twilight"
         : alt > -18 ? "astronomical twilight"
         : "full dark";
}

// Moon phase from the mean synodic month, anchored on the 2000-01-06 new moon.
// Good to well under a day, which is all a phase name needs.
function moon(jd) {
    var p = mod((jd - 2451550.1) / 29.530588853, 1);
    var names = ["new moon", "waxing crescent", "first quarter", "waxing gibbous",
                 "full moon", "waning gibbous", "last quarter", "waning crescent"];
    return {
        phase: p,                                       // 0 new, 0.5 full
        age: p * 29.530588853,                          // days since new
        illum: (1 - Math.cos(2 * Math.PI * p)) / 2,     // lit fraction
        name: names[Math.floor(mod(p * 8 + 0.5, 8))]
    };
}

// "#ffa757" -> "rgba(255,167,87,a)" for Canvas.
function hexA(hex, a) {
    var n = parseInt(String(hex).slice(1, 7), 16);
    return "rgba(" + (n >> 16 & 255) + "," + (n >> 8 & 255) + "," + (n & 255) + "," + a + ")";
}

// Seeded PRNG (mulberry32), so the starfield is the same sky every launch.
function rng(seed) {
    var a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) >>> 0;
        var t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// Nominal gain of a 0..1 mixer fraction, as amplitude dB.
function gainDb(v) {
    if (v <= 0) return "−∞ dB";
    var d = 20 * Math.log(v) / Math.LN10;
    return (Math.abs(d) < 0.05 ? "0" : d.toFixed(Math.abs(d) < 10 ? 1 : 0).replace("-", "−")) + " dB";
}
