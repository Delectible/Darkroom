#version 460 core
// Procedural agglomerated cork: lots of small, irregular granules pressed
// together (varied size and tone, from pale tan to orange-brown, the odd dark
// one), each softly domed and lit from the top left, with dark crevices
// between them. Plus the wear of a well-used board: old pin holes, coffee
// rings, faint water marks and sun-faded patches where prints used to hang.
// Rendered in tiles that scroll with the prints: uOffset is the tile's
// position on the wall, so the pattern is continuous across tiles.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1  tile size in px
uniform float uScale;   // 2    texture px per logical px
uniform float uSeed;    // 3
uniform float uOffset;  // 4    tile's top edge on the wall, in px

out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 4; i++) {
    v += amp * valueNoise(p);
    p *= 2.03;
    amp *= 0.5;
  }
  return v;
}

// Weighted Voronoi over granules of about one unit: x = distance to the
// nearest granule's edge-ish (F1 minus its weight), y = gap to the
// second-nearest (0 on a crevice), zw = offset from the granule's centre.
// The granule id comes back through [id].
vec4 granules(vec2 p, float seed, out vec2 id) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float d1 = 9.0, d2 = 9.0;
  vec2 rel = vec2(0.0);
  id = i;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 o = vec2(float(x), float(y));
      vec2 c = i + o;
      vec2 h = 0.12 + 0.76 * hash22(c + seed);
      float w = 0.28 * hash12(c + seed + 31.7); // bigger and smaller grains
      vec2 r = o + h - f;
      float d = length(r) - w;
      if (d < d1) {
        d2 = d1;
        d1 = d;
        rel = r;
        id = c;
      } else if (d < d2) {
        d2 = d;
      }
    }
  }
  return vec4(d1, d2 - d1, -rel);
}

// Old pin holes: most cells empty, some with one hole, a few with a cluster
// (a print was pinned, moved, pinned again).
float pinHoles(vec2 p) {
  const float cellSize = 140.0;
  vec2 cell = floor(p / cellSize);
  float h = hash12(cell + uSeed * 11.0);
  if (h < 0.82) return 0.0;
  float d = 1e3;
  int n = h > 0.95 ? 3 : 1;
  for (int k = 0; k < 3; k++) {
    if (k >= n) break;
    vec2 c = (cell + 0.1 + 0.8 * vec2(hash12(cell + float(k) * 7.1), hash12(cell + float(k) * 3.7 + 9.0))) * cellSize;
    d = min(d, length(p - c));
  }
  return 1.0 - smoothstep(0.9, 1.7, d);
}

// A coffee ring: where a mug was put down. Darker, browner rim (the coffee
// dries at the edge) with a faintly tinted inside; sometimes a second ring
// where it was put down again, and a drip or two beside it.
vec2 coffee(vec2 p) {
  const float cellSize = 520.0;
  vec2 cell = floor(p / cellSize);
  float h = hash12(cell + uSeed * 13.0);
  if (h < 0.55) return vec2(0.0);
  float rim = 0.0, inside = 0.0;
  int n = h > 0.85 ? 2 : 1;
  for (int k = 0; k < 2; k++) {
    if (k >= n) break;
    vec2 c = (cell + 0.25 + 0.5 * hash22(cell + uSeed + float(k) * 5.3)) * cellSize;
    float R = 27.0 + 12.0 * hash12(cell + float(k) * 2.9);
    vec2 q = p - c;
    float a = atan(q.y, q.x);
    // A wobbly, not-quite-round ring that fades out along part of it.
    float wob = (fbm(vec2(a * 2.0, float(k) * 7.0) + cell) - 0.5) * 3.0;
    float r = length(q) + wob;
    float strength = 0.45 + 0.55 * smoothstep(0.25, 0.6, fbm(vec2(a * 1.3 + float(k), 3.0) + cell * 1.7));
    float dr = r - R;
    rim = max(rim, strength * (exp(-dr * dr / 1.6) + 0.45 * exp(-(dr + 2.2) * (dr + 2.2) / 5.0)));
    inside = max(inside, (1.0 - smoothstep(R - 3.0, R, r)) * (0.35 + 0.5 * fbm(q * 0.06 + cell)));
    // A drip that ran down from the rim.
    vec2 drip = c + vec2(cos(h * 40.0 + float(k)), sin(h * 40.0 + float(k))) * (R + 9.0 + 6.0 * h);
    float dd = length(p - drip);
    inside = max(inside, 1.0 - smoothstep(2.0, 3.4, dd));
    rim = max(rim, 0.6 * exp(-(dd - 3.0) * (dd - 3.0) / 0.8));
  }
  return vec2(rim, inside);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 world = frag + vec2(0.0, uOffset);
  vec2 p = world / max(uScale, 1.0); // logical px on the wall

  // Granules about 3.4 px across, their outlines warped so they come out
  // irregular rather than polygonal.
  const float grain = 3.4;
  vec2 warp = vec2(fbm(p * 0.22 + uSeed), fbm(p * 0.22 + uSeed + 17.0)) - 0.5;
  vec2 gid;
  vec4 g = granules(p / grain + warp * 0.55, uSeed, gid);

  // A sprinkling of bigger chunks pressed in among the small ones.
  vec2 bid;
  vec4 b = granules(p / (grain * 2.4) + warp * 0.3, uSeed + 50.0, bid);
  bool big = hash12(bid + uSeed * 3.0) > 0.86 && b.x < 0.1;
  if (big) {
    g = b;
    gid = bid + 1000.0;
  }

  float r1 = hash12(gid + uSeed * 1.7);
  float r2 = hash12(gid + uSeed * 2.3 + 8.0);

  // Each granule's own tone: mostly tan to orange, some pale, a few dark.
  vec3 pale = vec3(0.88, 0.72, 0.52);
  vec3 tan = vec3(0.80, 0.59, 0.37);
  vec3 orange = vec3(0.72, 0.46, 0.25);
  vec3 dark = vec3(0.50, 0.31, 0.16);
  vec3 c = r1 < 0.5 ? mix(pale, tan, r1 * 2.0) : mix(tan, orange, (r1 - 0.5) * 2.0);
  if (r2 > 0.93) c = mix(c, dark, 0.7);
  else if (r2 < 0.05) c = mix(c, vec3(0.93, 0.80, 0.62), 0.6);

  // A broad, gentle drift in colour across the board.
  float drift = fbm(p * 0.007 + uSeed * 0.5);
  c *= 0.92 + 0.16 * drift;
  c = mix(c, c * vec3(1.03, 0.98, 0.93), smoothstep(0.4, 0.7, fbm(p * 0.012 + uSeed + 9.0)));

  // Domed granules lit from the top left, darker where they dip into the
  // crevices; the cut surface is porous.
  float radius = big ? 0.55 : 0.45;
  vec2 v = g.zw / radius;
  float dome = clamp(dot(v, normalize(vec2(-1.0, -1.0))), -1.0, 1.0);
  c *= 1.0 + 0.10 * dome;
  float edge = smoothstep(0.0, 0.22, g.y);
  c *= mix(0.72, 1.0, edge);
  float pores = valueNoise(p * 1.7 + gid * 3.1);
  c *= 0.94 + 0.08 * pores;
  c = mix(c, c * 0.7, step(0.9, hash12(floor(p * 1.3) + gid)) * 0.6);

  // The crevices between granules: deep brown, darkest where widest.
  vec3 gap = vec3(0.30, 0.18, 0.09) * (0.8 + 0.4 * valueNoise(p * 0.9 + 3.0));
  // Some granules sit tight against each other, others leave a wide gap.
  float open = smoothstep(0.25, 0.75, valueNoise(p * 0.55 + uSeed + 4.0));
  float crevice = (1.0 - smoothstep(0.0, 0.02 + 0.13 * open, g.y)) * (0.35 + 0.65 * open);
  float hollow = smoothstep(0.55, 0.78, valueNoise(p * 0.45 + uSeed + 21.0)) * smoothstep(0.6, 0.2, g.y);
  c = mix(c, gap, max(crevice * 0.9, hollow * 0.45));

  // Sun-faded rectangles where prints hung for years.
  const float hung = 480.0;
  vec2 cell = floor(p / hung);
  if (hash12(cell + uSeed * 5.0) > 0.75) {
    vec2 o = (cell + 0.5) * hung + (hash22(cell + 1.3) - 0.5) * 150.0;
    vec2 hs = vec2(100.0, 135.0) * (0.8 + 0.4 * hash12(cell + 4.2));
    vec2 q = abs(p - o) - hs;
    float inside = 1.0 - smoothstep(-10.0, 8.0, max(q.x, q.y));
    c = mix(c, c * vec3(1.07, 1.06, 1.04), inside * 0.8);
  }

  // Faint water marks: soft blotches with a slightly darker tide line.
  float wet = fbm(p * 0.0022 + uSeed * 2.0 + 40.0);
  float blotch = smoothstep(0.66, 0.70, wet);
  float tide = smoothstep(0.64, 0.665, wet) - smoothstep(0.665, 0.69, wet);
  c *= 1.0 - 0.06 * blotch - 0.08 * tide;

  // Coffee.
  vec2 cf = coffee(p);
  vec3 coffeeTint = vec3(0.62, 0.42, 0.26);
  c = mix(c, c * coffeeTint * 1.25, clamp(cf.y * 0.35, 0.0, 1.0));
  c = mix(c, c * coffeeTint, clamp(cf.x * 0.55, 0.0, 1.0));

  c = mix(c, vec3(0.13, 0.08, 0.04), pinHoles(p) * 0.9);

  // Soft shading at the left and right frame edges (the wall continues up
  // and down as you scroll).
  float ux = frag.x / uSize.x;
  float side = smoothstep(0.0, 0.05, min(ux, 1.0 - ux));
  c *= mix(0.82, 1.0, side);

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
