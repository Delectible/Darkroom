#version 460 core
// Film stock simulation for the live viewfinder.
//
//   camera sRGB -> linear -> exposure / vignette / flash -> shaper
//   -> 3D LUT (the stock's characteristic curves + colour, built by
//      lib/core/processing/film/film_profile.dart) -> halation -> grain
//
// The still renderer (film_renderer.dart) runs the same steps on the CPU and
// FFmpeg uses the same LUT for Super 8 clips, so preview == result.
//
// Uniform layout (float indices) is written by FilmUniforms in
// lib/core/shaders/shader_library.dart; keep the declaration order.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;          // 0-1   engine (ImageFilter.shader) / caller
uniform float uTime;         // 2     seconds
uniform vec4 uCrop;          // 3-6   visible (unmasked) rect, normalised
uniform float uExposure;     // 7     linear gain
uniform float uVignette;     // 8
uniform float uFlash;        // 9     0..1 (already scaled by the stock)
uniform float uLutSize;      // 10
uniform float uGrainAmount;  // 11    sRGB std dev incl. strength setting
uniform float uGrainChroma;  // 12
uniform float uGrainRes;     // 13    grain texels per frame height
uniform float uHalation;     // 14
uniform vec3 uHalColor;      // 15-17
uniform float uWeave;        // 18    Super 8: gate weave
uniform float uFlicker;      // 19    Super 8: exposure flicker
uniform float uDust;         // 20    Super 8: dust specks
uniform float uGate;         // 21    Super 8: rounded projector gate
uniform float uFps;          // 22    cadence of grain / weave / dust

uniform sampler2D uTexture;  // camera (bound by the engine)
uniform sampler2D uLut;      // (size*size) x size strip, blue slices side by side
uniform sampler2D uGrain;    // 512x512 tileable grain, RGB = 3 layers

out vec4 fragColor;

const float kShaperK = 31.0;
const float kShaperNorm = 4.8283137; // ln(1 + 31 * 4)
const float kGrainSize = 512.0;
const float kGrainDecode = 7.0833333; // 255 / 36
const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

float hash11(float p) {
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 srgbToLinear(vec3 c) {
  vec3 lo = c / 12.92;
  vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
  return mix(lo, hi, step(vec3(0.04045), c));
}

vec3 shaper(vec3 x) {
  return clamp(log(1.0 + kShaperK * max(x, 0.0)) / kShaperNorm, 0.0, 1.0);
}

vec3 lut(vec3 s) {
  float n = uLutSize;
  float b = s.b * (n - 1.0);
  float b0 = floor(b);
  float b1 = min(b0 + 1.0, n - 1.0);
  vec2 rg = s.rg * (n - 1.0) + 0.5;
  float w = n * n;
  vec3 c0 = texture(uLut, vec2((b0 * n + rg.x) / w, rg.y / n)).rgb;
  vec3 c1 = texture(uLut, vec2((b1 * n + rg.x) / w, rg.y / n)).rgb;
  return mix(c0, c1, b - b0);
}

vec2 inputUv(vec2 frag) {
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

// Normalised radius used by vignette + flash (matches FilmSpatial.exposure).
float spatialExposure(vec2 cropUv) {
  float r = length((cropUv - 0.5) * 2.0) * 0.70710678;
  float v = 1.0 - uVignette * smoothstep(0.30, 1.0, r);
  float hot = 1.0 - smoothstep(0.0, 0.85, r);
  return v * (1.0 + uFlash * (1.1 * hot - 0.35 * (1.0 - hot)));
}

float highlight(vec2 frag, float gain) {
  vec3 c = srgbToLinear(texture(uTexture, inputUv(frag)).rgb) * gain;
  return max(0.0, dot(c, kLuma) - 0.82) * 2.2;
}

float roundRectSdf(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float frame = floor(uTime * uFps);
  vec2 frameSize = uSize * uCrop.zw;

  // Super 8 gate weave: the whole picture hops a little every frame.
  vec2 weave = (vec2(hash11(frame + 1.7), hash11(frame + 9.3)) - 0.5) * vec2(0.0035, 0.0055) * uWeave * frameSize;
  vec2 src = frag + weave;
  vec2 cropUv = (src / uSize - uCrop.xy) / max(uCrop.zw, vec2(1e-4));

  float gain = uExposure * spatialExposure(cropUv);
  gain *= 1.0 + (hash11(frame * 1.37 + 4.1) - 0.5) * 0.11 * uFlicker;

  vec3 lin = srgbToLinear(texture(uTexture, inputUv(src)).rgb) * gain;
  lin *= vec3(1.0 - 0.03 * uFlash, 1.0, 1.0 + 0.06 * uFlash);
  vec3 c = lut(shaper(lin));

  // Halation: highlight energy gathered from a jittered ring of taps.
  if (uHalation > 0.0) {
    float radius = frameSize.y * 0.014;
    float a0 = hash12(frag) * 6.2831853;
    float e = 0.0;
    for (int i = 0; i < 6; i++) {
      float fi = float(i);
      float a = a0 + fi * 1.0471976;
      float rr = radius * (0.8 + 0.8 * mod(fi, 2.0));
      e += highlight(src + vec2(cos(a), sin(a)) * rr, gain);
    }
    float h = min(1.0, e / 6.0 * 2.5) * uHalation;
    c += uHalColor * h * (1.0 - c);
  }

  // Grain: tileable texture, sized relative to the frame, re-rolled per frame.
  // Grain finer than a pixel averages out: draw it at 1 px, fainter
  // (FilmSpatial.grainTexel).
  if (uGrainAmount > 0.0) {
    float t = frameSize.y / uGrainRes;
    float texel = max(t, 1.0);
    float gain = min(t, 1.0);
    vec2 offset = vec2(hash11(frame + 0.31), hash11(frame + 7.77)) * kGrainSize;
    vec2 guv = fract((src / texel + offset) / kGrainSize);
    vec3 g = (texture(uGrain, guv).rgb - 0.502) * kGrainDecode;
    vec3 n = mix(vec3(g.r), g, uGrainChroma);
    float l = dot(c, kLuma);
    c += n * uGrainAmount * gain * (0.22 + 3.1 * l * (1.0 - l));
  }

  // Super 8: dust specks (dark on reversal film), a few per frame.
  if (uDust > 0.0) {
    for (int k = 0; k < 3; k++) {
      float fk = float(k);
      float present = step(0.55, hash11(frame * 3.1 + fk * 11.0));
      vec2 pos = vec2(hash11(frame + fk * 5.3 + 0.5), hash11(frame * 0.7 + fk * 2.9 + 1.5));
      float size = (0.0025 + 0.006 * hash11(frame + fk * 17.0)) * uDust;
      vec2 d = (cropUv - pos) * vec2(frameSize.x / max(1.0, frameSize.y), 1.0);
      float m = 1.0 - smoothstep(size * 0.4, size, length(d));
      c *= 1.0 - 0.85 * m * present;
    }
  }

  // Super 8: soft rounded projector gate.
  if (uGate > 0.0) {
    vec2 p = (cropUv - 0.5) * vec2(frameSize.x / frameSize.y, 1.0);
    vec2 halfSize = vec2(0.5 * frameSize.x / frameSize.y, 0.5);
    float d = roundRectSdf(p, halfSize - 0.012, 0.06);
    c *= 1.0 - uGate * smoothstep(-0.03, 0.004, d);
  }

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
