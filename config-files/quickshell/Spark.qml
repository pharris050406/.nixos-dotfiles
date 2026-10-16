import QtQuick
import "Lib.js" as Lib

// A real chart instead of text glyphs: area-filled trace of 0..1 samples,
// oldest on the left. Optional second series drawn as a bare line on top.
Canvas {
    id: spark

    property var values: []
    property var values2: null
    property color tint: "white"
    property color tint2: "white"
    property color baseColor: "#444444"
    property real fillAlpha: 0.18

    implicitHeight: 20
    antialiasing: true

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onTintChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function trace(ctx, vals, col, fill) {
        var n = vals ? vals.length : 0;
        if (n < 2 || width <= 0) return;
        var h = height - 1, dx = width / (n - 1);
        ctx.beginPath();
        for (var i = 0; i < n; i++) {
            var x = i * dx, y = 1 + (h - 1) * (1 - Lib.clamp01(vals[i]));
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.lineWidth = 1.25;
        ctx.lineJoin = "round";
        ctx.strokeStyle = Lib.css(col, 1);
        ctx.stroke();
        if (!fill) return;
        ctx.lineTo(width, h + 1);
        ctx.lineTo(0, h + 1);
        ctx.closePath();
        ctx.fillStyle = Lib.css(col, spark.fillAlpha);
        ctx.fill();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = Lib.css(spark.baseColor, 0.6);
        ctx.fillRect(0, height - 1, width, 1);
        trace(ctx, spark.values, spark.tint, true);
        if (spark.values2) trace(ctx, spark.values2, spark.tint2, false);
    }
}
