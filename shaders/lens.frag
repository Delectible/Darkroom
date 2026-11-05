#version 460 core
// The lens on the film camera, over the live viewfinder (ImageFilter.shader;
// the photo gets the same in Dart, lens_renderer.dart). One lens at a time
// by uLens: 1 wide adapter, 2 fish-eye, 3 plastic, 4 soft focus, 5 swirl,
// 6 tilt-shift, 7 star filter, 8 anamorphic, 9 pinhole (0: none, the plain
// picture). No y-flip: see the contract test.
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;          // 0-1 (the engine's: the picture in pixels)
uniform float uLens;         // 2
uniform sampler2D uTexture;

out vec4 fragColor;

vec3 tex(vec2 uv) { return texture(uTexture, clamp(uv, 0.0, 1.0)).rgb; }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// A small disc of taps round uv, radius rad (uv units, x scaled to stay round).
vec3 disc(vec2 uv, float rad) {
  vec2 k = vec2(uSize.y / uSize.x, 1.0) * rad;
  vec3 s = tex(uv);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398;
    s += tex(uv + vec2(cos(a), sin(a)) * k);
    s += tex(uv + vec2(cos(a + 0.39), sin(a + 0.39)) * k * 0.5);
  }
  return s / 17.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 d = uv - 0.5;
  float aspect = uSize.x / uSize.y;
  // 0 at the centre, 1 at the corners
  float r = length(vec2(d.x * aspect, d.y)) / length(vec2(0.5 * aspect, 0.5));
  int lens = int(uLens + 0.5);
  vec3 c;

  if (lens == 1) {
    // wide: a little more in, bent slightly, corners soft and darker
    vec2 src = 0.5 + d * 0.93 * (1.0 + 0.10 * r * r);
    float m = clamp((r - 0.55) / 0.45, 0.0, 1.0);
    c = mix(tex(src), disc(src, 0.004), m * 0.6) * (1.0 - 0.35 * r * r);
  } else if (lens == 2) {
    // fish-eye: a circle on black
    float mn = min(uSize.x, uSize.y);
    vec2 dp = d * uSize;
    float rad = 0.49 * mn;
    float rm = length(dp) / rad;
    float th = min(rm * 1.25, 1.45);
    float k = (tan(th) / tan(1.25)) / max(rm, 1e-4);
    float diag = 0.5 * length(uSize);
    vec2 src = 0.5 + (dp / rad) * k * diag * 0.72 / uSize;
    float edge = clamp((1.0 - rm) * rad / 2.0, 0.0, 1.0);
    c = tex(src) * (1.0 - 0.25 * rm * rm) * edge;
  } else if (lens == 3) {
    // plastic: soft dark edges, colour fringes, faded
    float f = 1.0 + 0.06 * r * r;
    vec2 base = 0.5 + d * f;
    vec3 sharp = vec3(tex(0.5 + d * f * 1.006).r, tex(base).g, tex(0.5 + d * f * 0.994).b);
    c = mix(sharp, disc(base, 0.008), clamp(r * r * 1.6, 0.0, 1.0));
    c = (c * 0.92 + 0.04) * vec3(1.04, 1.0, 0.94);
    c *= 1.0 - 0.75 * pow(r, 2.2);
  } else if (lens == 4) {
    // soft focus: highlights bloom, detail stays
    vec3 b = disc(uv, 0.018);
    float m = pow(clamp((luma(tex(uv)) - 0.45) / 0.5, 0.0, 1.0), 1.5);
    vec3 s = tex(uv);
    c = (1.0 - (1.0 - s) * (1.0 - b * (0.55 * m + 0.12))) * 0.97;
  } else if (lens == 5) {
    // swirl: the background turns round the sharp middle
    vec2 p = vec2(d.x * aspect, d.y);
    float ang = atan(p.y, p.x), rr = length(p);
    float sw = 0.24 * pow(clamp(r - 0.25, 0.0, 1.0), 1.4);
    vec3 s = vec3(0.0);
    for (int i = 0; i < 9; i++) {
      float t = (float(i) / 8.0 - 0.5) * sw;
      vec2 q = vec2(cos(ang + t), sin(ang + t)) * rr;
      s += tex(0.5 + vec2(q.x / aspect, q.y));
    }
    c = s / 9.0 * (1.0 - 0.4 * r * r);
  } else if (lens == 6) {
    // tilt-shift: a sharp band, blur above and below, a little extra colour
    float m = clamp((abs(uv.y - 0.52) - 0.13) / 0.28, 0.0, 1.0);
    c = mix(tex(uv), disc(uv, 0.003 + 0.012 * m), m);
    float l = luma(c);
    c = (vec3(l) + (c - l) * 1.35 - 0.5) * 1.12 + 0.5;
  } else if (lens == 7) {
    // star filter: points of light grow six-pointed stars
    c = tex(uv);
    vec3 star = vec3(0.0);
    for (int dir = 0; dir < 3; dir++) {
      float a = 0.5236 + float(dir) * 1.0472;
      vec2 step = vec2(cos(a) / aspect, sin(a)) * 0.006;
      for (int i = 1; i <= 10; i++) {
        float w = exp(-float(i) / 3.5) * 0.22;
        star += max(tex(uv + step * float(i)) - 0.9, 0.0) * 10.0 * w;
        star += max(tex(uv - step * float(i)) - 0.9, 0.0) * 10.0 * w;
      }
    }
    c = 1.0 - (1.0 - c) * (1.0 - clamp(star, 0.0, 1.0));
  } else if (lens == 8) {
    // anamorphic: long blue streaks off bright lights, an oval vignette
    c = tex(uv);
    float streak = 0.0;
    for (int i = 1; i <= 16; i++) {
      float w = exp(-float(i) / 6.0) * 0.16;
      float o = float(i) * 0.016;
      streak += max(luma(tex(uv + vec2(o, 0.0))) - 0.85, 0.0) / 0.15 * w;
      streak += max(luma(tex(uv - vec2(o, 0.0))) - 0.85, 0.0) / 0.15 * w;
    }
    c = 1.0 - (1.0 - c) * (1.0 - clamp(streak, 0.0, 1.0) * vec3(0.35, 0.6, 1.0));
    float ov = length(vec2(d.x * 2.0, d.y * 3.0));
    c *= 1.0 - 0.3 * pow(clamp(ov - 0.5, 0.0, 1.0), 1.5);
  } else if (lens == 9) {
    // pinhole: soft all over, deep vignette
    c = (disc(uv, 0.006) - 0.5) * 0.9 + 0.5;
    c *= 1.0 - 0.95 * pow(r, 2.6);
  } else {
    c = tex(uv);
  }
  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
