#version 460 core
// Darkroom 98's resolution: the screen drawn in chunky pixels. Each block
// of uBlock device pixels shows the average of four samples inside it (no
// y-flip: see the contract test).
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;          // 0-1 (the engine's: the picture in pixels)
uniform float uBlock;        // 2   one block's size in device pixels
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 cell = floor(FlutterFragCoord().xy / uBlock) * uBlock;
  vec2 q = vec2(uBlock * 0.25);
  vec4 c = texture(uTexture, clamp((cell + vec2(q.x, q.y)) / uSize, 0.0, 1.0))
         + texture(uTexture, clamp((cell + vec2(3.0 * q.x, q.y)) / uSize, 0.0, 1.0))
         + texture(uTexture, clamp((cell + vec2(q.x, 3.0 * q.y)) / uSize, 0.0, 1.0))
         + texture(uTexture, clamp((cell + vec2(3.0 * q.x, 3.0 * q.y)) / uSize, 0.0, 1.0));
  fragColor = c * 0.25;
}
