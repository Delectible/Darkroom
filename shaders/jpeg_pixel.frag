#version 460 core
// Y2K flip-phone camera: tiny sensor resolution (fat pixels), crushed colour
// depth and JPEG macro-block artefacts (8x8 blocks, 4:2:0 chroma smear,
// mosquito ringing on edges).
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
// --- JPEG-specific ---
uniform float uLowRes;       // 29  fat pixels across the visible frame width
uniform float uPosterize;    // 30  levels per channel
uniform float uArtifact;     // 31  0..1 block/ringing strength

uniform sampler2D uTexture;

out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 toUv(vec2 frag) {
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

vec3 rgb2ycc(vec3 c) {
  float y = dot(c, vec3(0.299, 0.587, 0.114));
  return vec3(y, (c.b - y) * 0.564, (c.r - y) * 0.713);
}

vec3 ycc2rgb(vec3 y) {
  return vec3(y.x + 1.403 * y.z, y.x - 0.344 * y.y - 0.714 * y.z, y.x + 1.773 * y.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // Fat-pixel grid anchored to the visible crop so the export (which really is
  // rendered at uLowRes and upscaled with nearest-neighbour) lines up.
  float px = max(1.0, (uSize.x * uCrop.z) / max(uLowRes, 1.0));
  vec2 origin = uCrop.xy * uSize;
  vec2 cell = floor((frag - origin) / px);
  vec2 cellCentre = origin + (cell + 0.5) * px;

  vec3 lumaSrc = texture(uTexture, toUv(cellCentre)).rgb;

  // 4:2:0 chroma: one chroma sample per 2x2 fat pixels.
  vec2 chromaCell = floor(cell / 2.0);
  vec2 chromaCentre = origin + (chromaCell * 2.0 + 1.0) * px;
  vec3 chromaSrc = texture(uTexture, toUv(chromaCentre)).rgb;

  vec3 ycc = vec3(rgb2ycc(lumaSrc).x, rgb2ycc(chromaSrc).yz);

  // 8x8 macro-block: pull luma towards the block mean (coarse DC quantisation)
  // and add a faint ringing pattern proportional to local contrast.
  vec2 block = floor(cell / 8.0);
  vec2 blockCentre = origin + (block * 8.0 + 4.0) * px;
  float blockY = rgb2ycc(texture(uTexture, toUv(blockCentre)).rgb).x;
  float contrast = abs(ycc.x - blockY);
  vec2 inBlock = mod(cell, 8.0);
  float ring = cos(inBlock.x * 1.5708 * 3.0) * cos(inBlock.y * 1.5708 * 3.0);
  float q = uArtifact * 0.35;
  ycc.x = mix(ycc.x, blockY, q * (1.0 - smoothstep(0.0, 0.25, contrast)));
  ycc.x += ring * contrast * uArtifact * 0.18;
  // Block-edge seams.
  float seam = step(7.0, inBlock.x) + step(7.0, inBlock.y);
  ycc.x -= seam * contrast * uArtifact * 0.08;

  vec2 cropUv = (cellCentre / uSize - uCrop.xy) / max(uCrop.zw, vec2(1e-4));
  vec3 c = grade(clamp(ycc2rgb(ycc), 0.0, 1.0), cropUv);

  // Cheap sensor noise per fat pixel, refreshed at 15 fps like the real thing.
  float t = floor(uTime * 15.0);
  float n = hash12(floor(cell / max(uGrainSize, 1.0)) + vec2(t * 3.3, t * 1.9)) * 2.0 - 1.0;
  c += n * uGrainAmount;

  // Reduced colour depth (the banding of a 4096-colour screen).
  float levels = max(uPosterize, 2.0);
  c = floor(c * levels + 0.5) / levels;

  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
