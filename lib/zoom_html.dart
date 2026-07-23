// Erzeugt aus einer (riesigen) PDF-Seite EINE offline-fähige HTML-Datei mit
// Karten-Zoom (Kachel-Pyramide wie bei Google Maps): mehrere Zoomstufen,
// 512-px-JPEG-Kacheln, alle als Base64 eingebettet. Der eingebaute Viewer
// zeigt immer nur die sichtbaren Kacheln der passenden Stufe an – dadurch
// öffnet die Datei auch auf dem Handy sofort und zoomt ohne Wartezeit scharf.
//
// Speicher: Es wird nie die ganze Seite auf einmal gerastert. Jede Zoomstufe
// wird in waagrechten Streifen gerendert (Budget [stripBudgetBytes]), die
// Kacheln daraus werden in einem Hintergrund-Isolate geschnitten, JPEG-kodiert
// und Base64-verpackt und sofort in die Datei geschrieben (Streaming).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Kachelgröße in Pixeln (Kante).
const int zoomHtmlTileSize = 512;

/// JPEG-Qualität der Kacheln.
const int zoomHtmlJpegQuality = 80;

/// Eine Zoomstufe der Pyramide.
class _Level {
  _Level(this.width, this.height);
  final int width;
  final int height;
  int get cols => (width + zoomHtmlTileSize - 1) ~/ zoomHtmlTileSize;
  int get rows => (height + zoomHtmlTileSize - 1) ~/ zoomHtmlTileSize;
}

/// Schneidet einen gerenderten Streifen (BGRA) in Kacheln, kodiert sie als
/// JPEG und liefert (Kachel-Schlüssel, Base64) zurück. Läuft im Isolate.
List<(String, String)> _encodeStrip(
    (int, int, int, int, int, TransferableTypedData, int, int) e) {
  final (level, tileY0, stripW, stripH, quality, data, tile, levelCols) = e;
  final image = img.Image.fromBytes(
    width: stripW,
    height: stripH,
    bytes: data.materialize(),
    order: img.ChannelOrder.bgra,
  );
  final out = <(String, String)>[];
  final rows = (stripH + tile - 1) ~/ tile;
  for (int ty = 0; ty < rows; ty++) {
    for (int tx = 0; tx < levelCols; tx++) {
      final x = tx * tile;
      final y = ty * tile;
      final w = math.min(tile, stripW - x);
      final h = math.min(tile, stripH - y);
      if (w <= 0 || h <= 0) continue;
      final tileImg = img.copyCrop(image, x: x, y: y, width: w, height: h);
      final jpg = img.encodeJpg(tileImg, quality: quality);
      out.add(('$level/${tx}_${tileY0 + ty}', base64Encode(jpg)));
    }
  }
  return out;
}

/// Erzeugt die Zoom-HTML für [page] und schreibt sie nach [outPath].
///
/// [dpi] bestimmt die Auflösung der schärfsten Stufe. [stripBudgetBytes]
/// begrenzt den Rohpuffer je Render-Streifen (BGRA, 4 Byte/Pixel).
/// [onToken] meldet das jeweils aktive Render-Token (für den
/// Abbrechen-Knopf), [isCancelled] wird zwischen den Streifen geprüft,
/// [onProgress] liefert Status + Fortschritt 0..1 innerhalb dieser Seite.
///
/// Gibt true zurück, wenn die Datei fertig geschrieben wurde (false = Abbruch).
Future<bool> writeZoomHtml({
  required PdfPage page,
  required String outPath,
  required String title,
  required int dpi,
  required int stripBudgetBytes,
  void Function(PdfPageRenderCancellationToken?)? onToken,
  bool Function()? isCancelled,
  void Function(String status, double progress)? onProgress,
}) async {
  bool cancelled() => isCancelled?.call() ?? false;

  // Zoomstufen planen: Stufe N = volle Auflösung bei [dpi], darunter jeweils
  // halbiert, bis die ganze Seite in ~1024 px passt.
  final scaleFull = dpi / 72.0;
  final levels = <_Level>[];
  {
    var w = (page.width * scaleFull).floor();
    var h = (page.height * scaleFull).floor();
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    final tops = <_Level>[];
    while (true) {
      tops.add(_Level(w, h));
      if (math.max(w, h) <= 1024) break;
      w = math.max(1, w ~/ 2);
      h = math.max(1, h ~/ 2);
    }
    levels.addAll(tops.reversed); // levels[0] = kleinste Stufe
  }
  final maxLevel = levels.length - 1;
  final backdropLevel = math.min(2, maxLevel);

  // Streifen je Stufe planen (Höhe = Vielfaches der Kachelkante, damit keine
  // Kachel über eine Streifengrenze läuft).
  final stripsPerLevel = <int, List<(int y0, int h)>>{};
  int totalStrips = 0;
  for (int l = 0; l <= maxLevel; l++) {
    final lv = levels[l];
    final int maxRows = math.max(
        1, stripBudgetBytes ~/ (lv.width * 4 * zoomHtmlTileSize));
    final int stripH = maxRows * zoomHtmlTileSize;
    final strips = <(int, int)>[];
    for (int y = 0; y < lv.height; y += stripH) {
      strips.add((y, math.min(stripH, lv.height - y)));
    }
    stripsPerLevel[l] = strips;
    totalStrips += strips.length;
  }

  final meta = {
    'tile': zoomHtmlTileSize,
    'maxLevel': maxLevel,
    'backdropLevel': backdropLevel,
    'levels': {
      for (int l = 0; l <= maxLevel; l++)
        '$l': {
          'w': levels[l].width,
          'h': levels[l].height,
          'cols': levels[l].cols,
          'rows': levels[l].rows,
        }
    },
    'title': title,
  };

  final file = File(outPath);
  IOSink? sink;
  var ok = false;
  try {
    sink = file.openWrite();
    final safeTitle = const HtmlEscape().convert(title);
    sink.write(_htmlHead.replaceAll('@@TITLE@@', safeTitle));
    sink.write(jsonEncode(meta));
    sink.write(';\nconst TILES = {');

    int doneStrips = 0;
    for (int l = 0; l <= maxLevel && !cancelled(); l++) {
      final lv = levels[l];
      final levelScale = scaleFull / math.pow(2, maxLevel - l);
      for (final (y0, stripH) in stripsPerLevel[l]!) {
        if (cancelled()) break;
        onProgress?.call(
            'Zoomstufe ${l + 1}/${maxLevel + 1} wird gerendert …',
            doneStrips / totalStrips);

        final token = page.createCancellationToken();
        onToken?.call(token);
        final rendered = await page.render(
          x: 0,
          y: y0,
          width: lv.width,
          height: stripH,
          fullWidth: page.width * levelScale,
          fullHeight: page.height * levelScale,
          backgroundColor: 0xFFFFFFFF,
          cancellationToken: token,
        );
        onToken?.call(null);
        if (rendered == null) {
          if (cancelled()) break;
          throw Exception('Zoomstufe ${l + 1} konnte nicht gerendert werden.');
        }

        final params = (
          l,
          y0 ~/ zoomHtmlTileSize,
          rendered.width,
          rendered.height,
          zoomHtmlJpegQuality,
          TransferableTypedData.fromList([rendered.pixels]),
          zoomHtmlTileSize,
          lv.cols,
        );
        rendered.dispose();
        final tiles = await compute(_encodeStrip, params);
        for (final (key, b64) in tiles) {
          sink.write('"$key":"$b64",');
        }
        doneStrips++;
        onProgress?.call(
            'Zoomstufe ${l + 1}/${maxLevel + 1} wird gerendert …',
            doneStrips / totalStrips);
      }
    }

    if (!cancelled()) {
      sink.write('};\n');
      sink.write(_htmlTail);
      await sink.flush();
      ok = true;
    }
  } finally {
    await sink?.close();
    onToken?.call(null);
    if (!ok) {
      // Abbruch/Fehler: halbe Datei nicht liegen lassen.
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
  return ok;
}

// ---------------------------------------------------------------------------
// Viewer-Template (getestet). Teil A endet mitten in `const META = `,
// danach folgen META-JSON, `;\nconst TILES = {`, die Kacheln und Teil B.
// ---------------------------------------------------------------------------

const String _htmlHead = r'''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>@@TITLE@@</title>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="mobile-web-app-capable" content="yes">
<style>
  html, body { margin:0; padding:0; height:100%; overflow:hidden;
    background:#0b0e14; touch-action:none; overscroll-behavior:none;
    -webkit-user-select:none; user-select:none;
    font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif; }
  #viewport { position:fixed; inset:0; overflow:hidden; cursor:grab; }
  #viewport.drag { cursor:grabbing; }
  #stage { position:absolute; left:0; top:0; transform-origin:0 0; will-change:transform; }
  .layer { position:absolute; left:0; top:0; transform-origin:0 0; }
  .layer img { position:absolute; display:block; }
  #bar { position:fixed; left:0; right:0; top:0; display:flex; align-items:center; gap:8px;
    padding:calc(env(safe-area-inset-top, 0px) + 8px) 12px 8px 12px;
    background:linear-gradient(rgba(5,8,14,.85), rgba(5,8,14,0)); color:#e8e2d5;
    pointer-events:none; z-index:10; }
  #bar .title { font-size:15px; font-weight:600; letter-spacing:.04em; text-shadow:0 1px 3px #000;
    flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #bar button { pointer-events:auto; width:40px; height:40px; border-radius:10px; border:1px solid rgba(255,255,255,.25);
    background:rgba(20,26,38,.75); color:#e8e2d5; font-size:20px; line-height:1; }
  #bar button.wide { width:auto; padding:0 12px; font-size:13px; }
  #bar button:active { background:rgba(60,70,95,.9); }
  #hint { position:fixed; bottom:calc(env(safe-area-inset-bottom, 0px) + 14px); left:50%; transform:translateX(-50%);
    background:rgba(10,14,22,.8); color:#cfc8b8; font-size:13px; padding:8px 14px; border-radius:999px;
    z-index:10; transition:opacity .6s; pointer-events:none; white-space:nowrap; }
  #loading { position:fixed; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center;
    gap:14px; background:#0b0e14; color:#cfc8b8; z-index:20; font-size:15px; }
  #loading .spin { width:34px; height:34px; border-radius:50%; border:3px solid rgba(255,255,255,.15);
    border-top-color:#d9b25a; animation:sp 1s linear infinite; }
  @keyframes sp { to { transform:rotate(360deg); } }
</style>
</head>
<body>
<div id="viewport"><div id="stage"></div></div>
<div id="bar">
  <div class="title">@@TITLE@@</div>
  <button id="zo" aria-label="Herauszoomen">&minus;</button>
  <button id="zi" aria-label="Hineinzoomen">+</button>
  <button id="fit" class="wide">Übersicht</button>
</div>
<div id="hint">Ziehen = verschieben &nbsp;·&nbsp; Kneifen / Mausrad = zoomen</div>
<div id="loading"><div class="spin"></div><div>Wird geladen …</div></div>
<script>
const META = ''';

const String _htmlTail = r'''
const TS = META.tile, MAXL = META.maxLevel;
const worldW = META.levels[MAXL].w, worldH = META.levels[MAXL].h;
const vp = document.getElementById('viewport');
const stage = document.getElementById('stage');

let scale = 0, tx = 0, ty = 0;     // screen = world*scale + t
let minScale = 0.01, maxScale = 4;
let curLevel = -1;
const layers = {};                  // level -> {el, imgs:Map}

function levelScale(l) { return Math.pow(2, l - MAXL); }
function pickLevel(s) {
  for (let l = 0; l <= MAXL; l++) if (levelScale(l) >= s * 0.999) return l;
  return MAXL;
}
function makeLayer(l) {
  if (layers[l]) return layers[l];
  const el = document.createElement('div');
  el.className = 'layer';
  const inv = 1 / levelScale(l);   // Stufenpixel -> Weltpixel
  el.style.transform = 'scale(' + inv + ')';
  stage.appendChild(el);
  layers[l] = { el, imgs: new Map() };
  return layers[l];
}
function fillLayer(l, x0, x1, y0, y1, prune) {
  const L = makeLayer(l);
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const key = x + '_' + y;
      if (L.imgs.has(key)) continue;
      const data = TILES[l + '/' + key];
      if (!data) continue;
      const img = new Image();
      img.decoding = 'async';
      img.src = 'data:image/jpeg;base64,' + data;
      img.style.left = (x * TS) + 'px';
      img.style.top = (y * TS) + 'px';
      L.el.appendChild(img);
      L.imgs.set(key, img);
    }
  }
  if (prune) {
    for (const [key, img] of L.imgs) {
      const [x, y] = key.split('_').map(Number);
      if (x < x0 - 1 || x > x1 + 1 || y < y0 - 1 || y > y1 + 1) { img.remove(); L.imgs.delete(key); }
    }
  }
}
function render() {
  stage.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
  const l = pickLevel(scale), info = META.levels[l];
  const ls = levelScale(l);
  const wx0 = (-tx) / scale, wy0 = (-ty) / scale;
  const wx1 = (vp.clientWidth - tx) / scale, wy1 = (vp.clientHeight - ty) / scale;
  const x0 = Math.max(0, Math.floor(wx0 * ls / TS)), y0 = Math.max(0, Math.floor(wy0 * ls / TS));
  const x1 = Math.min(info.cols - 1, Math.floor(wx1 * ls / TS)), y1 = Math.min(info.rows - 1, Math.floor(wy1 * ls / TS));
  if (l !== curLevel) {
    for (const k of Object.keys(layers)) {
      const kl = Number(k);
      if (kl !== l && kl !== META.backdropLevel) { layers[k].el.remove(); delete layers[k]; }
    }
    curLevel = l;
  }
  fillLayer(l, x0, x1, y0, y1, true);
}
function clampView() {
  scale = Math.min(maxScale, Math.max(minScale, scale));
  const vw = vp.clientWidth, vh = vp.clientHeight;
  const sw = worldW * scale, sh = worldH * scale;
  if (sw <= vw) tx = (vw - sw) / 2; else tx = Math.min(0, Math.max(vw - sw, tx));
  if (sh <= vh) ty = (vh - sh) / 2; else ty = Math.min(0, Math.max(vh - sh, ty));
}
function zoomAt(px, py, f) {
  if (!(scale > 0)) { fit(); if (!(scale > 0)) return; }
  const ns = Math.min(maxScale, Math.max(minScale, scale * f));
  f = ns / scale;
  tx = px - (px - tx) * f;
  ty = py - (py - ty) * f;
  scale = ns;
  clampView(); render();
}
function fit() {
  const s = Math.min(vp.clientWidth / worldW, vp.clientHeight / worldH);
  minScale = s;
  scale = s;
  tx = 0; ty = 0;
  clampView(); render();
}

const pointers = new Map();
let lastTap = 0, lastDist = 0;
vp.addEventListener('pointerdown', e => {
  vp.setPointerCapture(e.pointerId);
  pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  vp.classList.add('drag');
  if (pointers.size === 1) {
    const now = Date.now();
    if (now - lastTap < 320) { zoomAt(e.clientX, e.clientY, 2.5); lastTap = 0; }
    else lastTap = now;
  } else if (pointers.size === 2) {
    const [a, b] = [...pointers.values()];
    lastDist = Math.hypot(a.x - b.x, a.y - b.y);
  }
});
vp.addEventListener('pointermove', e => {
  const p = pointers.get(e.pointerId);
  if (!p) return;
  if (pointers.size === 1) {
    tx += e.clientX - p.x; ty += e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    clampView(); render();
  } else if (pointers.size === 2) {
    p.x = e.clientX; p.y = e.clientY;
    const [a, b] = [...pointers.values()];
    const d = Math.hypot(a.x - b.x, a.y - b.y);
    if (lastDist > 0) zoomAt((a.x + b.x) / 2, (a.y + b.y) / 2, d / lastDist);
    lastDist = d;
  }
});
function endPointer(e) {
  pointers.delete(e.pointerId);
  lastDist = 0;
  if (pointers.size === 0) vp.classList.remove('drag');
}
vp.addEventListener('pointerup', endPointer);
vp.addEventListener('pointercancel', endPointer);
vp.addEventListener('wheel', e => {
  e.preventDefault();
  zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.0018));
}, { passive: false });
document.getElementById('zi').addEventListener('click', () => zoomAt(vp.clientWidth / 2, vp.clientHeight / 2, 1.6));
document.getElementById('zo').addEventListener('click', () => zoomAt(vp.clientWidth / 2, vp.clientHeight / 2, 1 / 1.6));
document.getElementById('fit').addEventListener('click', fit);
window.addEventListener('resize', () => {
  if (!(vp.clientWidth > 0 && vp.clientHeight > 0)) return;
  const wasMin = !(scale > minScale + 1e-9);
  const s = Math.min(vp.clientWidth / worldW, vp.clientHeight / worldH); minScale = s;
  if (wasMin || !(scale > 0)) { scale = s; tx = 0; ty = 0; }
  clampView(); render(); });

(function start() {
  const bl = META.backdropLevel, info = META.levels[bl];
  fillLayer(bl, 0, info.cols - 1, 0, info.rows - 1, false);
  function tryFit() {
    if (vp.clientWidth > 0 && vp.clientHeight > 0) { fit(); return true; }
    return false;
  }
  if (!tryFit()) {
    const iv = setInterval(() => { if (tryFit()) clearInterval(iv); }, 150);
  }
  document.getElementById('loading').remove();
  setTimeout(() => { const h = document.getElementById('hint'); if (h) h.style.opacity = '0'; }, 4000);
})();
window.__view = { zoomAt, fit, get state() { return { scale, tx, ty, curLevel }; } };
</script>
</body>
</html>
''';
