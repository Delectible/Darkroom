#version 460 core
// Darkroom 98's CRT: the picture bulging out of the curved glass. Each
// pixel samples a little further from the centre than it sits (more toward
// the corners), so the lines bow and the corners fall away into the black
// round the tube (no y-flip: see the contract test).
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;          // 0-1 (the engine's: the screen in pixels)
uniform float uK;            // 2   how far it bulges (0 = flat)
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 d = uv - 0.5;
  float a = uSize.x / uSize.y;
  // squared distance from the centre, 1.0 at the corners
  float r2 = (d.x * d.x * a * a + d.y * d.y) / (0.25 * (a * a + 1.0));
  // Normalised per axis so the middle of each edge stays on the edge: the
  // picture fills the glass and only its corners bow in.
  float e = 1.0 / (a * a + 1.0);
  vec2 src = 0.5 + d * (1.0 + uK * r2) / (1.0 + uK * vec2(a * a * e, e));
  if (src.x < 0.0 || src.y < 0.0 || src.x > 1.0 || src.y > 1.0) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  fragColor = texture(uTexture, src);
}
