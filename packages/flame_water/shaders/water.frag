#version 460 core

// A reflection in a stretch of water: bent by the rings rain makes on it,
// and smeared downwards by how rough the surface is.
//
// uReflection is the mirrored world (or its glow), rendered into an image the
// size of the water's rectangle. Each ring is a travelling bump on the
// surface: where it passes, the surface tilts, and the reflection there is
// looked up a little to one side, so the mirrored world wobbles around every
// drop. A rough surface (a wet road) mirrors each point over a range of
// heights, so a lamp's reflection runs down it into a long streak - which
// the ripples then break, since every row of it is bent on its own.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kMaxRings = 16;
const int kTaps = 14;

uniform vec2 uSize;           // the water's rectangle, local units
uniform float uCount;         // rings in use
uniform float uFlatten;       // ring height over width: water seen low
uniform float uWavelength;    // length of a ring's wave, local units
uniform float uStreak;        // how far a rough surface smears, local units
uniform float uGain;          // how bright the result comes out
uniform vec4 uRings[kMaxRings]; // centre x, centre y, radius, amplitude
uniform sampler2D uReflection;

out vec4 fragColor;

vec2 ripple(vec2 p) {
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
    return shift;
}

vec4 look(vec2 p) {
    return texture(uReflection, clamp(p / uSize, vec2(0.0), vec2(1.0)));
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec2 at = p + ripple(p);
    if (uStreak < 0.5) {
        fragColor = look(at) * uGain;
        return;
    }
    // Each point shows what lies over a range of heights above it, mostly
    // above (the streak runs towards the viewer) and a little below.
    vec4 sum = vec4(0.0);
    float weights = 0.0;
    for (int i = 0; i < kTaps; i++) {
        float t = mix(-0.25, 1.0, float(i) / float(kTaps - 1));
        float w = 1.0 - 0.7 * abs(t);
        sum += look(at - vec2(0.0, t * uStreak)) * w;
        weights += w;
    }
    fragColor = sum / weights * uGain;
}
