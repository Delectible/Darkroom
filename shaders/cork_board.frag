#version 460 core
// Procedural cork: low-frequency colour blotches, dark granules and a few
// pale flecks. Painted once behind the Corkboard gallery (no texture asset).
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1
uniform float uScale;   // 2  granule size in logical px * devicePixelRatio
uniform float uSeed;    // 3

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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = frag / max(uScale, 1.0);

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

  // Soft edge shading so the board reads as recessed inside its frame.
  vec2 uv = frag / uSize;
  float edge = smoothstep(0.0, 0.06, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
  c *= mix(0.78, 1.0, edge);

  fragColor = vec4(c, 1.0);
}
