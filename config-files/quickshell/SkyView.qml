import QtQuick
import "Lib.js" as Lib
import "SkyMath.js" as SM
import "SkyData.js" as SD
import "SkyEvents.js" as EV

// Tonight's sky, as seen from (latitude, longitude), drawn as a planetarium.
// Plain QtQuick so it can be tested anywhere; Sky.qml puts it on the
// wallpaper layer.
//
// What's real:
//   stars        5,044 Hipparcos stars to mag 6, in the true blackbody color for
//                their B−V index (Ballesteros' formula -> Planck colors), sized
//                and dimmed by magnitude, with atmospheric extinction near the
//                horizon (Kasten–Young airmass, 0.2 mag per airmass)
//   planets      JPL Keplerian elements with light-time; magnitudes with phase
//   the Moon     low-precision lunar series with topocentric parallax, phase
//                drawn from the actual Sun–Moon geometry, lit limb pointing at
//                the Sun, earthshine on the dark side
//   twilight     glow toward the Sun's azimuth, scaled by its depression;
//                green oxygen airglow (557.7 nm) low on the horizon at full dark
//   precession   J2000 catalog carried to today's equator (IAU 1976)
// What isn't: the Sun and Moon are drawn 3x their real size, and daylight
// doesn't wash the stars out (the sky stays "airless" so it's always worth looking at).
Item {
    id: root

    property Theme theme
    property real latitude: 34.05
    property real longitude: -118.25
    property real facing: 180            // azimuth at screen center, degrees
    property real fov: 150               // horizontal field of view, degrees
    property real offsetMin: 0           // time warp, minutes
    property real nowMs: Date.now()
    property bool live: true             // follow the real clock (tests pin nowMs instead)
    property bool meteors: true          // Sky.qml ties this to the bar's motion setting
    property int refreshMs: 30000

    signal turned(real facing)
    signal zoomed(real fov)
    signal warped(real offsetMin)

    readonly property color label: Lib.mix(theme.foreground, theme.muted, 0.5)
    readonly property string fontCss: "'" + theme.fontFamily + "', monospace"

    // ---------------- static catalog, prepared once ----------------
    property var cat: null
    Component.onCompleted: {
        var st = SD.STARS, n = st.length / 4, stars = [];
        for (var i = 0; i < n; i++) {
            var hex = Lib.blackbody(SM.bvToKelvin(st[4 * i + 3]));
            var c = parseInt(hex.slice(1), 16);
            stars.push({ v: SM.vec(st[4 * i], st[4 * i + 1]), mag: st[4 * i + 2],
                         rgb: "rgba(" + (c >> 16 & 255) + "," + (c >> 8 & 255) + "," + (c & 255) + "," });
        }
        var mw = [];
        for (var j = 0; j < SD.MILKY.length; j += 3)
            mw.push({ v: SM.vec(SD.MILKY[j], SD.MILKY[j + 1]), lv: SD.MILKY[j + 2] });
        var lines = SD.LINES.map(pl => {
            var out = [];
            for (var k = 0; k < pl.length; k += 2) out.push(SM.vec(pl[k], pl[k + 1]));
            return out;
        });
        var named = SD.NAMED.map(s => {
            var T = SM.bvToKelvin(s[4]);
            return { v: SM.vec(s[0], s[1]), mag: s[2], name: s[3], bv: s[4], kelvin: T };
        });
        var labels = SD.LABELS.map(l => ({ v: SM.vec(l[0], l[1]), name: l[2] }));
        // Unresolved starlight: a fixed, seeded scatter of faint points inside
        // the Milky Way, denser in the brighter levels. This grain carries the
        // structure; the haze under it stays faint.
        var rnd = Lib.rng(1977), dust = [], per = [0, 1, 3, 6, 9, 12];
        var half = SD.MILKY_STEP / 2;
        for (var q = 0; q < SD.MILKY.length; q += 3) {
            var dra = SD.MILKY[q], ddec = SD.MILKY[q + 1], lvl = SD.MILKY[q + 2];
            var cosd = Math.max(0.15, Math.cos(ddec * SM.D2R));
            for (var u = 0; u < per[lvl]; u++) {
                var hx = Lib.blackbody(3200 + 7000 * Math.pow(rnd(), 1.6));
                var cn = parseInt(hx.slice(1), 16);
                dust.push({
                    v: SM.vec(dra + (rnd() - 0.5) * 2 * half / cosd, ddec + (rnd() - 0.5) * 2 * half),
                    a: 0.06 + 0.035 * lvl * rnd(),
                    rgb: "rgba(" + (cn >> 16 & 255) + "," + (cn >> 8 & 255) + "," + (cn & 255) + ","
                });
            }
        }
        cat = { stars: stars, mw: mw, dust: dust, lines: lines, named: named, labels: labels };
        almanac();
        redraw();
        if (meteors) scheduleMeteor();
    }

    // ---------------- almanac: the next/last 12 hours, for the time strip ----------------
    // Sun and Moon altitude every 10 minutes from 12 h before now to 12 h after,
    // and the moments they cross the horizon (−0.83°: the upper limb touching it,
    // refraction included) and the Sun crosses −18° (astronomical dark / dawn).
    property var alm: null
    function almanac() {
        var t0 = nowMs - 12 * 3600e3, t1 = nowMs + 12 * 3600e3, n = 145, sam = [];
        for (var i = 0; i < n; i++) {
            var ms = t0 + (t1 - t0) * i / (n - 1), jd = SM.julian(ms);
            var Hz = SM.horizon(jd, latitude, longitude);
            var A = SM.mm(Hz, SM.precession(jd));
            sam.push({
                ms: ms,
                sun: SM.altaz(SM.mul(A, SM.sun(jd, SD.PLANETS))).alt,
                moon: SM.altaz(SM.mul(Hz, SM.moon(jd, latitude, longitude).v)).alt
            });
        }
        var ev = [];
        var cross = function (key, level, up, down) {
            for (var j = 1; j < n; j++) {
                var a = sam[j - 1][key] - level, b = sam[j][key] - level;
                if (a * b < 0) {
                    var u = a / (a - b);
                    ev.push({ ms: sam[j - 1].ms + u * (sam[j].ms - sam[j - 1].ms), name: b > a ? up : down, key: key });
                }
            }
        };
        cross("sun", -0.833, "sunrise", "sunset");
        cross("sun", -18, "dawn", "dark");
        cross("moon", -0.833, "moonrise", "moonset");
        ev.sort((x, y) => x.ms - y.ms);
        alm = { t0: t0, t1: t1, sam: sam, ev: ev };
    }
    function almAt(key, ms) {
        var a = alm, n = a.sam.length;
        var u = Math.max(0, Math.min(n - 1, (ms - a.t0) / (a.t1 - a.t0) * (n - 1)));
        var i = Math.min(n - 2, Math.floor(u)), k = u - i;
        return a.sam[i][key] * (1 - k) + a.sam[i + 1][key] * k;
    }

    function redraw() { Qt.callLater(paintAll); }
    function paintAll() { base.requestPaint(); archGlow.requestPaint(); antiGlow.requestPaint(); milky.requestPaint(); main.requestPaint(); }
    onFacingChanged: redraw()
    onFovChanged: redraw()
    onOffsetMinChanged: redraw()
    onNowMsChanged: { if (cat) almanac(); redraw(); }
    onLatitudeChanged: { if (cat) almanac(); redraw(); }
    onLongitudeChanged: { if (cat) almanac(); redraw(); }
    onWidthChanged: redraw()
    onHeightChanged: redraw()
    onThemeChanged: redraw()

    // ---------------- per-frame geometry ----------------
    // Keep the horizon at 88% of the height whatever the field of view.
    function frame(W, H) {
        var jd = SM.julian(nowMs + offsetMin * 60000);
        var Hz = SM.horizon(jd, latitude, longitude);
        var A = SM.mm(Hz, SM.precession(jd));
        var S = (W / 2) / (2 * Math.tan(fov * SM.D2R / 4));
        var centerAlt = 2 * Math.atan(0.19 * H / S) / SM.D2R;
        var pr = SM.projector(facing, centerAlt, fov, W, H, 0.5);
        var bodies = SM.planets(jd, SD.PLANETS).map(b => Object.assign(b, { w: SM.mul(A, b.v) }));
        var sun = bodies.find(b => b.key === "sun");
        var mo = SM.moon(jd, latitude, longitude);
        return { jd: jd, A: A, Hz: Hz, pr: pr, S: S, bodies: bodies, sun: sun,
                 moon: { w: SM.mul(Hz, mo.v), distKm: mo.distKm } };
    }

    function onScreen(p, W, H, m) { return p && p[0] > -m && p[0] < W + m && p[1] > -m && p[1] < H + m; }

    // How dark is it? The faintest star you could see by eye (the limiting
    // magnitude) follows the Sun down through twilight:
    //     Sun above the horizon   −1    Sirius, the bright planets, the Moon
    //     −6° (civil dusk)        1.5   first-magnitude stars
    //     −12° (nautical)         4     the constellations take shape
    //     −18° (astronomical)     6.2   everything, and the Milky Way
    // A bright Moon high up washes the faint end out again, by up to ~1.5 mag
    // at full. `day` is how much daylight blue to put in the sky (0..1).
    function skyLight(f) {
        var sa = SM.altaz(f.sun.w).alt;
        var pts = [[2, -1.0], [-1, -0.3], [-6, 1.5], [-12, 4.0], [-18, 6.2]];
        var lim = sa >= 2 ? -1 : 6.2;
        for (var i = 1; i < pts.length; i++) {
            if (sa >= pts[i][0] && sa < pts[i - 1][0]) {
                var u = (sa - pts[i][0]) / (pts[i - 1][0] - pts[i][0]);
                lim = pts[i][1] + u * (pts[i - 1][1] - pts[i][1]);
                break;
            }
        }
        var mAlt = SM.altaz(f.moon.w).alt;
        var cosE = SM.dot(SM.norm(f.moon.w), SM.norm(f.sun.w));
        var illum = (1 - cosE) / 2;
        var up = Math.max(0, Math.min(1, (mAlt + 2) / 25));
        var moonlight = Math.pow(illum, 1.5) * up;                // 0 .. 1
        var dim = 1.5 * moonlight * Math.max(0, Math.min(1, (lim - 1.5) / 4.7));
        var smooth = function (lo, hi, x) {
            var v = Math.max(0, Math.min(1, (x - lo) / (hi - lo)));
            return v * v * (3 - 2 * v);
        };
        return {
            lim: lim - dim,
            day: smooth(-7, 3, sa),
            moonlight: moonlight,
            figures: 0.3 + 0.7 * smooth(0.5, 4, lim - dim)        // lines and names: a trace by day
        };
    }
    // 1 for a star comfortably brighter than the limit, fading to 0 just past it.
    function seen(mag, lim) {
        var u = Math.max(0, Math.min(1, (lim + 0.4 - mag) / 1.1));
        return u * u * (3 - 2 * u);
    }

    // Kasten & Young (1989) relative airmass; extinction 0.2 mag per airmass.
    // Clamped at the horizon: below it the formula's denominator crosses zero.
    function extinction(altRad) {
        var h = Math.max(0, altRad);
        var X = 1 / (Math.sin(h) + 0.50572 * Math.pow(h / SM.D2R + 6.07995, -1.6364));
        return 0.2 * (X - 1);
    }

    // ================= layer 1: sky gradient, twilight, airglow =================
    Canvas {
        id: base
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.cat) return;
            var W = width, H = height, f = root.frame(W, H), t = root.theme;
            var hp = f.pr.project(SM.enu(0, root.facing)), hy = hp ? hp[1] : H * 0.88;

            // Night: the theme's background, a little lighter toward the horizon.
            // Day: a deep blue that's paler low down: unmistakably day, but
            // still a dark wallpaper (about twice night's brightness, not the
            // real sky's hundreds of times). Moonlight lifts the night a little.
            var L = root.skyLight(f);
            var blue = Math.min(1, L.day + 0.18 * L.moonlight);
            var pale = Qt.color(Lib.mix(t.accent2, t.foreground, 0.45));
            var g = ctx.createLinearGradient(0, 0, 0, hy);
            g.addColorStop(0, Lib.mix(t.background, t.accent2, 0.2 * blue));
            g.addColorStop(0.6, Lib.mix(Qt.color(Lib.mix(t.background, t.muted, 0.1)), t.accent2, 0.24 * blue));
            g.addColorStop(1, Lib.mix(Qt.color(Lib.mix(t.background, t.muted, 0.22)), pale, 0.3 * blue));
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, W, H);

            // Scattered sunlight, following where the Sun actually is.
            //   day        aureole around the Sun (forward scattering) and a pale
            //              band all along the horizon (more air on that line of sight).
            //              No orange: sunlight only reddens through a lot of air.
            //   sunset, twilight: see the `twilight` layer
            //   night      faint green oxygen airglow low all around
            // Which stars show is up to skyLight(): they come out through twilight.
            var sunAA = SM.altaz(f.sun.w), sa = sunAA.alt;
            var smooth = function (lo, hi, x) {
                var u = Math.max(0, Math.min(1, (x - lo) / (hi - lo)));
                return u * u * (3 - 2 * u);
            };
            // an elliptical glow: horizontal radius R, squashed vertically
            var glow = function (x, y, R, squash, stops) {
                ctx.save();
                ctx.translate(x, y);
                ctx.scale(1, squash);
                var gg = ctx.createRadialGradient(0, 0, 0, 0, 0, R);
                for (var si = 0; si < stops.length; si++) gg.addColorStop(stops[si][0], stops[si][1]);
                ctx.fillStyle = gg;
                ctx.fillRect(-R, -R, 2 * R, 2 * R);
                ctx.restore();
            };
            var day = smooth(-4, 8, sa);                          // 0 at night, 1 in daylight
            var night = 1 - smooth(-18, -12, sa);

            if (day > 0) {                                        // pale horizon band, all around
                var hb = ctx.createLinearGradient(0, hy - 320, 0, hy);
                hb.addColorStop(0, Lib.css(t.accent2, 0));
                hb.addColorStop(1, Lib.mix(t.accent2, t.foreground, 0.3));
                ctx.globalAlpha = 0.16 * day;
                ctx.fillStyle = hb;
                ctx.fillRect(0, hy - 320, W, 320);
                ctx.globalAlpha = 1;
            }

            if (sa > -1) {                                        // aureole, centered on the Sun
                var sp = f.pr.project(f.sun.w);
                if (sp) {
                    var white = Lib.mix(t.foreground, Qt.color(Lib.blackbody(Lib.SUN_T)), 0.5);
                    glow(sp[0], sp[1], W * 0.42, 1, [
                        [0, Lib.css(Qt.color(white), 0.05 + 0.2 * day)],
                        [0.12, Lib.css(Qt.color(white), 0.03 + 0.09 * day)],
                        [1, Lib.css(Qt.color(white), 0)]]);
                }
            }

            // The twilight arch, the Belt of Venus and the Earth's shadow are
            // on their own layer (`twilight`, below), worked out per pixel.

            if (night > 0) {                                      // oxygen airglow, 557.7 nm
                var ag = ctx.createLinearGradient(0, hy - 170, 0, hy);
                ag.addColorStop(0, Lib.css(t.accent3, 0));
                ag.addColorStop(0.7, Lib.css(t.accent3, 0.05 * night));
                ag.addColorStop(1, Lib.css(t.accent3, 0.015 * night));
                ctx.fillStyle = ag;
                ctx.fillRect(0, hy - 170, W, 170);
            }
        }
    }

    // ================= layer 1b: twilight =================
    //   the arch    warm light hugging the horizon under the Sun, strongest with
    //               the Sun just below the horizon; then the last blue
    //   opposite    the Earth's shadow, a dark blue-grey band rising from the
    //               horizon as the Sun sinks, with the pink Belt of Venus above it
    // These are bands in the sky that follow the curved horizon, but they're
    // still plain canvas gradients, thanks to one property of the stereographic
    // projection: every circle on the sky is drawn as a circle on the screen.
    //   - Lines of equal altitude are circles around the zenith.
    //   - The shadow's edge is a great circle: 90° from a pole tilted from the
    //     zenith toward the Sun by about the Sun's depression, so it stands
    //     about as high as the Sun is low straight opposite the Sun, and slopes
    //     down to the horizon 90° to either side. Lines parallel to it (the
    //     belt above, the shadow below) are circles around the same pole.
    // So each band is a radial gradient between two screen circles, with
    // its colour stops placed at the right heights. A second, gentle gradient
    // fades it out sideways (stronger opposite the Sun, or under it). Each
    // band gets its own small canvas, because the fade is applied by
    // compositing: colours first, then the fade "destination-in".
    function circleFrom3(a, b, c) {
        var d = 2 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]));
        if (Math.abs(d) < 1e-9) return null;              // a straight line
        var a2 = a[0] * a[0] + a[1] * a[1], b2 = b[0] * b[0] + b[1] * b[1], c2 = c[0] * c[0] + c[1] * c[1];
        var x = (a2 * (b[1] - c[1]) + b2 * (c[1] - a[1]) + c2 * (a[1] - b[1])) / d;
        var y = (a2 * (c[0] - b[0]) + b2 * (a[0] - c[0]) + c2 * (b[0] - a[0])) / d;
        return { x: x, y: y, r: Math.hypot(a[0] - x, a[1] - y) };
    }
    // The point at angular distance rho (deg) from pole n, on the side toward
    // ref, turned by t (rad) around the pole.
    function circlePoint(n, rhoDeg, ref, t) {
        var k = SM.dot(ref, n);
        var e1 = SM.norm([ref[0] - k * n[0], ref[1] - k * n[1], ref[2] - k * n[2]]);
        var e2 = [n[1] * e1[2] - n[2] * e1[1], n[2] * e1[0] - n[0] * e1[2], n[0] * e1[1] - n[1] * e1[0]];
        var r = rhoDeg * SM.D2R, cr = Math.cos(r), sr = Math.sin(r), ct = Math.cos(t), st = Math.sin(t);
        return [cr * n[0] + sr * (ct * e1[0] + st * e2[0]),
                cr * n[1] + sr * (ct * e1[1] + st * e2[1]),
                cr * n[2] + sr * (ct * e1[2] + st * e2[2])];
    }
    // Any three points fix a circle: take them from whatever part of it can be
    // projected (much of it may be behind you).
    function screenCircle(pr, n, rhoDeg, ref) {
        var pts = [];
        for (var i = -11; i <= 12; i++) {                 // all the way round, 15° apart
            var p = pr.project(circlePoint(n, rhoDeg, ref, i * Math.PI / 12));
            if (p) pts.push(p);
        }
        return pts.length < 3 ? null : circleFrom3(pts[0], pts[pts.length >> 1], pts[pts.length - 1]);
    }
    // A projectable point of that circle, as close as possible to the ref side.
    function circleAnchor(pr, n, rhoDeg, ref) {
        var ts = [0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.2, -1.2, 1.5, -1.5];
        for (var i = 0; i < ts.length; i++) {
            var p = pr.project(circlePoint(n, rhoDeg, ref, ts[i]));
            if (p) return p;
        }
        return null;
    }
    // Radial gradient from the circle at rhos[0] to the one at rhos[last]
    // (both around pole n); colours[i] lands where the circle at rhos[i]
    // crosses the meridian toward ref.
    function bandGradient(ctx, pr, n, ref, rhos, colours) {
        var last = rhos.length - 1;
        var A = screenCircle(pr, n, rhos[0], ref), B = screenCircle(pr, n, rhos[last], ref);
        if (!A || !B) return null;
        if (A.r > B.r) {                       // Qt wants the smaller circle first (it draws nothing otherwise)
            rhos = rhos.slice().reverse();
            colours = colours.slice().reverse();
            var tmp = A; A = B; B = tmp;
        }
        var g = ctx.createRadialGradient(A.x, A.y, A.r, B.x, B.y, B.r);
        var dx = B.x - A.x, dy = B.y - A.y, dr = B.r - A.r, prev = 0;
        for (var i = 0; i <= last; i++) {
            var s = i === 0 ? 0 : i === last ? 1 : NaN;
            if (isNaN(s)) {
                // where along the gradient this circle sits: |p − c(s)| = r(s)
                var p = circleAnchor(pr, n, rhos[i], ref);
                if (!p) continue;
                var px = p[0] - A.x, py = p[1] - A.y;
                var qa = dx * dx + dy * dy - dr * dr, qb = -2 * (dx * px + dy * py + A.r * dr);
                var qc = px * px + py * py - A.r * A.r;
                if (Math.abs(qa) < 1e-9) s = -qc / qb;
                else {
                    var disc = Math.sqrt(Math.max(0, qb * qb - 4 * qa * qc));
                    var s1 = (-qb - disc) / (2 * qa), s2 = (-qb + disc) / (2 * qa);
                    s = Math.abs(s1 - i / last) < Math.abs(s2 - i / last) ? s1 : s2;
                }
            }
            s = Math.max(prev, Math.min(1, s));
            prev = s;
            g.addColorStop(s, colours[i]);
        }
        return g;
    }
    // Fade sideways: 1 at the centre point, falling to 0 at radius R (screen).
    function fadeGradient(ctx, c, R, weight) {
        var g = ctx.createRadialGradient(c[0], c[1], 0, c[0], c[1], R);
        for (var i = 0; i <= 10; i++) g.addColorStop(i / 10, "rgba(255,255,255," + weight(i / 10).toFixed(4) + ")");
        return g;
    }
    // Several colours stacked "over" each other -> one rgba() string.
    function stack(layers) {
        var R = 0, G = 0, B = 0, A = 0;
        for (var i = 0; i < layers.length; i++) {
            var c = Qt.color(layers[i][0]), a = Math.max(0, Math.min(1, layers[i][1]));
            R = c.r * a + R * (1 - a); G = c.g * a + G * (1 - a); B = c.b * a + B * (1 - a); A = a + A * (1 - a);
        }
        if (A <= 0) return "rgba(0,0,0,0)";
        return "rgba(" + Math.round(R / A * 255) + "," + Math.round(G / A * 255) + "," + Math.round(B / A * 255) + "," + A.toFixed(4) + ")";
    }
    function twilightState(f) {
        var sunAA = SM.altaz(f.sun.w), sa = sunAA.alt;
        var smooth = function (lo, hi, x) {
            var u = Math.max(0, Math.min(1, (x - lo) / (hi - lo)));
            return u * u * (3 - 2 * u);
        };
        return {
            sa: sa, az: sunAA.az, smooth: smooth,
            warm: Math.max(0, 1 - Math.abs(sa + 1) / 11),         // reddening: peaks at sa ≈ −1°
            deep: sa < 0 ? smooth(-18, -8, sa) : 0,               // the last blue of twilight
            belt: Math.max(0, 1 - Math.abs(sa + 2) / 5.5)         // Belt of Venus: sa ≈ +3.5° .. −7.5°
        };
    }
    // Where to pin a band's colour stops: its centre azimuth, or, when that's
    // off to the side, the nearest azimuth well inside the view. (Between the
    // two end circles the gradient only interpolates, which is exact where the
    // stops are pinned and drifts further round; so pin them where you look.)
    function anchorAz(az) {
        var d = SM.mod(az - facing + 180, 360) - 180, lim = 0.33 * fov;
        return facing + Math.max(-lim, Math.min(lim, d));
    }
    // How far apart (screen) two horizon azimuths are, for the sideways fade.
    function horizonSpan(pr, az, dAz, fallback) {
        var c = pr.project(SM.enu(0, az)), l = pr.project(SM.enu(0, az - dAz)), r = pr.project(SM.enu(0, az + dAz));
        var d = [];
        if (c && l) d.push(Math.hypot(l[0] - c[0], l[1] - c[1]));
        if (c && r) d.push(Math.hypot(r[0] - c[0], r[1] - c[1]));
        return d.length ? Math.max.apply(null, d) : fallback;
    }

    Item {
        id: twilight
        anchors.fill: parent
        readonly property int k: 4
        Canvas {                                          // the arch, under the Sun
            id: archGlow
            width: Math.ceil(root.width / twilight.k)
            height: Math.ceil(root.height / twilight.k)
            scale: twilight.k
            transformOrigin: Item.TopLeft
            smooth: true
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                if (!root.cat) return;
                var W = width, H = height, f = root.frame(W, H), t = root.theme, tw = root.twilightState(f);
                if (tw.warm <= 0 && tw.deep <= 0) return;
                var at = f.pr.project(SM.enu(0, tw.az));
                if (!at) return;                          // the Sun's side is behind you
                // fade sideways: ±110° around the Sun's azimuth
                // colours by height above the horizon (altitude circles around the zenith)
                var hot = Qt.color(Lib.mix(t.accent5, t.accent4, 0.25)), archH = Math.max(0, tw.sa) * 0.6;
                var rhos = [], cols = [];
                for (var h = -2; h <= 46; h += 2) {
                    var hh = Math.max(0, h - archH), up = hh / (14 * 2.2);
                    var col = up < 0.25 ? Lib.mix(hot, t.accent5, up / 0.25)
                            : up < 0.65 ? Lib.mix(t.accent5, t.accent7, (up - 0.25) / 0.4) : t.accent7;
                    rhos.push(90 - h);
                    cols.push(root.stack([[col, tw.warm * 0.42 * Math.exp(-hh / 14)],
                                          [t.accent2, 0.2 * tw.deep * (1 - tw.warm) * Math.exp(-hh / 12)]]));
                }
                cols[0] = cols[cols.length - 1] = "rgba(0,0,0,0)";   // nothing beyond the ends
                var g = root.bandGradient(ctx, f.pr, [0, 0, 1], SM.enu(0, root.anchorAz(tw.az)), rhos, cols);
                if (!g) return;
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, W, H);
                // then fade it sideways: ±110° around the Sun's azimuth
                var R = root.horizonSpan(f.pr, tw.az, 110, W);
                ctx.globalCompositeOperation = "destination-in";
                ctx.fillStyle = root.fadeGradient(ctx, at, R,
                    u => Math.min(1, Math.pow(Math.max(0, (Math.cos(u * 110 * SM.D2R) + 0.35) / 1.35), 1.8) + 0.12 * (1 - u)));
                ctx.fillRect(0, 0, W, H);
            }
        }
        Canvas {                                          // Earth's shadow and the Belt of Venus, opposite
            id: antiGlow
            width: Math.ceil(root.width / twilight.k)
            height: Math.ceil(root.height / twilight.k)
            scale: twilight.k
            transformOrigin: Item.TopLeft
            smooth: true
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                if (!root.cat) return;
                var W = width, H = height, f = root.frame(W, H), t = root.theme, tw = root.twilightState(f);
                if (tw.belt <= 0) return;
                var anti = SM.mod(tw.az + 180, 360), at = f.pr.project(SM.enu(0, anti));
                if (!at) return;                          // the anti-Sun side is behind you
                // pole of the shadow's edge: the zenith tipped toward the Sun by ~0.9 × the Sun's depression
                var tilt = Math.max(0, -tw.sa) * 0.9 * SM.D2R, sz = tw.az * SM.D2R;
                var n = [Math.sin(tilt) * Math.sin(sz), Math.sin(tilt) * Math.cos(sz), Math.cos(tilt)];
                var on = tw.smooth(0, 1.5, -tw.sa);
                var dark = Lib.mix(t.background, t.accent2, 0.18), pink = Lib.mix(t.accent7, t.accent5, 0.45);
                var rhos = [], cols = [];
                for (var x = -12; x <= 18; x += 1) {      // degrees above the shadow's edge
                    rhos.push(90 - x);
                    cols.push(root.stack([[dark, 0.6 * tw.belt * on * (1 - tw.smooth(-1.2, 1.2, x))],
                                          [pink, 0.4 * tw.belt * tw.smooth(-0.5, 2.5, x) * (1 - tw.smooth(3, 16, x))]]));
                }
                cols[0] = cols[cols.length - 1] = "rgba(0,0,0,0)";
                var g = root.bandGradient(ctx, f.pr, n, SM.enu(0, root.anchorAz(anti)), rhos, cols);
                if (!g) return;
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, W, H);
                // then fade it sideways: gone 90° either side of straight opposite the Sun
                var R = root.horizonSpan(f.pr, anti, 90, W);
                ctx.globalCompositeOperation = "destination-in";
                ctx.fillStyle = root.fadeGradient(ctx, at, R, u => Math.pow(Math.max(0, Math.cos(u * Math.PI / 2)), 0.6));
                ctx.fillRect(0, 0, W, H);
            }
        }
    }

    // ================= layer 2: the Milky Way, drawn small and scaled up soft =================
    // The haze is so faint that drawing it at its real opacity leaves only one
    // or two 8-bit levels per blob, which show up as rings and grid lines.
    // So it's drawn `gain` times brighter (plenty of levels, smooth gradients)
    // and the whole layer is faded by 1/gain when composited.
    Canvas {
        id: milky
        readonly property int k: 3
        readonly property real gain: 6
        width: Math.ceil(parent.width / k)
        height: Math.ceil(parent.height / k)
        scale: k
        opacity: 1 / gain
        transformOrigin: Item.TopLeft
        smooth: true
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.cat) return;
            var W = width, H = height, f = root.frame(W, H), c = root.cat;
            // Faint and nonlinear: the outer envelope (level 1) is barely there,
            // only the dense core builds up. Edges lean toward the theme's
            // blue/mauve, the core warms toward gold, like a real sky photo.
            var th = root.theme;
            var tints = [null,
                Lib.mix(th.accent2, th.accent7, 0.5),
                Lib.mix(th.accent2, th.foreground, 0.35),
                Lib.mix(th.foreground, th.accent7, 0.25),
                Lib.mix(th.foreground, th.accent4, 0.35),
                Lib.mix(th.foreground, th.accent4, 0.5)];
            var rgbs = tints.map(cc => {
                if (!cc) return "";
                var n = parseInt(String(cc).slice(1), 16);
                return "rgba(" + (n >> 16 & 255) + "," + (n >> 8 & 255) + "," + (n & 255) + ",";
            });
            // only once the sky is properly dark (and it fades under a bright Moon)
            var dark = Math.max(0, Math.min(1, (root.skyLight(f).lim - 4.6) / 1.4));
            if (dark <= 0) return;
            var alpha = [0, 0.007, 0.014, 0.022, 0.032, 0.042].map(x => x * milky.gain * dark);
            var step = SD.MILKY_STEP * SM.D2R;
            for (var i = 0; i < c.mw.length; i++) {
                var w = SM.mul(f.A, c.mw[i].v);
                if (w[2] < -0.03) continue;
                var p = f.pr.project(w);
                if (!root.onScreen(p, W, H, 4)) continue;
                // soft-edged blobs, overlapping heavily, so the sampling grid never shows
                var r = Math.max(1.5, 2 / (1 + p[2]) * f.S * step * 2.0);
                var a = alpha[c.mw[i].lv] * Math.max(0, 1 - root.extinction(Math.asin(w[2])) / 1.2);
                if (a <= 0.0005) continue;
                var gr = ctx.createRadialGradient(p[0], p[1], 0, p[0], p[1], r);
                var rgb = rgbs[c.mw[i].lv];
                gr.addColorStop(0, rgb + a.toFixed(4) + ")");
                gr.addColorStop(1, rgb + "0)");
                ctx.fillStyle = gr;
                ctx.fillRect(p[0] - r, p[1] - r, 2 * r, 2 * r);
            }
        }
    }

    // ================= layer 3: everything else =================
    property var targets: []                  // hover hit-list, filled each paint

    Canvas {
        id: main
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.cat) return;
            var W = width, H = height, f = root.frame(W, H), c = root.cat, t = root.theme;
            var hits = [];
            var font = function (px, extra) { ctx.font = (extra ? extra + " " : "") + px + "px " + root.fontCss; };
            var L = root.skyLight(f), mwDark = Math.max(0, Math.min(1, (L.lim - 4.6) / 1.4));

            // ---- Milky Way grain ----
            for (var di = 0; di < c.dust.length; di++) {
                var dd = c.dust[di], dw = SM.mul(f.A, dd.v);
                if (dw[2] < 0.01) continue;
                var dp = f.pr.project(dw);
                if (!root.onScreen(dp, W, H, 2)) continue;
                var da = dd.a * mwDark * Math.max(0, 1 - root.extinction(Math.asin(dw[2])) / 1.5);
                if (da < 0.01) continue;
                ctx.fillStyle = dd.rgb + da.toFixed(3) + ")";
                ctx.fillRect(dp[0], dp[1], 1, 1);
            }

            // ---- constellation figures ----
            ctx.lineWidth = 1;
            ctx.strokeStyle = Lib.css(t.accent2, 0.22 * L.figures);
            ctx.beginPath();
            for (var li = 0; li < c.lines.length; li++) {
                var prev = null;
                for (var lj = 0; lj < c.lines[li].length; lj++) {
                    var lw = SM.mul(f.A, c.lines[li][lj]);
                    var lp = lw[2] > -0.05 ? f.pr.project(lw) : null;
                    if (lp && prev && Math.abs(lp[0] - prev[0]) < W / 2) {
                        ctx.moveTo(prev[0], prev[1]);
                        ctx.lineTo(lp[0], lp[1]);
                    }
                    prev = lp;
                }
            }
            ctx.stroke();

            // ---- stars ----
            for (var i = 0; i < c.stars.length; i++) {
                var s = c.stars[i], w = SM.mul(f.A, s.v);
                if (w[2] < 0) continue;
                var p = f.pr.project(w);
                if (!root.onScreen(p, W, H, 6)) continue;
                var m = s.mag + root.extinction(Math.asin(w[2]));
                var vis = root.seen(m, L.lim);
                if (m > 6.2 || vis < 0.02) continue;
                var a = Math.max(0.32, Math.min(1, 1.15 - 0.13 * m)) * vis;
                var r = Math.max(0.7, Math.min(3.4, 2.6 - 0.36 * m));
                if (m < 1.2) {                         // halo for the brightest
                    var hg = ctx.createRadialGradient(p[0], p[1], 0, p[0], p[1], r * 4);
                    hg.addColorStop(0, s.rgb + (0.35 * a).toFixed(3) + ")");
                    hg.addColorStop(1, s.rgb + "0)");
                    ctx.fillStyle = hg;
                    ctx.fillRect(p[0] - r * 4, p[1] - r * 4, r * 8, r * 8);
                }
                ctx.fillStyle = s.rgb + a.toFixed(3) + ")";
                if (r < 1.1) {
                    ctx.fillRect(p[0] - r, p[1] - r, 2 * r, 2 * r);
                } else {
                    ctx.beginPath();
                    ctx.arc(p[0], p[1], r, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }

            // ---- named stars ----
            font(Math.max(9, t.fontSize - 3));
            for (var ni = 0; ni < c.named.length; ni++) {
                var ns = c.named[ni], nw = SM.mul(f.A, ns.v);
                if (nw[2] < 0.03) continue;
                var np = f.pr.project(nw);
                if (!root.onScreen(np, W, H, 0)) continue;
                var nvis = root.seen(ns.mag + root.extinction(Math.asin(nw[2])), L.lim);
                if (nvis < 0.25) continue;                    // its star isn't out yet
                ctx.fillStyle = Lib.css(root.label, 0.75 * nvis);
                ctx.fillText(ns.name.toLowerCase(), np[0] + 6, np[1] - 5);
                var naa = SM.altaz(nw);
                hits.push({ x: np[0], y: np[1], title: ns.name,
                            lines: ["star · mag " + ns.mag.toFixed(2),
                                    Lib.grouped(ns.kelvin) + " K · class " + Lib.spectralClass(ns.kelvin) + " · B−V " + ns.bv.toFixed(2),
                                    "alt " + naa.alt.toFixed(1) + "°  az " + naa.az.toFixed(1) + "°"] });
            }

            // ---- constellation names ----
            font(Math.max(9, t.fontSize - 4), "bold");
            ctx.fillStyle = Lib.css(t.accent2, 0.3 * L.figures);
            for (var ci = 0; ci < c.labels.length; ci++) {
                var cw = SM.mul(f.A, c.labels[ci].v);
                if (cw[2] < 0.08) continue;
                var cp = f.pr.project(cw);
                if (!root.onScreen(cp, W, H, -20)) continue;
                var txt = c.labels[ci].name.toUpperCase().split("").join(" ");
                ctx.fillText(txt, cp[0] - ctx.measureText(txt).width / 2, cp[1]);
            }

            // ---- planets ----
            var sunEnu = f.sun.w;
            for (var bi = 0; bi < f.bodies.length; bi++) {
                var b = f.bodies[bi];
                if (b.key === "sun" || b.w[2] < 0) continue;
                var bp = f.pr.project(b.w);
                if (!root.onScreen(bp, W, H, 0)) continue;
                var info = Lib.PLANETS.find(x => x.name === b.name);
                var tint = info ? info.tint : "#ffffff";
                var br = Math.max(1.6, Math.min(4.2, 2.6 - 0.38 * b.mag));
                // like the stars, but never quite gone: by day they're ghosts you can still find
                var pv = Math.max(0.3, root.seen(b.mag + root.extinction(Math.asin(b.w[2])), L.lim));
                var halo = ctx.createRadialGradient(bp[0], bp[1], 0, bp[0], bp[1], br * 4.5);
                halo.addColorStop(0, Lib.hexA(tint, 0.35 * pv));
                halo.addColorStop(1, Lib.hexA(tint, 0));
                ctx.fillStyle = halo;
                ctx.fillRect(bp[0] - br * 4.5, bp[1] - br * 4.5, br * 9, br * 9);
                ctx.fillStyle = Lib.hexA(tint, pv);
                ctx.beginPath();
                ctx.arc(bp[0], bp[1], br, 0, 2 * Math.PI);
                ctx.fill();
                font(Math.max(9, t.fontSize - 2));
                ctx.fillStyle = Lib.hexA(tint, 0.9 * Math.max(0.45, pv));
                ctx.fillText(b.name, bp[0] + br + 5, bp[1] + 4);
                var baa = SM.altaz(b.w);
                hits.push({ x: bp[0], y: bp[1], title: b.name,
                            lines: ["planet · mag " + (b.mag >= 0 ? "+" : "−") + Math.abs(b.mag).toFixed(1)
                                        + " · " + b.dist.toFixed(2) + " AU",
                                    "light left it " + Lib.hm(b.dist * Lib.AU / Lib.C) + " ago",
                                    "phase angle " + b.phase.toFixed(0) + "° · alt " + baa.alt.toFixed(1) + "°  az " + baa.az.toFixed(1) + "°"] });
            }

            // ---- the Sun (3x size) ----
            var sunAA = SM.altaz(sunEnu);
            if (sunAA.alt > -0.6) {
                var sp = f.pr.project(sunEnu);
                if (root.onScreen(sp, W, H, 40)) {
                    var srad = Math.max(7, 3 * 0.2666 * SM.D2R * f.S * 2 / (1 + sp[2]));
                    var scol = Lib.blackbody(Lib.SUN_T);
                    var sg = ctx.createRadialGradient(sp[0], sp[1], 0, sp[0], sp[1], srad * 6);
                    sg.addColorStop(0, Lib.hexA(scol, 0.55));
                    sg.addColorStop(0.25, Lib.hexA(scol, 0.16));
                    sg.addColorStop(1, Lib.hexA(scol, 0));
                    ctx.fillStyle = sg;
                    ctx.fillRect(sp[0] - srad * 6, sp[1] - srad * 6, srad * 12, srad * 12);
                    ctx.fillStyle = scol;
                    ctx.beginPath(); ctx.arc(sp[0], sp[1], srad, 0, 2 * Math.PI); ctx.fill();
                    hits.push({ x: sp[0], y: sp[1], title: "sun",
                                lines: ["G2 V · 5,772 K · " + f.sun.dist.toFixed(4) + " AU",
                                        "light left it " + Lib.hm(f.sun.dist * Lib.AU / Lib.C) + " ago",
                                        "alt " + sunAA.alt.toFixed(1) + "°  az " + sunAA.az.toFixed(1) + "°"] });
                }
            }

            // ---- the Moon (3x size), lit limb toward the Sun ----
            var mw = f.moon.w, maa = SM.altaz(mw);
            var cosE = SM.dot(SM.norm(mw), SM.norm(sunEnu));
            var elong = Math.acos(Math.max(-1, Math.min(1, cosE)));
            var illum = (1 - Math.cos(elong)) / 2;               // phase angle ≈ 180° − elongation
            if (maa.alt > -0.6) {
                var mp = f.pr.project(mw);
                if (root.onScreen(mp, W, H, 30)) {
                    var angR = Math.asin(1737.4 / f.moon.distKm);
                    var mr = Math.max(7, 3 * angR * f.S * 2 / (1 + mp[2]));
                    // screen direction toward the Sun along the great circle
                    var tdir = [sunEnu[0] - cosE * mw[0], sunEnu[1] - cosE * mw[1], sunEnu[2] - cosE * mw[2]];
                    var tl = Math.sqrt(SM.dot(tdir, tdir)) || 1;
                    var p2 = f.pr.project(SM.norm([mw[0] + 0.01 * tdir[0] / tl, mw[1] + 0.01 * tdir[1] / tl, mw[2] + 0.01 * tdir[2] / tl]));
                    var th = p2 ? Math.atan2(p2[1] - mp[1], p2[0] - mp[0]) : 0;
                    var lit = Lib.css(t.foreground, 0.95);
                    var dark = Lib.mix(t.muted, t.background, 0.55);  // earthshine
                    var mg = ctx.createRadialGradient(mp[0], mp[1], 0, mp[0], mp[1], mr * 4);
                    mg.addColorStop(0, Lib.css(t.foreground, 0.12 * illum + 0.03));
                    mg.addColorStop(1, Lib.css(t.foreground, 0));
                    ctx.fillStyle = mg;
                    ctx.fillRect(mp[0] - mr * 4, mp[1] - mr * 4, mr * 8, mr * 8);
                    ctx.save();
                    ctx.translate(mp[0], mp[1]);
                    ctx.rotate(th);                               // +x now points at the Sun
                    ctx.fillStyle = dark;
                    ctx.beginPath(); ctx.arc(0, 0, mr, 0, 2 * Math.PI); ctx.fill();
                    ctx.fillStyle = lit;
                    ctx.beginPath(); ctx.arc(0, 0, mr, -Math.PI / 2, Math.PI / 2, false); ctx.fill();
                    var rx = Math.abs(Math.cos(Math.PI - elong)) * mr;
                    ctx.fillStyle = illum < 0.5 ? dark : lit;
                    ctx.beginPath(); ctx.ellipse(-rx, -mr, 2 * rx, 2 * mr); ctx.fill();
                    ctx.restore();
                    font(Math.max(9, t.fontSize - 2));
                    ctx.fillStyle = Lib.css(t.foreground, 0.8);
                    ctx.fillText("moon " + Math.round(illum * 100) + "%", mp[0] + mr + 6, mp[1] + 4);
                    hits.push({ x: mp[0], y: mp[1], title: "moon",
                                lines: [Math.round(illum * 100) + "% lit · " + Lib.grouped(f.moon.distKm) + " km",
                                        "light left it " + (f.moon.distKm * 1000 / Lib.C).toFixed(2) + " s ago",
                                        "alt " + maa.alt.toFixed(1) + "°  az " + maa.az.toFixed(1) + "°"] });
                }
            }

            // ---- meteor shower radiants ----
            var showers = EV.activeShowers(f.jd);
            for (var ri = 0; ri < showers.length; ri++) {
                var sh = showers[ri];
                if (sh.zhr < 2) continue;
                var rw = SM.mul(f.A, SM.vec(sh.ra, sh.dec));
                if (rw[2] < 0.02) continue;
                var rp = f.pr.project(rw);
                if (!root.onScreen(rp, W, H, 0)) continue;
                var rc = Lib.css(t.accent4, 0.65);
                ctx.strokeStyle = rc;
                ctx.fillStyle = rc;
                ctx.lineWidth = 1;
                for (var rk = 0; rk < 8; rk++) {                  // a burst: where the meteors come from
                    var ra0 = rk * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(rp[0] + 5 * Math.cos(ra0), rp[1] + 5 * Math.sin(ra0));
                    ctx.lineTo(rp[0] + (rk % 2 ? 9 : 12) * Math.cos(ra0), rp[1] + (rk % 2 ? 9 : 12) * Math.sin(ra0));
                    ctx.stroke();
                }
                font(Math.max(9, t.fontSize - 3));
                ctx.fillText(sh.shower.name.toLowerCase(), rp[0] + 15, rp[1] + 4);
                var raltR = Math.asin(rw[2]);
                var hr = sh.zhr * Math.sin(raltR);
                var pk = Math.round(sh.days);
                hits.push({ x: rp[0], y: rp[1], kind: "radiant", code: sh.shower.code, title: sh.shower.name,
                            lines: ["meteor shower radiant · " + Math.round(raltR / SM.D2R) + "° up",
                                    "ZHR ~" + Math.round(sh.zhr) + " now (" + sh.shower.zhr + " at peak, "
                                        + (pk === 0 ? "today" : pk < 0 ? Math.abs(pk) + " d ahead" : pk + " d ago") + ")",
                                    "~" + Math.max(1, Math.round(hr)) + " per hour from here under dark skies",
                                    "debris of " + sh.shower.parent + " · " + sh.shower.v + " km/s",
                                    "click to launch one"] });
            }

            // ---- ground ----
            var horizonPts = [];
            ctx.beginPath();
            var first = true;
            for (var az = root.facing - 130; az <= root.facing + 130; az += 2) {
                var gp = f.pr.project(SM.enu(0, az));
                if (!gp) continue;
                horizonPts.push(gp);
                if (first) { ctx.moveTo(gp[0], gp[1]); first = false; } else ctx.lineTo(gp[0], gp[1]);
            }
            root.horizon = horizonPts;
            ctx.lineTo(W + 50, H + 50);
            ctx.lineTo(-50, H + 50);
            ctx.closePath();
            var bgc = t.background;
            ctx.fillStyle = "rgba(" + Math.round(bgc.r * 140) + "," + Math.round(bgc.g * 140) + "," + Math.round(bgc.b * 140) + ",1)";
            ctx.fill();
            ctx.lineWidth = 1;
            ctx.strokeStyle = Lib.css(t.muted, 0.7);
            ctx.beginPath();
            first = true;
            for (az = root.facing - 130; az <= root.facing + 130; az += 2) {
                gp = f.pr.project(SM.enu(0, az));
                if (!gp) continue;
                if (first) { ctx.moveTo(gp[0], gp[1]); first = false; } else ctx.lineTo(gp[0], gp[1]);
            }
            ctx.stroke();

            // ---- compass bezel: azimuth ticks along the horizon ----
            // Each tick points straight "down" into the ground at its own spot on
            // the curved horizon: the direction to the point 1° below it.
            // 1° ticks only once zoomed in enough for them to be 4 px apart.
            var c0 = f.pr.project(SM.enu(0, root.facing)), c1 = f.pr.project(SM.enu(0, root.facing + 1));
            var pxPerDeg = c0 && c1 ? Math.hypot(c1[0] - c0[0], c1[1] - c0[1]) : 0;
            var dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
            for (var h = 0; h < 720; h++) {                        // half degrees: NNE & co. sit at 22.5°
                var point = h % 45 === 0;                           // one of the 16 compass points
                if (h % 2 && !point) continue;
                var deg = h / 2, major = deg % 90 === 0, mid = deg % 45 === 0;   // N/E/S/W, NE/SE/SW/NW
                var len = major ? 10 : mid ? 7 : point || deg % 10 === 0 ? 5 : deg % 5 === 0 ? 3.5 : 2;
                if (len === 2 && pxPerDeg < 4) continue;
                var p0 = f.pr.project(SM.enu(0, deg));
                if (!root.onScreen(p0, W, H, 0)) continue;
                var p1 = f.pr.project(SM.enu(-1, deg));
                if (!p1) continue;
                var nx = p1[0] - p0[0], ny = p1[1] - p0[1], nl = Math.hypot(nx, ny) || 1;
                nx /= nl; ny /= nl;
                ctx.strokeStyle = Lib.css(mid ? t.foreground : t.muted, mid ? 0.75 : deg % 10 === 0 ? 0.7 : 0.45);
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(p0[0], p0[1]);
                ctx.lineTo(p0[0] + nx * len, p0[1] + ny * len);
                ctx.stroke();

                var label = point ? dirs[h / 45] : deg % 30 === 0 ? deg + "°" : "";
                if (label === "" || (!mid && point && pxPerDeg < 6)) continue;   // NNE etc. only when there's room
                font(major ? t.fontSize - 1 : mid ? t.fontSize - 2 : t.fontSize - 4, major ? "bold" : "");
                ctx.fillStyle = Lib.css(point ? (mid ? t.foreground : t.muted) : t.muted, point ? 0.85 : 0.6);
                var off = len + (major ? 14 : 11);
                ctx.fillText(label, p0[0] + nx * off - ctx.measureText(label).width / 2, p0[1] + ny * off + 4);
            }

            // ---- readout, bottom left on the ground ----
            var names = ["north", "north-northeast", "northeast", "east-northeast", "east", "east-southeast",
                         "southeast", "south-southeast", "south", "south-southwest", "southwest", "west-southwest",
                         "west", "west-northwest", "northwest", "north-northwest"];
            var facingName = names[Math.round(SM.mod(root.facing, 360) / 22.5) % 16];
            var lst = SM.lstHours(f.jd, root.longitude);
            var hud = [
                "facing " + facingName + " · lst " + Lib.hours(lst, true) + " · "
                    + Math.abs(root.latitude).toFixed(2) + "°" + (root.latitude >= 0 ? "N " : "S ")
                    + Math.abs(root.longitude).toFixed(2) + "°" + (root.longitude >= 0 ? "E" : "W"),
                "sun " + (sunAA.alt >= 0 ? "+" : "−") + Math.abs(sunAA.alt).toFixed(1) + "° " + Lib.twilight(sunAA.alt)
                    + " · stars to mag " + L.lim.toFixed(1)
                    + " · moon " + Math.round(illum * 100) + "% lit, " + (maa.alt >= 0 ? "up" : "down")
            ];
            if (root.offsetMin !== 0) {
                var om = Math.abs(root.offsetMin);
                hud.push("time warp T" + (root.offsetMin > 0 ? "+" : "−") + Math.floor(om / 60) + "h"
                         + Lib.pad(Math.round(om % 60), 2) + "m · middle-click: now");
            }
            font(Math.max(9, t.fontSize - 3));
            for (var hi = 0; hi < hud.length; hi++) {
                ctx.fillStyle = hi === 2 ? Lib.css(t.accent4, 0.9) : Lib.css(root.label, 0.85);
                ctx.fillText(hud[hi], 24, H - 46 + hi * 15);
            }
            ctx.fillStyle = Lib.css(t.muted, 0.8);
            ctx.fillText("scroll: turn · scroll the ground or drag the strip: time", 24, H - 46 - 32);
            ctx.fillText("right-click + scroll: zoom · middle-click: now · hover: identify", 24, H - 46 - 18);

            // ---- the time strip: 24 h of sky around now, drag to scrub ----
            var a = root.alm;
            if (a) {
                var x0 = Math.max(W * 0.36, 600), x1 = W - 32, sy = H - 40, bh = 7;
                var tx = function (ms) { return x0 + (ms - a.t0) / (a.t1 - a.t0) * (x1 - x0); };
                // sky state by Sun altitude, blended through the twilight bands
                var dayC = Qt.color(Lib.mix(t.accent2, t.foreground, 0.35));
                var civC = Qt.color(Lib.mix(t.accent5, t.accent4, 0.3));
                var nauC = t.accent7;
                var astC = Qt.color(Lib.mix(t.accent2, t.background, 0.45));
                var nitC = Qt.color(Lib.mix(t.background, t.muted, 0.35));
                var skyCol = function (alt) {
                    if (alt >= 0) return Lib.mix(civC, dayC, Math.min(1, alt / 6));
                    if (alt >= -6) return Lib.mix(nauC, civC, (alt + 6) / 6);
                    if (alt >= -12) return Lib.mix(astC, nauC, (alt + 12) / 6);
                    if (alt >= -18) return Lib.mix(nitC, astC, (alt + 18) / 6);
                    return Lib.mix(nitC, nitC, 0);
                };
                var band = ctx.createLinearGradient(x0, 0, x1, 0);
                for (var bi2 = 0; bi2 < a.sam.length; bi2++)
                    band.addColorStop(bi2 / (a.sam.length - 1), skyCol(a.sam[bi2].sun));
                ctx.fillStyle = band;
                ctx.fillRect(x0, sy, x1 - x0, bh);

                // Moon above the horizon: a thin line over the band
                ctx.fillStyle = Lib.css(t.foreground, 0.55);
                var stepW = (x1 - x0) / (a.sam.length - 1);
                for (var mi = 0; mi < a.sam.length - 1; mi++)
                    if (a.sam[mi].moon > -0.833 && a.sam[mi + 1].moon > -0.833)
                        ctx.fillRect(tx(a.sam[mi].ms), sy - 4, stepW + 0.5, 2);

                // hours (local), labeled every 3
                font(Math.max(9, t.fontSize - 4));
                var hr = new Date(a.t0); hr.setMinutes(0, 0, 0);
                for (var hm = hr.getTime() + 3600e3; hm <= a.t1; hm += 3600e3) {
                    var hx = tx(hm), h = new Date(hm).getHours(), third = h % 3 === 0;
                    ctx.fillStyle = Lib.css(t.muted, third ? 0.9 : 0.6);
                    ctx.fillRect(Math.round(hx), sy + bh + 1, 1, third ? 4 : 2);
                    if (third) {
                        var hl = Lib.pad(h, 2);
                        ctx.fillText(hl, hx - ctx.measureText(hl).width / 2, sy + bh + 15);
                    }
                }

                // events, labels stacked in two rows so they don't collide
                var rowEnd = [-1e9, -1e9];
                for (var ei = 0; ei < a.ev.length; ei++) {
                    var e = a.ev[ei], ex = tx(e.ms);
                    var ec = e.key === "moon" ? t.foreground : e.name === "dark" || e.name === "dawn" ? t.accent7 : t.accent5;
                    ctx.fillStyle = Lib.css(ec, 0.85);
                    ctx.fillRect(Math.round(ex), sy - 1, 1, bh + 2);
                    var el = e.name + " " + Qt.formatTime(new Date(e.ms), "HH:mm");
                    var ew = ctx.measureText(el).width;
                    for (var r = 0; r < 2; r++) {
                        if (rowEnd[r] < ex - ew / 2 - 8) {
                            ctx.fillStyle = Lib.css(ec, 0.7);
                            ctx.fillText(el, ex - ew / 2, sy - 9 - r * 11);
                            rowEnd[r] = ex + ew / 2;
                            break;
                        }
                    }
                }

                // now: a small notch under the band
                var nx = tx(root.nowMs);
                ctx.fillStyle = Lib.css(t.foreground, 0.9);
                ctx.beginPath(); ctx.moveTo(nx, sy + bh + 1); ctx.lineTo(nx - 4, sy + bh + 6); ctx.lineTo(nx + 4, sy + bh + 6); ctx.closePath(); ctx.fill();

                // the time being shown: a gold handle through the band
                var shown = root.nowMs + root.offsetMin * 60000;
                var sx = Math.max(x0, Math.min(x1, tx(shown)));
                ctx.fillStyle = Lib.css(t.accent4, 0.95);
                ctx.fillRect(Math.round(sx) - 1, sy - 6, 2, bh + 12);
                if (root.offsetMin !== 0) {
                    font(Math.max(9, t.fontSize - 3), "bold");
                    var sl = Qt.formatTime(new Date(shown), "HH:mm");
                    ctx.fillText(sl, Math.max(x0, Math.min(x1 - ctx.measureText(sl).width, sx - ctx.measureText(sl).width / 2)), sy - 33);
                }
                root.strip = { x0: x0, x1: x1, y0: sy - 40, y1: sy + bh + 18, t0: a.t0, t1: a.t1 };
            }

            root.targets = hits;
        }
    }

    // Every 30 s; the sky turns ~0.125° in that time, about a pixel.
    Timer {
        interval: root.refreshMs; repeat: true; running: root.live
        onTriggered: root.nowMs = Date.now()
    }

    // ================= interaction =================
    // A wallpaper never has keyboard focus, and Wayland only reports Shift/Ctrl
    // to the focused app, so these controls use only what the pointer knows:
    //   scroll over the sky                 turn (vertical or sideways swipe)
    //   scroll over the ground              run time back and forth
    //   hold right button + scroll          zoom
    //   middle-click                        back to now
    // Scaled by the actual scroll amount, so touchpads glide instead of jumping.
    property var hovered: null
    property var horizon: []                  // screen points along the horizon, from the last paint
    property var strip: null                  // the time strip's box, from the last paint
    property bool scrubbing: false
    property var stripHover: null             // { x, y, text } while the pointer is on the strip

    function inStrip(x, y) {
        var s = strip;
        return !!s && x >= s.x0 - 8 && x <= s.x1 + 8 && y >= s.y0 && y <= s.y1;
    }
    function stripTime(x) {
        var s = strip, u = Math.max(0, Math.min(1, (x - s.x0) / (s.x1 - s.x0)));
        return s.t0 + u * (s.t1 - s.t0);
    }
    function scrubTo(x) { warped(Math.round((stripTime(x) - nowMs) / 60000)); }
    function stripText(x) {
        var ms = stripTime(x), sa = almAt("sun", ms), ma = almAt("moon", ms);
        var state = sa > -0.833 ? "daylight" : Lib.twilight(sa);
        return Qt.formatTime(new Date(ms), "HH:mm") + " · " + state + " · moon " + (ma > -0.833 ? "up" : "down");
    }

    function groundAt(x, y) {
        var h = horizon;
        for (var i = 1; i < h.length; i++) {
            if ((h[i - 1][0] - x) * (h[i][0] - x) <= 0) {
                var t = (x - h[i - 1][0]) / ((h[i][0] - h[i - 1][0]) || 1);
                return y > h[i - 1][1] + t * (h[i][1] - h[i - 1][1]);
            }
        }
        return y > height * 0.88;
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: root.stripHover || root.scrubbing ? Qt.SizeHorCursor : Qt.ArrowCursor
        onPressed: m => {
            if (m.button !== Qt.LeftButton) return;
            if (root.hovered && root.hovered.kind === "radiant") { root.launch(root.hovered.code); return; }
            if (root.inStrip(m.x, m.y)) { root.scrubbing = true; root.scrubTo(m.x); }
            else m.accepted = false;            // left-click elsewhere on the desktop: not ours
        }
        onReleased: root.scrubbing = false
        onCanceled: root.scrubbing = false
        onClicked: m => { if (m.button === Qt.MiddleButton) root.warped(0); }
        onWheel: w => {
            var notches = (w.angleDelta.y || w.angleDelta.x) / 120;   // 1.0 per mouse-wheel click
            if (notches === 0) return;
            if (mouse.pressedButtons & Qt.RightButton)
                root.zoomed(Math.max(60, Math.min(170, root.fov - 10 * notches)));
            else if (root.groundAt(w.x, w.y))
                root.warped(Math.round(root.offsetMin + 10 * notches));
            else
                root.turned(SM.mod(root.facing - 10 * notches, 360));
        }
        onPositionChanged: m => {
            if (root.scrubbing) root.scrubTo(m.x);
            root.stripHover = root.inStrip(m.x, m.y) || root.scrubbing
                ? { x: m.x, y: root.strip.y0, text: root.stripText(m.x) } : null;
            var best = null, bd = 14 * 14;
            for (const h of root.targets) {
                var dx = h.x - m.x, dy = h.y - m.y, d2 = dx * dx + dy * dy;
                if (d2 < bd) { bd = d2; best = h; }
            }
            root.hovered = best;
        }
        onExited: { root.hovered = null; root.stripHover = null; }
    }

    // ================= meteors =================
    // Each one is a streak running *away* from its shower's radiant along a great
    // circle: short near the radiant (we see those nearly head-on), longer
    // further out. Rates are the real ones: ZHR × sin(radiant altitude), plus
    // ~6/h of sporadic background, and only once the Sun is 6° down.
    // Colour follows speed: fast meteors (Orionids, Leonids, 66–71 km/s) burn
    // green-white (magnesium, oxygen), slow ones (Draconids, Taurids) yellow-
    // orange (sodium, iron).
    // They're animated as overlay items, so the sky itself never repaints for them.
    function meteorColor(v) {
        return v >= 55 ? Lib.mix(theme.foreground, theme.accent3, 0.4)
             : v >= 35 ? Lib.mix(theme.foreground, theme.accent4, 0.1)
             : Lib.mix(theme.foreground, theme.accent4, 0.55);
    }
    function spawnFrom(raDeg, decDeg, v) {
        var f = frame(width, height);
        var r = SM.mul(f.A, SM.vec(raDeg, decDeg));
        var helper = Math.abs(r[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
        var u = SM.norm([r[1] * helper[2] - r[2] * helper[1], r[2] * helper[0] - r[0] * helper[2], r[0] * helper[1] - r[1] * helper[0]]);
        var w = [r[1] * u[2] - r[2] * u[1], r[2] * u[0] - r[0] * u[2], r[0] * u[1] - r[1] * u[0]];
        for (var attempt = 0; attempt < 12; attempt++) {
            var th = Math.random() * 2 * Math.PI, dir = [0, 1, 2].map(k => Math.cos(th) * u[k] + Math.sin(th) * w[k]);
            var d = (12 + 70 * Math.random()) * SM.D2R;
            var L = Math.max(3, (8 + 16 * Math.random()) * Math.sin(d)) * SM.D2R;  // foreshortened near the radiant
            var P = function (a) { return [0, 1, 2].map(k => Math.cos(a) * r[k] + Math.sin(a) * dir[k]); };
            var p1w = P(d), p2w = P(d + L);
            if (p1w[2] < 0.09 || p2w[2] < 0.05) continue;                // keep it above the horizon
            var p1 = f.pr.project(p1w), p2 = f.pr.project(p2w);
            if (!onScreen(p1, width, height, -20) || !onScreen(p2, width, height, -20)) continue;
            for (var i = 0; i < pool.count; i++) {
                var m = pool.itemAt(i);
                if (m.busy) continue;
                var fire = Math.random() < 0.06;
                m.fly(p1, p2, meteorColor(v), Math.min(1.4, Math.max(0.3, 0.3 + 14 / v + 0.25 * Math.random())), fire);
                return true;
            }
            return false;
        }
        return false;
    }
    function launch(code) {
        var act = EV.activeShowers(frame(width, height).jd).find(a => a.shower.code === code);
        if (act) spawnFrom(act.ra, act.dec, act.shower.v);
    }
    // Pick the next meteor: which shower, and how long until it (Poisson process).
    function scheduleMeteor() {
        var f = frame(width, height);
        var sunAlt = SM.altaz(f.sun.w).alt;
        if (!meteors) { meteorTimer.stop(); return; }
        if (sunAlt > -6) { meteorTimer.interval = 60000; meteorTimer.next = null; meteorTimer.fire = false; meteorTimer.restart(); return; }
        var cands = [{ sporadic: true, hr: EV.SPORADIC_ZHR }];
        var act = EV.activeShowers(f.jd);
        for (var i = 0; i < act.length; i++) {
            var a = SM.altaz(SM.mul(f.A, SM.vec(act[i].ra, act[i].dec))).alt;
            if (a > 0) cands.push({ act: act[i], hr: act[i].zhr * Math.sin(a * SM.D2R) });
        }
        var total = cands.reduce((s, c) => s + c.hr, 0);
        var pick = Math.random() * total, chosen = cands[0];
        for (var k = 0; k < cands.length; k++) { pick -= cands[k].hr; if (pick <= 0) { chosen = cands[k]; break; } }
        var wait = -Math.log(1 - Math.random()) / (total / 3600) * 1000;
        meteorTimer.next = chosen;
        meteorTimer.interval = Math.max(500, Math.min(wait, 60000));
        meteorTimer.fire = wait <= 60000;                 // long waits: re-roll after a minute
        meteorTimer.restart();
    }
    onMeteorsChanged: if (meteors && cat) scheduleMeteor(); else meteorTimer.stop()
    Timer {
        id: meteorTimer
        property var next: null
        property bool fire: false
        onTriggered: {
            if (fire && next) {
                if (next.sporadic) {
                    var z = 2 * Math.random() - 1, ph = 2 * Math.PI * Math.random();
                    root.spawnFrom(ph / SM.D2R, Math.asin(z) / SM.D2R, 25 + 45 * Math.random());
                } else {
                    root.spawnFrom(next.act.ra, next.act.dec, next.act.shower.v);
                }
            }
            root.scheduleMeteor();
        }
    }

    Repeater {
        id: pool
        model: 4
        Item {
            id: met
            property bool busy: false
            property real t: 0
            property real x1: 0
            property real y1: 0
            property real x2: 0
            property real y2: 0
            property real len: 0
            property real tail: 0
            property color tint: "white"
            property bool fireball: false
            visible: busy
            x: x1 + (x2 - x1) * t
            y: y1 + (y2 - y1) * t
            rotation: Math.atan2(y2 - y1, x2 - x1) / SM.D2R
            transformOrigin: Item.TopLeft
            opacity: Math.min(1, t * 6) * Math.pow(1 - t, 0.7)           // flares fast, fades as it burns out
            width: 1
            height: 1

            function fly(p1, p2, col, secs, fire) {
                x1 = p1[0]; y1 = p1[1]; x2 = p2[0]; y2 = p2[1];
                len = Math.hypot(x2 - x1, y2 - y1);
                tail = len * (fire ? 0.8 : 0.6);
                tint = col;
                fireball = fire;
                anim.duration = secs * 1000 * (fire ? 1.4 : 1);
                busy = true;
                t = 0;
                anim.restart();
            }
            NumberAnimation {
                id: anim
                target: met; property: "t"; from: 0; to: 1
                onFinished: met.busy = false
            }

            // the trail, behind the head (rotation makes +x the direction of travel)
            Rectangle {
                x: -width
                y: -height / 2
                width: Math.max(1, Math.min(met.tail, met.len * met.t))
                height: met.fireball ? 2.6 : 1.6
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: met.tint }
                }
            }
            Rectangle {                                 // the head
                x: -width / 2; y: -height / 2
                width: met.fireball ? 4.5 : 2.4; height: width; radius: width / 2
                color: Qt.lighter(met.tint, 1.2)
            }
        }
    }

    Rectangle {
        visible: root.stripHover !== null
        x: root.stripHover ? Math.max(8, Math.min(root.width - width - 8, root.stripHover.x - width / 2)) : 0
        y: root.stripHover ? root.stripHover.y - height - 4 : 0
        width: stripLabel.implicitWidth + 16
        height: stripLabel.implicitHeight + 8
        radius: 3
        color: Qt.rgba(root.theme.barColor.r, root.theme.barColor.g, root.theme.barColor.b, 0.94)
        border.width: 1
        border.color: root.theme.accent4
        Text {
            id: stripLabel
            anchors.centerIn: parent
            text: root.stripHover ? root.stripHover.text : ""
            color: root.theme.foreground
            font { family: root.theme.fontFamily; pixelSize: root.theme.fontSize - 2 }
        }
    }

    Rectangle {
        visible: root.hovered !== null
        x: root.hovered ? Math.min(root.width - width - 8, root.hovered.x + 14) : 0
        y: root.hovered ? Math.max(8, root.hovered.y - height - 10) : 0
        width: tipCol.implicitWidth + 24
        height: tipCol.implicitHeight + 18
        color: Qt.rgba(root.theme.barColor.r, root.theme.barColor.g, root.theme.barColor.b, 0.94)
        border.width: 1
        border.color: Lib.mix(root.theme.muted, root.theme.barColor, 0.35)
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2
            color: root.theme.accent4
        }
        Column {
            id: tipCol
            x: 12; y: 10
            spacing: 3
            Text {
                text: root.hovered ? root.hovered.title.toUpperCase() : ""
                color: root.theme.accent4
                font { family: root.theme.fontFamily; pixelSize: root.theme.fontSize - 3; letterSpacing: 2.5; bold: true }
            }
            Repeater {
                model: root.hovered ? root.hovered.lines : []
                Text {
                    required property string modelData
                    text: modelData
                    color: root.theme.foreground
                    font { family: root.theme.fontFamily; pixelSize: root.theme.fontSize - 2 }
                }
            }
        }
    }
}
