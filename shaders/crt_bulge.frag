#version 460 core
// Darkroom 98's CRT: the picture bulging out of the curved glass. The
// middle is magnified a little and the edges not at all, so straight lines
// bow outward while the picture's outline stays where it is (no y-flip:
// see the contract test).
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;          // 0-1 (the engine's: the screen in pixels)
uniform float uK;            // 2   how far it bulges (0 = flat)
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 d = uv - 0.5;
  // 0 at the centre, 1 at the edges, per axis.
  vec2 e = 4.0 * d * d;
  // The middle swells toward you; the edges stay put, so the picture keeps
  // its outline (an even black rim round it) and the lines bow out.
  vec2 src = 0.5 + d * (1.0 - uK * (1.0 - e.x) * (1.0 - e.y));
  fragColor = texture(uTexture, clamp(src, 0.0, 1.0));
}
