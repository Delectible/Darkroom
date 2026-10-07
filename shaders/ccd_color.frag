#version 460 core
// 2003-era CCD point-and-shoot: cool colour matrix, hard highlight clipping
// with a bit of blown-out bloom, in-camera over-sharpening halos and chroma
// noise that lives in the shadows.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;          // 0-1
uniform float uTime;         // 2
uniform vec3 uRow0;          // 3-5
uniform vec3 uRow1;          // 6-8
uniform vec3 uRow2;          // 9-11
uniform vec3 uOffset;        // 12-14
uniform float uExposure;     // 15  > 1 pushes highlights past the clip point
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
// --- CCD-specific ---
uniform float uSharpen;      // 29
uniform float uChromaNoise;  // 30
uniform float uBloom;        // 31
uniform float uSmear;        // 32  vertical CCD smear from bright lights

uniform sampler2D uTexture;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 sampleUv(vec2 frag) {
  vec2 uv = frag / uSize;
  // No GLES y-flip: since Flutter 3.45 the engine hands the filter input
  // the same way up on every backend (a manual flip turns it upside down).
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = sampleUv(frag);
  vec2 cropUv = (frag / uSize - uCrop.xy) / max(uCrop.zw, vec2(1e-4));
  float scale = max(1.0, (uSize.x * uCrop.z) / 1080.0);
  vec2 texel = scale / uSize;

  // Unsharp mask (4-tap cross) => the bright/dark halos of in-camera sharpening.
  vec3 c0 = texture(uTexture, uv).rgb;
  vec3 n4 = texture(uTexture, uv + vec2(texel.x, 0.0)).rgb +
            texture(uTexture, uv - vec2(texel.x, 0.0)).rgb +
            texture(uTexture, uv + vec2(0.0, texel.y)).rgb +
            texture(uTexture, uv - vec2(0.0, texel.y)).rgb;
  vec3 sharp = c0 + (c0 - n4 * 0.25) * uSharpen * 2.0;

  // Wide, cheap blur for highlight bloom (blooming CCD wells).
  vec2 bt = texel * 6.0;
  vec3 wide = (texture(uTexture, uv + vec2(bt.x, bt.y)).rgb +
               texture(uTexture, uv + vec2(-bt.x, bt.y)).rgb +
               texture(uTexture, uv + vec2(bt.x, -bt.y)).rgb +
               texture(uTexture, uv + vec2(-bt.x, -bt.y)).rgb) * 0.25;
  vec3 bloom = max(grade(wide, cropUv) - 0.8, 0.0) * 5.0 * uBloom;

  vec3 c = grade(max(sharp, 0.0), cropUv);
  c = 1.0 - (1.0 - c) * (1.0 - bloom * 0.5); // screen blend

  // CCD smear: charge from an over-full well leaks along the whole column
  // during readout, so a bright light draws a vertical stripe.
  if (uSmear > 0.0) {
    float sm = 0.0;
    for (int i = 0; i < 12; i++) {
      float fy = (float(i) + 0.5) / 12.0;
      vec2 p = vec2(frag.x, (uCrop.y + uCrop.w * fy) * uSize.y);
      vec3 v = texture(uTexture, sampleUv(p)).rgb * uExposure;
      sm += max(0.0, dot(v, kLuma) - 0.92);
    }
    c += vec3(1.0, 0.94, 1.06) * (sm / 12.0) * 7.0 * uSmear;
  }

  // Chroma noise concentrated in the shadows, refreshed at sensor frame rate.
  float t = floor(uTime * 30.0);
  vec2 cell = floor(frag / (scale * max(uGrainSize, 1.0))) + vec2(t * 3.1, t * 5.7);
  vec3 nc = vec3(hash12(cell), hash12(cell + 7.7), hash12(cell + 13.3)) * 2.0 - 1.0;
  float l = dot(c, kLuma);
  c += nc * uChromaNoise * (1.0 - l) * (1.0 - l);
  float ln = hash12(cell + 31.0) * 2.0 - 1.0;
  c += ln * uGrainAmount * (0.35 + 2.6 * l * (1.0 - l));

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
