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
uniform float uGate;         // 21    Super 8: full-gate film strip (CineStrip)
uniform float uFps;          // 22    cadence of grain / weave / dust
uniform float uGrainHi;      // 23    extra grain toward white (B&W negatives)
uniform vec4 uCanvas;        // 24-27 Super 8: film-strip canvas in the box (normalised)
uniform float uTurns;        // 28    Super 8: quarter turns from box to the viewer's upright frame

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

// ---- Super 8 film strip (mirrors lib/core/processing/cine_strip.dart) ----
const float kLeft = 0.16;
const float kRight = 0.035;
const float kSliver = 0.05;
const float kGap = 0.014;
const float kPicX = kLeft;
const float kPicW = 1.0 - kLeft - kRight;
const float kPicY = kSliver + kGap;
const float kPicH = 1.0 - 2.0 * (kSliver + kGap);
const float kHoleW = 0.115;
const float kHoleH = 0.25;
const float kHoleX = kLeft - kHoleW - 0.008;
const float kHoleY = 0.5 - kHoleH / 2.0;
const float kHoleR = 0.035;
const float kFrameR = 0.02;

// Box uv -> viewer's upright uv (undo RotatedBox clockwise quarter turns).
vec2 toUpright(vec2 b, float q) {
  vec2 u = b;
  for (int i = 0; i < 3; i++) {
    if (float(i) >= q) break;
    u = vec2(u.y, 1.0 - u.x);
  }
  return u;
}

vec2 toBox(vec2 u, float q) {
  vec2 b = u;
  for (int i = 0; i < 3; i++) {
    if (float(i) >= q) break;
    b = vec2(1.0 - b.y, b.x);
  }
  return b;
}

float boxSdf(vec2 p, vec2 c, vec2 h, float r) {
  vec2 q = abs(p - c) - h + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Strip colour (rgb) and coverage (a) at upright canvas uv [u].
vec4 stripColor(vec2 u, float aspect, float px) {
  vec2 p = vec2(u.x * aspect, u.y);
  float pitch = kPicH + kGap;
  float k = clamp(floor((p.y - kPicY - kPicH / 2.0) / pitch + 0.5), -1.0, 1.0);
  float frame = boxSdf(p, vec2((kPicX + kPicW / 2.0) * aspect, kPicY + kPicH / 2.0 + k * pitch),
      vec2(kPicW / 2.0 * aspect, kPicH / 2.0), kFrameR);
  float cov = smoothstep(-px, px, frame);
  float hole = boxSdf(p, vec2((kHoleX + kHoleW / 2.0) * aspect, kHoleY + kHoleH / 2.0),
      vec2(kHoleW / 2.0 * aspect, kHoleH / 2.0), kHoleR);
  vec3 col = vec3(18.0, 12.0, 10.0) / 255.0;
  float e = (p.x - 0.012 * aspect) / 0.0016;
  col = mix(col, vec3(62.0, 74.0, 104.0) / 255.0, 0.55 * exp(-e * e));
  if (hole > 0.0) {
    float t = hole / 0.0035;
    float glow = min(1.0, exp(-t * t) + 0.35 * exp(-hole / 0.012));
    col = mix(col, vec3(255.0, 192.0, 125.0) / 255.0, glow);
  }
  col *= 1.0 - smoothstep(px, -px, hole);
  return vec4(col, cov);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float frame = floor(uTime * uFps);
  vec2 frameSize = uSize * uCrop.zw;

  // Super 8 gate weave: the whole picture hops a little every frame.
  vec2 weave = (vec2(hash11(frame + 1.7), hash11(frame + 9.3)) - 0.5) * vec2(0.0035, 0.0055) * uWeave * frameSize;
  vec2 src = frag + weave;
  vec2 cropUv = (src / uSize - uCrop.xy) / max(uCrop.zw, vec2(1e-4));

  // Super 8 full-gate strip: lay the canvas out in the viewer's upright
  // frame, show the frame (and slivers of its neighbours) through it, and
  // map each frame point back to the captured crop.
  vec4 strip = vec4(0.0);
  if (uGate > 0.5) {
    vec2 cb = (frag / uSize - uCanvas.xy) / max(uCanvas.zw, vec2(1e-4));
    if (cb.x < 0.0 || cb.y < 0.0 || cb.x > 1.0 || cb.y > 1.0) {
      fragColor = vec4(0.0, 0.0, 0.0, 1.0);
      return;
    }
    bool odd = mod(uTurns, 2.0) > 0.5;
    vec2 canvasPx = uCanvas.zw * uSize;
    float aspect = odd ? canvasPx.y / canvasPx.x : canvasPx.x / canvasPx.y;
    float px = 1.0 / (odd ? canvasPx.x : canvasPx.y);
    vec2 cu = toUpright(cb, uTurns);
    // Weave moves the whole film in the gate.
    cu += (vec2(hash11(frame + 1.7), hash11(frame + 9.3)) - 0.5) * vec2(0.0035, 0.0055) * uWeave;
    strip = stripColor(cu, aspect, px);
    float pitch = kPicH + kGap;
    float k = clamp(floor((cu.y - kPicY - kPicH / 2.0) / pitch + 0.5), -1.0, 1.0);
    vec2 pv = vec2((cu.x - kPicX) / kPicW, (cu.y - kPicY - k * pitch) / kPicH);
    cropUv = toBox(clamp(pv, 0.0, 1.0), uTurns);
    src = (uCrop.xy + cropUv * uCrop.zw) * uSize;
  }

  float gain = uExposure * spatialExposure(cropUv);
  // Flicker: a jump every frame plus a slow pulse (uneven shutter and lamp).
  gain *= 1.0 + (hash11(frame * 1.37 + 4.1) - 0.5) * 0.16 * uFlicker
      + 0.05 * uFlicker * sin(6.1 * uTime) * sin(1.7 * uTime);

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
    c += n * uGrainAmount * gain * (0.22 + 3.1 * l * (1.0 - l) + uGrainHi * l * l);
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

  // Super 8: the film strip over the frames.
  if (uGate > 0.5) c = mix(c, strip.rgb, strip.a);

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
