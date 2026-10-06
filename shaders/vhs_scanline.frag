#version 460 core
// 90s camcorder / VHS: ~240 visible scanlines, horizontal luma softness,
// chroma bleeding to the right, per-line time-base jitter and a rolling
// tracking-error band with white dropout streaks.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;          // 0-1
uniform float uTime;         // 2
uniform vec3 uRow0;          // 3-5
uniform vec3 uRow1;          // 6-8
uniform vec3 uRow2;          // 9-11
uniform vec3 uOffset;        // 12-14
uniform float uExposure;     // 15
uniform float uGamma;        // 16
uniform float uContrast;     // 17
uniform float uPivot;        // 18
uniform float uBlack;        // 19
uniform float uWhite;        // 20
uniform float uVignette;     // 21
uniform float uGrainAmount;  // 22
uniform float uGrainSize;    // 23
uniform float uFlash;        // 24
uniform vec4 uCrop;          // 25-28
// --- VHS-specific ---
uniform float uScanline;     // 29  darkening between lines (0..1)
uniform float uBleed;        // 30  chroma smear (0..1)
uniform float uJitter;       // 31  horizontal time-base error (0..1)
uniform float uTracking;     // 32  tracking band intensity (0..1)
uniform float uLines;        // 33  visible lines in the frame (e.g. 240)

uniform sampler2D uTexture;

out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 toUv(vec2 frag) {
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

vec3 tone(vec3 c) {
  c = pow(c, vec3(uGamma));
  vec3 lo = uPivot * pow(c / uPivot, vec3(uContrast));
  vec3 hi = 1.0 - (1.0 - uPivot) * pow((1.0 - c) / (1.0 - uPivot), vec3(uContrast));
  vec3 s = mix(lo, hi, step(vec3(uPivot), c));
  return uBlack + (uWhite - uBlack) * s;
}

vec3 grade(vec3 rgb, vec2 cropUv) {
  vec3 c = vec3(dot(uRow0, rgb), dot(uRow1, rgb), dot(uRow2, rgb)) + uOffset;
  float r = length((cropUv - 0.5) * 2.0) * 0.70710678;
  float vig = 1.0 - uVignette * smoothstep(0.35, 1.0, r);
  float hot = 1.0 - smoothstep(0.0, 0.85, r);
  float flash = 1.0 + uFlash * (0.9 * hot - 0.45 * (1.0 - hot));
  c *= uExposure * vig * flash;
  c *= vec3(1.0 - 0.03 * uFlash, 1.0, 1.0 + 0.06 * uFlash);
  return tone(clamp(c, 0.0, 1.0));
}

vec3 rgb2yiq(vec3 c) {
  return vec3(dot(c, vec3(0.299, 0.587, 0.114)),
              dot(c, vec3(0.596, -0.274, -0.322)),
              dot(c, vec3(0.211, -0.523, 0.312)));
}

vec3 yiq2rgb(vec3 c) {
  return vec3(c.x + 0.956 * c.y + 0.621 * c.z,
              c.x - 0.272 * c.y - 0.647 * c.z,
              c.x - 1.106 * c.y + 1.703 * c.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 cropUv = (frag / uSize - uCrop.xy) / max(uCrop.zw, vec2(1e-4));
  float frameW = uSize.x * uCrop.z;
  float px = max(1.0, frameW / 640.0); // one "VHS sample" in screen pixels

  float line = floor(cropUv.y * uLines);
  float field = floor(uTime * 29.97);

  // Time-base error: every line shifts a little, plus a slow wobble.
  float jitter = (hash12(vec2(line, field)) - 0.5) * 2.0 * px * uJitter;
  jitter += sin(cropUv.y * 9.0 + uTime * 1.3) * 0.6 * px * uJitter;

  // Rolling tracking band.
  float bandY = 1.0 - fract(uTime * 0.045);
  float band = 1.0 - smoothstep(0.0, 0.045, abs(cropUv.y - bandY));
  band *= uTracking;
  jitter += band * (hash12(vec2(line, field + 1.0)) * 18.0 - 6.0) * px;

  vec2 p = frag + vec2(jitter, 0.0);

  // Luma: soft horizontal 3-tap. Chroma: wide 5-tap smeared to the right.
  vec3 y0 = texture(uTexture, toUv(p)).rgb;
  vec3 yl = texture(uTexture, toUv(p - vec2(px, 0.0))).rgb;
  vec3 yr = texture(uTexture, toUv(p + vec2(px, 0.0))).rgb;
  float luma = rgb2yiq(y0 * 0.5 + (yl + yr) * 0.25).x;

  float cs = px * (1.0 + 4.0 * uBleed);
  vec2 cshift = vec2(-2.0 * px * uBleed, 0.0);
  vec2 iq = vec2(0.0);
  for (int i = -2; i <= 2; i++) {
    iq += rgb2yiq(texture(uTexture, toUv(p + cshift + vec2(float(i) * cs, 0.0))).rgb).yz;
  }
  iq /= 5.0;

  vec3 c = grade(clamp(yiq2rgb(vec3(luma, iq * (1.0 + 0.3 * uBleed))), 0.0, 1.0), cropUv);

  // Tape noise + dropout streaks inside the tracking band.
  float n = hash12(floor(p / (px * max(uGrainSize, 1.0))) + vec2(field * 1.7, field * 3.1)) * 2.0 - 1.0;
  c += n * uGrainAmount;
  float streak = step(0.985 - band * 0.06, hash12(vec2(floor(p.x / (px * 8.0)), line + field)));
  c = mix(c, vec3(0.92), streak * band);

  // Scanlines (cosine profile so the preview doesn't alias on any DPI).
  float sl = 0.5 + 0.5 * cos(cropUv.y * uLines * 6.2831853);
  c *= 1.0 - uScanline * sl;

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
