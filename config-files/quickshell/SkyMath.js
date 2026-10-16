.pragma library

// Positional astronomy for the sky layer. Everything works in unit vectors and
// 3x3 rotation matrices, so a whole catalog moves with one matrix per frame.
//
//   catalog (J2000 RA/Dec)  --precession-->  equator of date
//   --Earth rotation (local sidereal time)--> --latitude tilt--> east/north/up
//
// Accuracy, checked against PyEphem: stars and planets well under 0.1°,
// the Moon ~0.3° (low-precision series), which is a few pixels on screen.

var D2R = Math.PI / 180;

function mod(a, n) { return ((a % n) + n) % n; }

// ---------------- vectors & matrices ----------------
function vec(raDeg, decDeg) {
    var a = raDeg * D2R, d = decDeg * D2R, c = Math.cos(d);
    return [c * Math.cos(a), c * Math.sin(a), Math.sin(d)];
}
function mul(m, v) {
    return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
            m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
            m[6] * v[0] + m[7] * v[1] + m[8] * v[2]];
}
function mm(a, b) {            // a·b
    var r = [];
    for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++)
            r.push(a[3 * i] * b[j] + a[3 * i + 1] * b[3 + j] + a[3 * i + 2] * b[6 + j]);
    return r;
}
function rz(t) { var c = Math.cos(t), s = Math.sin(t); return [c, -s, 0, s, c, 0, 0, 0, 1]; }
function ry(t) { var c = Math.cos(t), s = Math.sin(t); return [c, 0, s, 0, 1, 0, -s, 0, c]; }
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
function norm(v) { var l = Math.sqrt(dot(v, v)); return [v[0] / l, v[1] / l, v[2] / l]; }

// ---------------- time ----------------
function julian(ms) { return ms / 86400000 + 2440587.5; }
function centuries(jd) { return (jd - 2451545.0) / 36525; }
function gmstDeg(jd) {         // IAU 1982, degrees
    var T = centuries(jd);
    return mod(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T * T, 360);
}
function obliquity(jd) { return (23.439291 - 0.0130042 * centuries(jd)) * D2R; }

// Precession J2000 -> mean equator of date (IAU 1976: zeta, z, theta).
function precession(jd) {
    var T = centuries(jd), as = D2R / 3600;
    var zeta = (2306.2181 * T + 0.30188 * T * T + 0.017998 * T * T * T) * as;
    var z = (2306.2181 * T + 1.09468 * T * T + 0.018203 * T * T * T) * as;
    var th = (2004.3109 * T - 0.42665 * T * T - 0.041833 * T * T * T) * as;
    return mm(rz(z), mm(ry(-th), rz(zeta)));
}

// Equator of date -> local east/north/up, for latitude and local sidereal time.
function horizon(jd, latDeg, lonDeg) {
    var lst = (gmstDeg(jd) + lonDeg) * D2R, phi = latDeg * D2R;
    var sp = Math.sin(phi), cp = Math.cos(phi);
    // after rz(-lst): (cosδ cosH, -cosδ sinH, sinδ)
    var tilt = [0, 1, 0,          // east  =  b
               -sp, 0, cp,        // north = -sinφ a + cosφ c
                cp, 0, sp];       // up    =  cosφ a + sinφ c
    return mm(tilt, rz(-lst));
}
function lstHours(jd, lonDeg) { return mod(gmstDeg(jd) + lonDeg, 360) / 15; }

// east/north/up vector -> {alt, az} in degrees (az from north through east)
function altaz(v) {
    return { alt: Math.asin(Math.max(-1, Math.min(1, v[2]))) / D2R, az: mod(Math.atan2(v[0], v[1]) / D2R, 360) };
}
function enu(altDeg, azDeg) {
    var a = altDeg * D2R, z = azDeg * D2R, c = Math.cos(a);
    return [c * Math.sin(z), c * Math.cos(z), Math.sin(a)];
}

// ---------------- planets (JPL "Approximate Positions of the Planets") ----------------
// Heliocentric ecliptic J2000 position (AU) from Keplerian elements.
function helio(p, T) {
    var e0 = p.el, r = p.rate;
    var a = e0[0] + r[0] * T, e = e0[1] + r[1] * T, I = (e0[2] + r[2] * T) * D2R;
    var L = e0[3] + r[3] * T, w = e0[4] + r[4] * T, N = e0[5] + r[5] * T;
    var omega = (w - N) * D2R, Om = N * D2R;
    var M = mod(L - w + 180, 360) - 180;                    // mean anomaly, deg
    var Mr = M * D2R, E = Mr + e * Math.sin(Mr);
    for (var i = 0; i < 12; i++) E -= (E - e * Math.sin(E) - Mr) / (1 - e * Math.cos(E));
    var xp = a * (Math.cos(E) - e), yp = a * Math.sqrt(1 - e * e) * Math.sin(E);
    var co = Math.cos(omega), so = Math.sin(omega), cO = Math.cos(Om), sO = Math.sin(Om);
    var cI = Math.cos(I), sI = Math.sin(I);
    return [(co * cO - so * sO * cI) * xp + (-so * cO - co * sO * cI) * yp,
            (co * sO + so * cO * cI) * xp + (-so * sO + co * cO * cI) * yp,
            (so * sI) * xp + (co * sI) * yp];
}
var EPS2000 = 23.43928 * D2R;
function eclToEq(v, eps) {
    var c = Math.cos(eps), s = Math.sin(eps);
    return [v[0], c * v[1] - s * v[2], s * v[1] + c * v[2]];
}

// Apparent magnitude with phase-angle terms (Astronomical Almanac, via Meeus ch. 41).
// A crescent Venus is far fainter than a full one; this is what accounts for it.
function magnitude(key, r, delta, i) {
    var base = 5 * Math.log(r * delta) / Math.LN10;
    switch (key) {
    case "mer": return -0.42 + base + 0.0380 * i - 0.000273 * i * i + 0.000002 * i * i * i;
    case "ven": return -4.40 + base + 0.0009 * i + 0.000239 * i * i - 0.00000065 * i * i * i;
    case "mar": return -1.52 + base + 0.016 * i;
    case "jup": return -9.40 + base + 0.005 * i;
    case "sat": return -8.88 + base;                     // ignoring the rings' tilt
    case "ura": return -7.19 + base;
    case "nep": return -6.87 + base;
    }
    return base;
}

// Planets (and the Sun) as J2000 equatorial unit vectors, with distances
// and an apparent magnitude estimate (H + 5 log10(r·Δ), no phase term).
function planets(jd, data) {
    var T = centuries(jd), earth = helio(data.ter, T), out = [];
    // light-time: positions are where the light left, Δ/c earlier (matters for Jupiter+)
    for (var key in data) {
        if (key === "ter") continue;
        var p = data[key], v = helio(p, T);
        var g = [v[0] - earth[0], v[1] - earth[1], v[2] - earth[2]];
        var delta = Math.sqrt(dot(g, g));
        v = helio(p, T - delta * 0.0057755183 / 36525);        // 1 AU = 0.00577552 light-days
        g = [v[0] - earth[0], v[1] - earth[1], v[2] - earth[2]];
        delta = Math.sqrt(dot(g, g));
        var r = Math.sqrt(dot(v, v)), R = Math.sqrt(dot(earth, earth));
        var ci = (r * r + delta * delta - R * R) / (2 * r * delta);
        var phase = Math.acos(Math.max(-1, Math.min(1, ci))) / D2R;   // Sun–planet–Earth angle
        out.push({ key: key, name: p.name, v: norm(eclToEq(g, EPS2000)), dist: delta,
                   phase: phase, mag: magnitude(key, r, delta, phase) });
    }
    var s = [-earth[0], -earth[1], -earth[2]];
    out.push({ key: "sun", name: "sun", v: norm(eclToEq(s, EPS2000)), dist: Math.sqrt(dot(s, s)), mag: -26.7 });
    return out;
}

// Just the Sun (J2000 equatorial unit vector), for the almanac strip's sampling.
function sun(jd, data) {
    var e = helio(data.ter, centuries(jd));
    return norm(eclToEq([-e[0], -e[1], -e[2]], EPS2000));
}

// ---------------- the Moon ----------------
// Astronomical Almanac low-precision series (~0.3°), mean equator OF DATE
// (so it skips the precession step). Includes topocentric parallax, which
// moves the Moon by up to a degree: twice its own width.
// Geocentric ecliptic longitude/latitude (deg, mean equinox of date) and
// horizontal parallax (deg). Meeus, Astronomical Algorithms ch. 47 (from
// ELP-2000/82), main periodic terms: good to a few hundredths of a degree,
// which is what eclipse predictions need. Columns: D, M, M', F, coefficient.
var MOON_L = [
    [0,0,1,0,6288774],[2,0,-1,0,1274027],[2,0,0,0,658314],[0,0,2,0,213618],[0,1,0,0,-185116],
    [0,0,0,2,-114332],[2,0,-2,0,58793],[2,-1,-1,0,57066],[2,0,1,0,53322],[2,-1,0,0,45758],
    [0,1,-1,0,-40923],[1,0,0,0,-34720],[0,1,1,0,-30383],[2,0,0,-2,15327],[0,0,1,2,-12528],
    [0,0,1,-2,10980],[4,0,-1,0,10675],[0,0,3,0,10034],[4,0,-2,0,8548],[2,1,-1,0,-7888],
    [2,1,0,0,-6766],[1,0,-1,0,-5163],[1,1,0,0,4987],[2,-1,1,0,4036],[2,0,2,0,3994],
    [4,0,0,0,3861],[2,0,-3,0,3665],[0,1,-2,0,-2689],[2,0,-1,2,-2602],[2,-1,-2,0,2390],
    [1,0,1,0,-2348],[2,-2,0,0,2236],[0,1,2,0,-2120],[0,2,0,0,-2069]];
var MOON_R = [
    [0,0,1,0,-20905355],[2,0,-1,0,-3699111],[2,0,0,0,-2955968],[0,0,2,0,-569925],[0,1,0,0,48888],
    [0,0,0,2,-3149],[2,0,-2,0,246158],[2,-1,-1,0,-152138],[2,0,1,0,-170733],[2,-1,0,0,-204586],
    [0,1,-1,0,-129620],[1,0,0,0,108743],[0,1,1,0,104755],[2,0,0,-2,10321],[0,0,1,-2,79661],
    [4,0,-1,0,-34782],[0,0,3,0,-23210],[4,0,-2,0,-21636],[2,1,-1,0,24208],[2,1,0,0,30824],
    [1,0,-1,0,-8379],[1,1,0,0,-16675],[2,-1,1,0,-12831],[2,0,2,0,-10445],[4,0,0,0,-11650],
    [2,0,-3,0,14403],[0,1,-2,0,-7003],[2,-1,-2,0,10056],[1,0,1,0,6322],[2,-2,0,0,-9884],
    [0,1,2,0,5751]];
var MOON_B = [
    [0,0,0,1,5128122],[0,0,1,1,280602],[0,0,1,-1,277693],[2,0,0,-1,173237],[2,0,-1,1,55413],
    [2,0,-1,-1,46271],[2,0,0,1,32573],[0,0,2,1,17198],[2,0,1,-1,9266],[0,0,2,-1,8822],
    [2,-1,0,-1,8216],[2,0,-2,-1,4324],[2,0,1,1,4200],[2,1,0,-1,-3359],[2,-1,-1,1,2463],
    [2,-1,0,1,2211],[2,-1,-1,-1,2065],[0,1,-1,-1,-1870],[4,0,-1,-1,1828],[0,1,0,1,-1794],
    [0,0,0,3,-1749],[0,1,-1,1,-1565],[1,0,0,1,-1491],[0,1,1,1,-1475],[0,1,1,-1,-1410],
    [0,1,0,-1,-1344],[1,0,0,-1,-1335],[0,0,3,1,1107]];

function moonEcl(jd) {
    var T = centuries(jd), T2 = T * T, T3 = T2 * T, T4 = T3 * T;
    var Lp = 218.3164477 + 481267.88123421 * T - 0.0015786 * T2 + T3 / 538841 - T4 / 65194000;
    var D  = 297.8501921 + 445267.1114034 * T - 0.0018819 * T2 + T3 / 545868 - T4 / 113065000;
    var M  = 357.5291092 + 35999.0502909 * T - 0.0001536 * T2 + T3 / 24490000;
    var Mp = 134.9633964 + 477198.8675055 * T + 0.0087414 * T2 + T3 / 69699 - T4 / 14712000;
    var F  = 93.2720950 + 483202.0175233 * T - 0.0036539 * T2 - T3 / 3526000 + T4 / 863310000;
    var E = 1 - 0.002516 * T - 0.0000074 * T2;                 // Earth's orbit's shrinking eccentricity
    var A1 = 119.75 + 131.849 * T, A2 = 53.09 + 479264.290 * T, A3 = 313.45 + 481266.484 * T;
    var arg = function (t) { return (t[0] * D + t[1] * M + t[2] * Mp + t[3] * F) * D2R; };
    var ecc = function (t) { var m = Math.abs(t[1]); return m === 1 ? E : m === 2 ? E * E : 1; };
    var sl = 0, sr = 0, sb = 0, i;
    for (i = 0; i < MOON_L.length; i++) sl += MOON_L[i][4] * ecc(MOON_L[i]) * Math.sin(arg(MOON_L[i]));
    for (i = 0; i < MOON_R.length; i++) sr += MOON_R[i][4] * ecc(MOON_R[i]) * Math.cos(arg(MOON_R[i]));
    for (i = 0; i < MOON_B.length; i++) sb += MOON_B[i][4] * ecc(MOON_B[i]) * Math.sin(arg(MOON_B[i]));
    var S = function (x) { return Math.sin(x * D2R); };
    sl += 3958 * S(A1) + 1962 * S(Lp - F) + 318 * S(A2);
    sb += -2235 * S(Lp) + 382 * S(A3) + 175 * S(A1 - F) + 175 * S(A1 + F) + 127 * S(Lp - Mp) - 115 * S(Lp + Mp);
    var distKm = 385000.56 + sr / 1000;
    return { lam: mod(Lp + sl / 1e6, 360), bet: sb / 1e6, par: Math.asin(6378.14 / distKm) / D2R, distKm: distKm };
}

function moon(jd, latDeg, lonDeg) {
    var e = moonEcl(jd);
    var rEarth = 1 / Math.sin(e.par * D2R);                     // distance in Earth radii
    var geo = eclToEq(vec(e.lam, e.bet), obliquity(jd));
    geo = [geo[0] * rEarth, geo[1] * rEarth, geo[2] * rEarth];
    // observer on the Earth's surface, equator of date (spherical Earth)
    var lst = (gmstDeg(jd) + lonDeg) * D2R, phi = latDeg * D2R;
    var obs = [Math.cos(phi) * Math.cos(lst), Math.cos(phi) * Math.sin(lst), Math.sin(phi)];
    var topo = [geo[0] - obs[0], geo[1] - obs[1], geo[2] - obs[2]];
    return { v: norm(topo), distKm: Math.sqrt(dot(topo, topo)) * 6378.14 };
}

// The Sun's geocentric ecliptic longitude, J2000 and of date (deg).
// (Solar longitude λ☉ in meteor-shower tables is J2000.)
function sunLonJ2000(jd, data) {
    var e = helio(data.ter, centuries(jd));
    return mod(Math.atan2(-e[1], -e[0]) / D2R, 360);
}
function sunLonOfDate(jd, data) {                              // + general precession in longitude
    return mod(sunLonJ2000(jd, data) + 1.396971 * centuries(jd), 360);
}

// ---------------- star colors ----------------
// B−V color index -> effective temperature (Ballesteros 2012), K.
function bvToKelvin(bv) {
    bv = Math.max(-0.4, Math.min(2.0, bv));
    return 4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62));
}

// ---------------- projection ----------------
// Stereographic (conformal, so constellations keep their shapes), centered
// on the direction you're facing. Returns a projector closure.
function projector(azDeg, altDeg, fovDeg, w, h, cyFrac) {
    var f = enu(altDeg, azDeg);
    var a = azDeg * D2R;
    var right = [Math.cos(a), -Math.sin(a), 0];
    var up = [right[1] * f[2] - right[2] * f[1], right[2] * f[0] - right[0] * f[2], right[0] * f[1] - right[1] * f[0]];
    var S = (w / 2) / (2 * Math.tan(fovDeg * D2R / 4));
    var cx = w / 2, cy = h * cyFrac;
    return {
        scale: S,                        // pixels per stereographic unit (~px/rad at center)
        f: f, right: right, up: up, cx: cx, cy: cy,   // for loops that unproject inline
        project: function (v) {          // -> [x, y, d] with d = cos(angle from center)
            var d = dot(v, f);
            if (d < -0.3) return null;   // too close to the antipode
            var k = 2 / (1 + d);
            return [cx + k * dot(v, right) * S, cy - k * dot(v, up) * S, d];
        },
        unproject: function (x, y) {     // screen point -> unit vector (east, north, up)
            var X = (x - cx) / S, Y = (cy - y) / S, r2 = X * X + Y * Y;
            var d = (4 - r2) / (4 + r2), s = (1 + d) / 2;
            return [s * (X * right[0] + Y * up[0]) + d * f[0],
                    s * (X * right[1] + Y * up[1]) + d * f[1],
                    s * (X * right[2] + Y * up[2]) + d * f[2]];
        }
    };
}
