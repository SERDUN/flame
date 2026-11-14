#version 460 core

// A veil of rain far off: so much rain so far away that each drop is a fine
// faint streak. Drawn from a formula, not simulated. The air is cut into
// columns along the wind's slant, a few streaks in each, each falling on
// its own phase and at its own speed and wrapping round the view's height;
// as hard as it rains, that share of them shows.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kPerColumn = 3;

// One array of vectors, named below (see water.frag for why).
uniform vec4 u[5];

#define uView    u[0]       // the view: left, top, width, height, world
#define uTime    u[1].x     // seconds
#define uFall    u[1].y     // how fast its streaks fall, world units a second
#define uLength  u[1].z     // a streak's length
#define uWidth   u[1].w     // a streak's width
#define uSlope   u[2].x     // across per down: the wind's slant
#define uShift   u[2].y     // how far it has slid by in the view (parallax)
#define uColumn  u[2].z     // a column's width
#define uShare   u[2].w     // the share of the streaks that show
#define uColor   u[3]       // the streaks' colour, premultiplied
#define uPixel   u[4].x     // world units a pixel
#define uSeed    u[4].y     // which veil: each has its own streaks

out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float down = p.y - uView.y;
    // Across, leaned back by the slant: a streak is a column there.
    float along = p.x - uView.x + uShift - down * uSlope;
    float column = floor(along / uColumn);
    // A slanted streak is that much narrower across.
    float lean = sqrt(1.0 + uSlope * uSlope);
    // A streak finer than a pixel is drawn a pixel wide, as faint as it is
    // finer: a thin stroke's coverage, as the canvas draws one.
    float half_ = max(uWidth, uPixel) * 0.5;
    float faint = uWidth / (2.0 * half_);
    float cover = 0.0;
    for (int k = 0; k < kPerColumn; k++) {
        vec2 seed = vec2(column, float(k) * 17.0 + uSeed);
        if (hash(seed + 11.3) > uShare) {
            continue;
        }
        float x = (column + hash(seed)) * uColumn;
        float speed = 0.8 + 0.4 * hash(seed + 3.1);
        float head = fract(hash(seed + 7.7) + uTime * uFall * speed / uView.w) *
            uView.w;
        float behind = head - down;
        if (behind < 0.0 || behind > uLength) {
            continue;
        }
        float across = abs(along - x) / lean;
        float edge = smoothstep(half_ - uPixel * 0.5, half_ + uPixel * 0.5,
                                across);
        cover = max(cover, (1.0 - edge) * faint);
    }
    fragColor = uColor * cover;
}
