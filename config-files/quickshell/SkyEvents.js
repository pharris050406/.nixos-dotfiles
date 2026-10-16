.pragma library
.import "SkyMath.js" as SM
.import "SkyData.js" as SD

// What's worth looking up for: meteor showers, the Moon passing planets and
// bright stars, planets meeting, moon phases, eclipses visible from here, and
// solstices/equinoxes. All computed locally from the same ephemeris as the
// sky; nothing is downloaded.

var DAY = 86400000;

// ---------------- meteor showers ----------------
// IMO working-list values (via the IMO/Wikipedia tables): activity window,
// peak solar longitude λ☉ (J2000), radiant at peak, entry speed V∞, ZHR, parent.
// Radiant drift (deg/day) and the activity slope B (ZHR falls by 10× every 1/B
// degrees of λ☉ from the peak) are approximate.
var SHOWERS = [
    { code: "QUA", name: "Quadrantids",          start: [12, 28], end: [1, 12],  peak: 283.15, ra: 229.5, dec: 49,  dra: 0.8,  ddec: -0.2,  v: 41, zhr: 80,  B: 1.8,   parent: "asteroid 2003 EH1" },
    { code: "LYR", name: "Lyrids",               start: [4, 14],  end: [4, 30],  peak: 32.32,  ra: 271.5, dec: 34,  dra: 1.1,  ddec: 0.0,   v: 49, zhr: 18,  B: 0.22,  parent: "comet C/1861 G1 Thatcher" },
    { code: "ETA", name: "η-Aquariids",          start: [4, 19],  end: [5, 28],  peak: 45.5,   ra: 337.5, dec: -1,  dra: 0.9,  ddec: 0.4,   v: 66, zhr: 50,  B: 0.08,  parent: "Halley's Comet" },
    { code: "SDA", name: "Southern δ-Aquariids", start: [7, 12],  end: [8, 23],  peak: 128,    ra: 340.5, dec: -16, dra: 0.8,  ddec: 0.18,  v: 41, zhr: 25,  B: 0.091, parent: "comet P/2008 Y12 (SOHO)" },
    { code: "CAP", name: "α-Capricornids",       start: [7, 3],   end: [8, 15],  peak: 128,    ra: 307.5, dec: -10, dra: 0.9,  ddec: 0.3,   v: 23, zhr: 5,   B: 0.1,   parent: "comet 169P/NEAT" },
    { code: "PER", name: "Perseids",             start: [7, 17],  end: [8, 24],  peak: 140.0,  ra: 48.0,  dec: 58,  dra: 1.35, ddec: 0.12,  v: 59, zhr: 100, B: 0.2,   parent: "comet 109P/Swift–Tuttle" },
    { code: "DRA", name: "Draconids",            start: [10, 6],  end: [10, 10], peak: 195.4,  ra: 262.5, dec: 54,  dra: 0,    ddec: 0,     v: 20, zhr: 5,   B: 0.4,   parent: "comet 21P/Giacobini–Zinner" },
    { code: "STA", name: "Southern Taurids",     start: [9, 20],  end: [11, 20], peak: 223,    ra: 52.5,  dec: 15,  dra: 0.8,  ddec: 0.2,   v: 27, zhr: 7,   B: 0.026, parent: "Comet Encke" },
    { code: "ORI", name: "Orionids",             start: [10, 2],  end: [11, 7],  peak: 208,    ra: 94.5,  dec: 16,  dra: 0.7,  ddec: 0.1,   v: 66, zhr: 20,  B: 0.12,  parent: "Halley's Comet" },
    { code: "NTA", name: "Northern Taurids",     start: [10, 20], end: [12, 10], peak: 230,    ra: 58.5,  dec: 22,  dra: 0.8,  ddec: 0.15,  v: 29, zhr: 5,   B: 0.026, parent: "asteroid 2004 TG10" },
    { code: "LEO", name: "Leonids",              start: [11, 6],  end: [11, 30], peak: 235.27, ra: 151.5, dec: 22,  dra: 0.7,  ddec: -0.42, v: 71, zhr: 15,  B: 0.39,  parent: "comet 55P/Tempel–Tuttle" },
    { code: "GEM", name: "Geminids",             start: [12, 4],  end: [12, 20], peak: 262.2,  ra: 112.5, dec: 33,  dra: 1.0,  ddec: -0.15, v: 35, zhr: 150, B: 0.39,  parent: "asteroid 3200 Phaethon" },
    { code: "URS", name: "Ursids",               start: [12, 17], end: [12, 26], peak: 270.7,  ra: 217.5, dec: 76,  dra: 0,    ddec: 0,     v: 33, zhr: 10,  B: 0.6,   parent: "comet 8P/Tuttle" }
];
var SPORADIC_ZHR = 6;           // the random background, every night of the year

function wrap180(x) { return SM.mod(x + 180, 360) - 180; }

// Calendar date -> approximate λ☉ (good to a degree or two; fine for windows)
function dateLon(md) {
    var doy = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][md[0] - 1] + md[1];
    return SM.mod((doy - 79.5) * 0.98565, 360);
}

// Activity of a shower right now: { zhr, ra, dec, days from peak } or null.
function activity(sh, jd) {
    var lam = SM.sunLonJ2000(jd, SD.PLANETS);
    var a = dateLon(sh.start), b = dateLon(sh.end);
    var inside = a <= b ? (lam >= a && lam <= b) : (lam >= a || lam <= b);
    if (!inside) return null;
    var dl = wrap180(lam - sh.peak), days = dl / 0.98565;
    return {
        zhr: sh.zhr * Math.pow(10, -sh.B * Math.abs(dl)),
        ra: SM.mod(sh.ra + sh.dra * days, 360),
        dec: sh.dec + sh.ddec * days,
        days: days
    };
}
function activeShowers(jd) {
    var out = [];
    for (var i = 0; i < SHOWERS.length; i++) {
        var a = activity(SHOWERS[i], jd);
        if (a && a.zhr >= 1) out.push({ shower: SHOWERS[i], zhr: a.zhr, ra: a.ra, dec: a.dec, days: a.days });
    }
    return out;
}

// ---------------- sky state at an instant ----------------
var STARS = [   // ecliptic stars and clusters the Moon and planets pass
    { name: "Regulus",   ra: 152.093, dec: 11.967 },
    { name: "Spica",     ra: 201.298, dec: -11.161 },
    { name: "Antares",   ra: 247.352, dec: -26.432 },
    { name: "Aldebaran", ra: 68.980,  dec: 16.509 },
    { name: "the Pleiades", ra: 56.75, dec: 24.12, r: 0.5 },     // r: the cluster's bright core, degrees
    { name: "the Beehive",  ra: 130.10, dec: 19.67, r: 0.5 }
];
var PLANET_NAMES = ["mercury", "venus", "mars", "jupiter", "saturn"];

function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
function compass(az) {
    return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(SM.mod(az, 360) / 45) % 8];
}

function snapshot(ms, lat, lon) {
    var jd = SM.julian(ms), Hz = SM.horizon(jd, lat, lon), A = SM.mm(Hz, SM.precession(jd));
    var o = { ms: ms, jd: jd, bodies: {} };
    var pl = SM.planets(jd, SD.PLANETS);
    for (var i = 0; i < pl.length; i++)
        o.bodies[pl[i].name] = { w: SM.mul(A, pl[i].v), dist: pl[i].dist, mag: pl[i].mag };
    var mo = SM.moon(jd, lat, lon);
    o.bodies.moon = { w: SM.mul(Hz, mo.v), distKm: mo.distKm };
    for (var s = 0; s < STARS.length; s++)
        o.bodies[STARS[s].name] = { w: SM.mul(A, SM.vec(STARS[s].ra, STARS[s].dec)), star: true };
    return o;
}
function alt(w) { return Math.asin(Math.max(-1, Math.min(1, w[2]))) / SM.D2R; }
function sep(a, b) { return Math.acos(Math.max(-1, Math.min(1, SM.dot(a, b)))) / SM.D2R; }

// ---------------- the search ----------------
// Events between ms0 and ms0 + days. Each:
//   { id, kind, ms, title, body, short, notify, notifyAt }
function upcoming(ms0, days, lat, lon) {
    var out = [];
    var step = 3600e3, n = Math.ceil(days * 24) + 2;
    var base = Math.floor(ms0 / step) * step;            // on the hour, so times come out round
    var snaps = [];
    for (var i = 0; i < n; i++) snaps.push(snapshot(base + i * step, lat, lon));
    var dark = function (s) { return alt(s.bodies.sun.w) < -6; };
    var fmt = function (ms) { var d = new Date(ms); return pad(d.getHours()) + ":" + pad(d.getMinutes()); };
    var day = function (ms) {
        var d = new Date(ms);
        return ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"][d.getMonth()] + " " + d.getDate();
    };
    var tonight = function (ms) {
        var d = new Date(ms), now = new Date(ms0);
        var dd = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / DAY);
        var early = d.getHours() < 6;   // pre-dawn belongs to the previous evening's night
        if (dd === 0) return early ? "before dawn" : d.getHours() >= 17 ? "tonight" : "today";
        if (dd === 1) return early ? "tonight, before dawn" : "tomorrow";
        return day(ms);
    };

    // ---- close approaches: Moon–planet, Moon–star, planet–planet, planet–star ----
    var pairs = [];
    PLANET_NAMES.forEach(p => pairs.push(["moon", p, 5]));
    STARS.forEach(s => pairs.push(["moon", s.name, 3]));
    for (var a = 0; a < PLANET_NAMES.length; a++) {
        for (var b = a + 1; b < PLANET_NAMES.length; b++) pairs.push([PLANET_NAMES[a], PLANET_NAMES[b], 3]);
        STARS.forEach(s => pairs.push([PLANET_NAMES[a], s.name, 2]));
    }
    pairs.forEach(pr => {
        var seps = snaps.map(s => sep(s.bodies[pr[0]].w, s.bodies[pr[1]].w));
        for (var k = 1; k < n - 1; k++) {
            if (!(seps[k] <= seps[k - 1] && seps[k] < seps[k + 1]) || seps[k] > pr[2]) continue;
            // best moment to look within ±8 h: both ≥ 8° up in a dark sky, closest together
            var best = -1, bestSep = 1e9;
            for (var j = Math.max(0, k - 8); j <= Math.min(n - 1, k + 8); j++) {
                var sj = snaps[j], A1 = alt(sj.bodies[pr[0]].w), A2 = alt(sj.bodies[pr[1]].w);
                if (A1 >= 8 && A2 >= 8 && dark(sj) && seps[j] < bestSep) { bestSep = seps[j]; best = j; }
            }
            if (best < 0) continue;                       // not visible from here
            var s = snaps[best];
            // The Moon moves its own width an hour: find the closest visible
            // moment to 5 min, which also catches it covering a star.
            if (pr[0] === "moon") {
                for (var dm = -60; dm <= 60; dm += 5) {
                    var sr = snapshot(snaps[best].ms + dm * 60e3, lat, lon);
                    if (!dark(sr) || alt(sr.bodies.moon.w) < 8 || alt(sr.bodies[pr[1]].w) < 8) continue;
                    var dr = sep(sr.bodies.moon.w, sr.bodies[pr[1]].w);
                    if (dr < bestSep) { bestSep = dr; s = sr; }
                }
            }
            var w = s.bodies[pr[1]].w, aa = SM.altaz(w);
            var other = pr[1], b2 = s.bodies[other], star = STARS.find(x => x.name === other);
            var extra = b2.star ? "" : " · " + cap(other) + " is " + b2.dist.toFixed(2) + " AU away, its light "
                + Math.round(b2.dist * 499.005 / 60) + " min old";
            var label = cap(pr[0]) + " " + bestSep.toFixed(1) + "° from " + (b2.star ? other : cap(other));
            var notify = !(pr[0] === "moon" && b2.star && bestSep > 2);   // wide Moon–star pairs: listed, not announced
            if (pr[0] === "moon" && star) {
                var rMoon = Math.asin(1737.4 / s.bodies.moon.distKm) / SM.D2R;
                if (star.r && bestSep < rMoon + star.r) {
                    label = "Moon crosses " + other;
                    extra = " · it covers the cluster's stars one by one; binoculars help";
                    notify = true;
                } else if (!star.r && bestSep < rMoon) {
                    label = "Moon covers " + other;
                    extra = " · the star vanishes in an instant at the Moon's edge: no lunar air to dim it first";
                    notify = true;
                }
            }
            var occ = label.indexOf("° from") < 0;
            out.push({
                id: "conj-" + pr[0] + "-" + pr[1] + "-" + day(s.ms).replace(" ", ""),
                kind: "conjunction", ms: s.ms, title: label,
                body: tonight(s.ms) + (occ ? ", mid-way around " : " around ") + fmt(s.ms) + ", " + compass(aa.az) + " "
                    + Math.round(aa.alt) + "° up" + extra,
                short: day(s.ms) + " · " + label.toLowerCase(),
                notify: notify
            });
        }
    });

    // ---- moon phases (geocentric elongation of date) ----
    var elong = function (ms) {
        var jd = SM.julian(ms);
        return SM.mod(SM.moonEcl(jd).lam - SM.sunLonOfDate(jd, SD.PLANETS), 360);
    };
    var names = ["new moon", "first quarter", "full moon", "last quarter"];
    for (var q = 1; q < n; q++) {
        var e0 = elong(snaps[q - 1].ms), e1 = elong(snaps[q].ms);
        for (var kq = 0; kq < 4; kq++) {
            var t = kq * 90, d0 = wrap180(e0 - t), d1 = wrap180(e1 - t);
            if (!(d0 < 0 && d1 >= 0)) continue;
            var lo = snaps[q - 1].ms, hi = snaps[q].ms;
            for (var it = 0; it < 20; it++) {
                var mid = (lo + hi) / 2;
                if (wrap180(elong(mid) - t) < 0) lo = mid; else hi = mid;
            }
            var pms = Math.round(hi / 300000) * 300000;   // ±20 min accuracy: say it to 5 min
            var title = cap(names[kq]), extraP = "";
            if (kq === 2) {
                var mn = fullMoonName(pms, lat, lon);
                title = "Full moon" + (mn ? " (" + mn + ")" : "");
                var dist = 6378.14 / Math.sin(SM.moonEcl(SM.julian(pms)).par * SM.D2R);
                extraP = " · " + Math.round(dist / 1000) * 1000 + " km away" + (dist < 361000 ? ", a supermoon" : "");
                var lun = lunarEclipse(pms, lat, lon);
                if (lun) { lun.short = day(lun.ms) + " · " + lun.title.toLowerCase(); out.push(lun); }
            }
            if (kq === 0) {
                extraP = " · darkest skies of the month";
                var sol = solarEclipse(pms, lat, lon);
                if (sol) { sol.short = day(sol.ms) + " · " + sol.title.toLowerCase(); out.push(sol); }
            }
            out.push({
                id: "phase-" + kq + "-" + day(pms).replace(" ", ""),
                kind: "phase", ms: pms, title: title,
                body: tonight(pms) + " at " + fmt(pms) + extraP,
                short: day(pms) + " · " + title.toLowerCase(),
                notify: kq === 0 || kq === 2
            });
        }
    }

    // ---- solstices and equinoxes ----
    var seasons = ["March equinox", "June solstice", "September equinox", "December solstice"];
    for (var z = 1; z < n; z++) {
        var l0 = SM.sunLonOfDate(snaps[z - 1].jd, SD.PLANETS), l1 = SM.sunLonOfDate(snaps[z].jd, SD.PLANETS);
        for (var kz = 0; kz < 4; kz++) {
            if (!(wrap180(l0 - kz * 90) < 0 && wrap180(l1 - kz * 90) >= 0)) continue;
            var zl = snaps[z - 1].ms, zh = snaps[z].ms;
            for (var iz = 0; iz < 20; iz++) {
                var zm = (zl + zh) / 2;
                if (wrap180(SM.sunLonOfDate(SM.julian(zm), SD.PLANETS) - kz * 90) < 0) zl = zm; else zh = zm;
            }
            out.push({
                id: "season-" + kz + "-" + new Date(zh).getFullYear(), kind: "season", ms: zh,
                title: seasons[kz], body: tonight(zh) + " at " + fmt(zh) + " · the Sun crosses " + (kz * 90) + "° ecliptic longitude",
                short: day(zh) + " · " + seasons[kz].toLowerCase(), notify: true
            });
        }
    }

    // ---- meteor shower peaks ----
    SHOWERS.forEach(sh => {
        for (var m = 1; m < n; m++) {
            var la = SM.sunLonJ2000(snaps[m - 1].jd, SD.PLANETS), lb = SM.sunLonJ2000(snaps[m].jd, SD.PLANETS);
            if (!(wrap180(la - sh.peak) < 0 && wrap180(lb - sh.peak) >= 0)) continue;
            // best hour within the night around the peak: radiant highest in a dark sky
            var bestH = -1, bestScore = 0;
            for (var h = Math.max(0, m - 14); h <= Math.min(n - 1, m + 14); h++) {
                var act = activity(sh, snaps[h].jd);
                if (!act || alt(snaps[h].bodies.sun.w) > -12) continue;
                var Hz2 = SM.horizon(snaps[h].jd, lat, lon), A2 = SM.mm(Hz2, SM.precession(snaps[h].jd));
                var ra2 = alt(SM.mul(A2, SM.vec(act.ra, act.dec)));
                var score = act.zhr * Math.sin(Math.max(0, ra2) * SM.D2R);
                if (score > bestScore) { bestScore = score; bestH = h; }
            }
            if (bestH < 0) continue;
            var sb = snaps[bestH], mw = sb.bodies.moon.w;
            var ill = (1 - SM.dot(SM.norm(mw), SM.norm(sb.bodies.sun.w))) / 2;
            var act2 = activity(sh, sb.jd);
            var radAA = SM.altaz(SM.mul(SM.mm(SM.horizon(sb.jd, lat, lon), SM.precession(sb.jd)), SM.vec(act2.ra, act2.dec)));
            out.push({
                id: "shower-" + sh.code + "-" + new Date(sb.ms).getFullYear(), kind: "shower", ms: sb.ms,
                title: sh.name + " peak",
                body: "best " + tonight(sb.ms) + " around " + fmt(sb.ms) + ", radiant " + Math.round(radAA.alt) + "° up in the "
                    + compass(radAA.az) + " · up to ~" + Math.max(1, Math.round(bestScore)) + "/h under dark skies · moon "
                    + Math.round(ill * 100) + "% lit, " + (alt(mw) > 0 ? "up" : "down") + " · debris of " + sh.parent
                    + " hitting the air at " + sh.v + " km/s",
                short: day(sb.ms) + " · " + sh.name.toLowerCase() + " peak",
                notify: true
            });
            break;
        }
    });

    out.forEach(e => { e.notifyAt = notifyTime(e); });
    out.sort((x, y) => x.ms - y.ms);
    return out;
}

function pad(x) { return (x < 10 ? "0" : "") + x; }

// ---------------- when to say so ----------------
// Four hours ahead, except that anything before 8 a.m. is announced at 20:00
// the evening before: four hours ahead of a 5 a.m. shower peak, you're asleep.
function notifyTime(e) {
    if (e.kind === "season") return e.ms - 3 * 3600e3;
    var d = new Date(e.ms);
    if (d.getHours() < 8) return new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1, 20, 0, 0).getTime();
    return e.ms - 4 * 3600e3;
}
// How late an announcement is still worth making (the laptop was asleep).
function grace(e) { return (e.kind === "season" ? 12 : e.kind === "phase" ? 6 : 1) * 3600e3; }
// The id without its date, so a pairing whose best moment slides across
// midnight between two scans isn't announced twice.
function eventKey(id) { return id.replace(/-[a-z]{3}\d{1,2}$/, ""); }
// Events to announce at `now`. sent: [{ key, ms }] already announced.
function due(events, sent, now) {
    return events.filter(e => e.notify && now >= e.notifyAt && now < e.ms + grace(e)
        && !sent.some(x => x.key === eventKey(e.id) && Math.abs(x.ms - e.ms) < 36 * 3600e3));
}

// ---------------- full moon names ----------------
// Harvest Moon: the full moon nearest the September equinox; Hunter's: the next.
function fullMoonName(ms, lat, lon) {
    var d = new Date(ms), y = d.getFullYear();
    var eq = septemberEquinox(y);
    var dd = (ms - eq) / DAY;
    if (Math.abs(dd) <= 14.77) return "Harvest Moon";
    if (dd > 14.77 && dd <= 44.3) return "Hunter's Moon";
    return ["Wolf Moon", "Snow Moon", "Worm Moon", "Pink Moon", "Flower Moon", "Strawberry Moon",
            "Buck Moon", "Sturgeon Moon", "Corn Moon", "Hunter's Moon", "Beaver Moon", "Cold Moon"][d.getMonth()];
}
function septemberEquinox(y) {
    var lo = Date.UTC(y, 8, 15), hi = Date.UTC(y, 8, 30);
    for (var i = 0; i < 40; i++) {
        var mid = (lo + hi) / 2;
        if (wrap180(SM.sunLonOfDate(SM.julian(mid), SD.PLANETS) - 180) < 0) lo = mid; else hi = mid;
    }
    return hi;
}

// ---------------- eclipses ----------------
// Lunar: the Moon's distance from the centre of Earth's shadow vs the shadow's
// size (umbra ≈ 1.02(πM + π☉ − s☉), penumbra ≈ 1.02(πM + π☉ + s☉)).
function lunarEclipse(msFull, lat, lon) {
    var best = null;
    for (var dt = -4; dt <= 4; dt += 1 / 12) {
        var ms = msFull + dt * 3600e3, jd = SM.julian(ms), m = SM.moonEcl(jd);
        var sl = SM.sunLonOfDate(jd, SD.PLANETS);
        var d = Math.acos(Math.cos(m.bet * SM.D2R) * Math.cos((m.lam - sl - 180) * SM.D2R)) / SM.D2R;
        if (!best || d < best.d) best = { ms: ms, d: d, par: m.par };
    }
    var sS = 0.2666, pS = 0.00244, sM = 0.2725 * best.par;
    var umbra = 1.02 * (best.par + pS - sS), pen = 1.02 * (best.par + pS + sS);
    var kind = best.d < umbra - sM ? "Total" : best.d < umbra + sM ? "Partial" : best.d < pen + sM - 0.15 ? "Penumbral" : null;
    if (!kind) return null;
    var s = snapshot(best.ms, lat, lon), ma = alt(s.bodies.moon.w);
    if (ma < 0) return null;                                    // not visible from here
    var magU = (umbra + sM - best.d) / (2 * sM);
    var t = new Date(best.ms);
    return {
        id: "lunar-" + t.getFullYear() + "-" + t.getMonth() + "-" + t.getDate(), kind: "eclipse", ms: best.ms,
        title: kind + " lunar eclipse",
        body: "greatest around " + pad(t.getHours()) + ":" + pad(t.getMinutes()) + ", Moon " + Math.round(ma) + "° up in the "
            + compass(SM.altaz(s.bodies.moon.w).az)
            + (kind === "Penumbral" ? " · a subtle dimming" : " · " + Math.round(Math.min(1, magU) * 100) + "% into Earth's umbra"),
        short: "", notify: true
    };
}

// Solar, as seen from here: topocentric Sun–Moon separation vs their radii.
function solarEclipse(msNew, lat, lon) {
    var best = null;
    for (var dt = -5; dt <= 5; dt += 1 / 12) {
        var ms = msNew + dt * 3600e3, s = snapshot(ms, lat, lon);
        if (alt(s.bodies.sun.w) < 0) continue;
        var d = sep(s.bodies.sun.w, s.bodies.moon.w);
        if (!best || d < best.d) best = { ms: ms, d: d, s: s };
    }
    if (!best) return null;
    var rS = 0.2666 / best.s.bodies.sun.dist, rM = Math.asin(1737.4 / best.s.bodies.moon.distKm) / SM.D2R;
    if (best.d >= rS + rM) return null;
    var kind = best.d < rM - rS ? "Total" : best.d < rS - rM ? "Annular" : "Partial";
    var mag = (rS + rM - best.d) / (2 * rS);
    var t = new Date(best.ms);
    return {
        id: "solar-" + t.getFullYear() + "-" + t.getMonth() + "-" + t.getDate(), kind: "eclipse", ms: best.ms,
        title: kind + " solar eclipse visible here",
        body: "greatest around " + pad(t.getHours()) + ":" + pad(t.getMinutes()) + " · about " + Math.round(Math.min(1, mag) * 100)
            + "% of the Sun's diameter covered · never look directly; use eclipse glasses or a pinhole",
        short: "", notify: true
    };
}
