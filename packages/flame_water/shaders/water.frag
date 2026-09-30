#version 460 core

// The reflection in a stretch of water, bent by the rings rain makes on it.
//
// uReflection is the mirrored world, rendered into an image the size of the
// water's rectangle. Each ring is a travelling bump on the surface: where it
// passes, the surface tilts, and the reflection there is looked up a little
// to one side, so the mirrored street wobbles around every drop.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kMaxRings = 16;

uniform vec2 uSize;           // the water's rectangle, local units
uniform float uCount;         // rings in use
uniform float uFlatten;       // ring height over width: water seen low
uniform float uWavelength;    // length of a ring's wave, local units
uniform vec4 uRings[kMaxRings]; // centre x, centre y, radius, amplitude
uniform sampler2D uReflection;

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec2 shift = vec2(0.0);
    for (int i = 0; i < kMaxRings; i++) {
        if (float(i) >= uCount) {
            break;
        }
        vec4 ring = uRings[i];
        // In ring space the ring is a circle: undo the flattening.
        vec2 d = p - ring.xy;
        d.y /= uFlatten;
        float dist = length(d);
        if (dist < 0.0001) {
            continue;
        }
        float x = dist - ring.z;
        float width = uWavelength * 0.75;
        float envelope = exp(-(x * x) / (width * width));
        float wave = sin(x * 6.2831853 / uWavelength) * envelope * ring.w;
        vec2 dir = d / dist;
        shift += vec2(dir.x, dir.y * uFlatten) * wave;
    }
    vec2 uv = clamp((p + shift) / uSize, vec2(0.0), vec2(1.0));
    fragColor = texture(uReflection, uv);
}
