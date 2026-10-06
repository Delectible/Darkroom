#version 460 core
// Procedural cork: low-frequency colour blotches, dark granules and a few
// pale flecks, plus the wear of a well-used board (old pin holes, a coffee
// stain, sun-faded patches where prints used to hang). Rendered in tiles that
// scroll with the prints: uOffset is the tile's position on the wall, so the
// pattern is continuous across tiles.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1  tile size in px
uniform float uScale;   // 2    granule size in logical px * devicePixelRatio
uniform float uSeed;    // 3
uniform float uOffset;  // 4    tile's top edge on the wall, in px

out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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

// Distance to the nearest random feature point => granule cells.
float cells(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float d = 1.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 o = vec2(float(x), float(y));
      vec2 h = vec2(hash12(i + o + uSeed), hash12(i + o + uSeed + 17.0));
      d = min(d, length(o + h - f));
    }
  }
  return d;
}

// Old pin holes: most cells empty, some with one hole, a few with a cluster
// (a print was pinned, moved, pinned again).
float pinHoles(vec2 p) {
  vec2 cell = floor(p / 46.0);
  float h = hash12(cell + uSeed * 11.0);
  if (h < 0.84) return 0.0;
  float d = 1e3;
  int n = h > 0.96 ? 3 : 1;
  for (int k = 0; k < 3; k++) {
    if (k >= n) break;
    vec2 c = (cell + vec2(hash12(cell + float(k) * 7.1), hash12(cell + float(k) * 3.7 + 9.0))) * 46.0;
    d = min(d, length(p - c));
  }
  return 1.0 - smoothstep(0.7, 1.4, d);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 world = frag + vec2(0.0, uOffset);
  vec2 p = world / max(uScale, 1.0);

  vec3 base = vec3(0.71, 0.53, 0.34);
  vec3 dark = vec3(0.42, 0.28, 0.16);
  vec3 light = vec3(0.86, 0.71, 0.50);

  float blot = fbm(p * 0.035 + uSeed);
  vec3 c = mix(base * 0.9, base * 1.08, blot);

  float g = cells(p * 0.55);
  float granule = 1.0 - smoothstep(0.08, 0.32, g);
  c = mix(c, dark, granule * 0.55);

  float pits = step(0.93, hash12(floor(p * 0.9) + uSeed * 3.0));
  c = mix(c, dark * 0.8, pits * 0.5);

  float fleck = step(0.975, hash12(floor(p * 0.7) + uSeed * 7.0 + 5.0));
  c = mix(c, light, fleck * 0.6);

  // Sun-faded rectangles where prints hung for years (paler around them).
  vec2 big = floor(p / 160.0);
  if (hash12(big + uSeed * 5.0) > 0.78) {
    vec2 o = (big + 0.5) * 160.0 + (vec2(hash12(big + 1.3), hash12(big + 2.7)) - 0.5) * 50.0;
    vec2 hs = vec2(34.0, 46.0) * (0.8 + 0.4 * hash12(big + 4.2));
    vec2 q = abs(p - o) - hs;
    float inside = 1.0 - smoothstep(-4.0, 3.0, max(q.x, q.y));
    c = mix(c, c * 1.07, inside * 0.8);
  }

  // A coffee ring or two: a darker patch with a darker rim.
  float stain = fbm(p * 0.006 + uSeed * 2.0 + 40.0);
  float blotchy = smoothstep(0.66, 0.70, stain);
  float rim = smoothstep(0.64, 0.665, stain) - smoothstep(0.665, 0.69, stain);
  c *= 1.0 - 0.09 * blotchy - 0.10 * rim;

  c = mix(c, dark * 0.35, pinHoles(p) * 0.9);

  // Soft shading at the left and right frame edges (the wall continues up
  // and down as you scroll).
  float ux = frag.x / uSize.x;
  float edge = smoothstep(0.0, 0.05, min(ux, 1.0 - ux));
  c *= mix(0.80, 1.0, edge);

  fragColor = vec4(c, 1.0);
}
