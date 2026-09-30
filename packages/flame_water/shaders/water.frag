#version 460 core

// A reflection in a stretch of water, bent by the rings rain makes on it.
//
// uReflection is the mirrored world (or its glow), rendered into an image the
// size of the water's rectangle - already smeared by how rough the surface
// is. Each ring is a travelling bump on the surface: where it passes, the
// surface tilts, and the reflection there is looked up a little to one side,
// so the mirrored world wobbles around every drop, and a lamp's streak on a
// wet road breaks where drops land.
//
// Rain keeps the whole surface astir besides: uChop is that chop, a small
// restless wave everywhere, changing fastest from row to row, so a lamp's
// reflection breaks into wavering horizontal bands, as it does on a road
// in the rain.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kMaxRings = 32;

uniform vec2 uSize;           // the water's rectangle, local units
uniform float uCount;         // rings in use
uniform float uFlatten;       // ring height over width: water seen low
uniform float uWavelength;    // length of a ring's wave, local units
uniform float uGain;          // how bright the result comes out
uniform float uTime;          // seconds, for the chop
uniform float uChop;          // how far the chop shifts the mirror, local units
uniform float uElevTop;       // sine of the angle the eye looks down, top row
uniform float uElevBottom;    // ... and bottom row
uniform float uFresnel;       // 1: mirror as much as water does at that angle
uniform float uSpread;        // how long a rough surface smears a point, units
uniform vec4 uRings[kMaxRings]; // centre x, centre y, radius, amplitude
uniform sampler2D uReflection;

out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
        u.y);
}

// The surface's restless chop: mostly sideways, changing fast down the rows
// and slowly across them.
vec2 chop(vec2 p) {
    if (uChop <= 0.0) {
        return vec2(0.0);
    }
    float a = noise(vec2(p.x * 0.07, p.y * 0.55 + uTime * 3.1));
    float b = noise(vec2(p.x * 0.19 + 7.0, p.y * 1.3 - uTime * 4.3));
    float side = (a * 0.65 + b * 0.35 - 0.5) * 2.0;
    return vec2(side * uChop, (b - 0.5) * uChop * 0.3);
}

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

// Water's reflectance seen at an angle whose sine above it is s (Schlick).
float fresnel(float s) {
    float c = 1.0 - clamp(s, 0.0, 1.0);
    return 0.02 + 0.98 * c * c * c * c * c;
}

// The mirror at uv, nothing outside it: the sampler clamps, and a clamped
// edge would run on as a line.
vec4 mirrored(vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0);
    }
    return texture(uReflection, uv);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec2 at = p + ripple(p) + chop(p);
    float s = mix(uElevTop, uElevBottom, clamp(p.y / uSize.y, 0.0, 1.0));
    // A rough surface smears a point into a column as long as its slopes
    // allow (the image is already blurred that long) and as wide as that
    // times the sine of the angle it is seen at: a thin streak far off,
    // where the eye looks along the water, rounder near.
    float across = uSpread * s;
    vec4 color;
    if (across < 0.75) {
        color = mirrored(at / uSize);
    } else {
        vec4 sum = vec4(0.0);
        float total = 0.0;
        for (int k = -4; k <= 4; k++) {
            float x = float(k) * 0.5;
            float w = exp(-0.5 * x * x);
            sum += mirrored((at + vec2(x * across, 0.0)) / uSize) * w;
            total += w;
        }
        color = sum / total;
    }
    float reflectance = uFresnel > 0.5 ? fresnel(s) : 1.0;
    fragColor = color * uGain * reflectance;
}
