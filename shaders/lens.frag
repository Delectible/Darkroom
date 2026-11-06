#version 460 core
// The lens on the film camera, over the live viewfinder (ImageFilter.shader;
// the photo gets the same in Dart, lens_renderer.dart). One lens at a time
// by uLens: 1 wide adapter, 2 fish-eye, 3 plastic, 4 soft focus, 5 swirl,
// 6 tilt-shift, 7 pinhole, 8 mist, 9 anamorphic (0: none, the plain picture). uCrop is the
// frame that's seen (the photo) in the picture, so the lens sits on it.
// No y-flip: see the contract test.
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;          // 0-1 (the engine's: the picture in pixels)
uniform float uLens;         // 2
uniform vec4 uCrop;          // 3-6: left, top, width, height (0-1)
uniform sampler2D uTexture;

out vec4 fragColor;

// The fish-eye (the same in lens_renderer.dart): how much of the frame's
// short side the circle fills, how hard the picture bends to fill it (the
// widest angle it's taken to show, radians), the colour fringe at the rim,
// where the glass bevel starts and how far it jogs the picture back, and
// the rainbow's reach outside (of the short side).
#define FISH_FILL 0.96
#define FISH_FILL_WIDE 1.15
#define FISH_CAP 1.05
#define FISH_CA 0.01
#define FISH_BEVEL 0.93
#define FISH_JOG 0.55
#define FISH_RAINBOW 0.035

vec3 tex(vec2 uv) { return texture(uTexture, uCrop.xy + clamp(uv, 0.0, 1.0) * uCrop.zw).rgb; }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// A thin spectrum across t: 0 blue (inside) to 1 red (outside).
vec3 spectrum(float t) {
  t = clamp(t, 0.0, 1.0);
  return clamp(vec3(1.5 - abs(t - 1.0) * 3.0, 1.5 - abs(t - 0.62) * 3.4, 1.5 - abs(t - 0.22) * 3.4), 0.0, 1.0);
}

// The frame's size in pixels.
vec2 frameSize() { return uSize * uCrop.zw; }

// A small disc of taps round uv, radius rad (uv units, x scaled to stay round).
vec3 disc(vec2 uv, float rad) {
  vec2 fs = frameSize();
  vec2 k = vec2(fs.y / fs.x, 1.0) * rad;
  vec3 s = tex(uv);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398;
    s += tex(uv + vec2(cos(a), sin(a)) * k);
    s += tex(uv + vec2(cos(a + 0.39), sin(a + 0.39)) * k * 0.5);
  }
  return s / 17.0;
}

void main() {
  vec2 pic = FlutterFragCoord().xy / uSize;
  vec2 uv = (pic - uCrop.xy) / uCrop.zw;
  // (outside the frame, under the viewfinder's mask: the plain picture)
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
    fragColor = vec4(texture(uTexture, pic).rgb, 1.0);
    return;
  }
  vec2 fs = frameSize();
  vec2 d = uv - 0.5;
  float aspect = fs.x / fs.y;
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
    // fish-eye: a 180-degree circular lens (equisolid) on black, the
    // picture bent to fill it; its glass bevel refracting a band at the
    // edge, light falling off to the rim, colour fringes, a thin blue
    // coating line and a faint rainbow just outside where light hits it.
    float mn = min(fs.x, fs.y);
    // (a 16:9 frame: the circle cropped top and bottom, not a dot in black)
    float rad = (max(fs.x, fs.y) > 1.7 * mn ? FISH_FILL_WIDE : FISH_FILL) * 0.5 * mn;
    vec2 dp = d * fs;
    float rm = length(dp) / rad;
    vec2 dir = dp / max(length(dp), 1e-4);
    float r1 = min(rm, 1.0);
    float sb = smoothstep(FISH_BEVEL, 1.0, r1);
    float rq = r1 - FISH_JOG * (1.0 - FISH_BEVEL) * sb;
    float th = 2.0 * asin(rq * 0.7071068);
    float rs = tan(th * FISH_CAP / 1.5707963) / tan(FISH_CAP);
    float sh = 0.5 * mn;
    float lat = FISH_CA * rm * rm + 0.012 * sb;
    vec2 at = dir * rs * sh / fs;
    vec3 inner = vec3(tex(0.5 + at * (1.0 - lat)).r, tex(0.5 + at).g, tex(0.5 + at * (1.0 + lat)).b);
    inner *= (1.0 - 0.22 * pow(r1, 4.0)) * (1.0 - 0.5 * pow(clamp((r1 - 0.86) / 0.14, 0.0, 1.0), 2.0));
    float ring = pow(clamp((r1 - 0.982) / 0.018, 0.0, 1.0), 1.5);
    vec3 blue = luma(inner) * vec3(0.30, 0.50, 1.25) + vec3(0.01, 0.03, 0.10);
    inner = mix(inner, blue, ring);
    float edge = clamp((1.0 - rm) * rad / (0.004 * mn) + 0.5, 0.0, 1.0);
    float o = (rm - 1.0) * rad / (FISH_RAINBOW * mn);
    float rimL = luma(tex(0.5 + dir * 0.985 * sh / fs));
    float band = o > -0.2 ? exp(-pow((o - 0.45) / 0.32, 2.0)) : 0.0;
    vec3 glow = spectrum(o) * band * (0.02 + 0.6 * rimL * rimL * rimL) * 0.8;
    c = inner * edge + glow * (1.0 - edge);
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
    // pinhole: soft all over, deep vignette
    c = (disc(uv, 0.006) - 0.5) * 0.9 + 0.5;
    c *= 1.0 - 0.95 * pow(r, 2.6);
  } else if (lens == 8) {
    // mist: a diffusion filter; light glows into its surroundings, blacks
    // lift and contrast eases (the video's: VideoLens.mist)
    vec3 s = tex(uv);
    vec3 g = max(disc(uv, 0.03) - 0.35, 0.0) / 0.65;
    c = (1.0 - (1.0 - s) * (1.0 - g * 0.6)) * 0.9 + 0.06;
  } else if (lens == 9) {
    // anamorphic: long blue streaks off bright lights, an oval falloff
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
  } else {
    c = tex(uv);
  }
  fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
