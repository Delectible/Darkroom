// The Darkroom rabbit (same drawing as tool/icon/make_icons.py, on its 192
// design grid): two ears, a round head and X'd-out eyes, as a flat
// single-colour glyph for printing on labels and bodies.

/** Draws the rabbit glyph on [g] (a 2D context), its head-and-ears box
 *  centred at (cx, cy) and [h] pixels tall. Eyes are cut out (transparent). */
export function drawRabbit(g, cx, cy, h, color) {
  const box = [52, 29, 157, 158];               // glyph bounds on the 192 grid
  const s = h / (box[3] - box[1]);
  const c = document.createElement('canvas');
  const w = Math.ceil((box[2] - box[0]) * s) + 4, hh = Math.ceil(h) + 4;
  c.width = w; c.height = hh;
  const x = c.getContext('2d');
  x.translate(2 - box[0] * s, 2 - box[1] * s);
  x.scale(s, s);
  x.fillStyle = x.strokeStyle = color;
  x.lineCap = 'round'; x.lineJoin = 'round';
  x.lineWidth = 22;
  x.beginPath(); x.moveTo(80, 104); x.lineTo(70, 40); x.stroke();                     // straight ear
  x.beginPath(); x.moveTo(110, 100); x.lineTo(120, 48); x.lineTo(146, 60); x.stroke(); // folded ear
  x.beginPath(); x.ellipse(94, 122, 42, 36, 0, 0, Math.PI * 2); x.fill();               // head
  x.globalCompositeOperation = 'destination-out';
  x.lineWidth = 5.5;
  for (const [ex, ey] of [[80, 118], [108, 118]]) {
    x.beginPath(); x.moveTo(ex - 7, ey - 7); x.lineTo(ex + 7, ey + 7); x.stroke();
    x.beginPath(); x.moveTo(ex + 7, ey - 7); x.lineTo(ex - 7, ey + 7); x.stroke();
  }
  g.drawImage(c, cx - w / 2, cy - hh / 2);
  return w;                                        // glyph width in px
}
