#version 460 core

// The air between the eye and what is drawn: as much of the air's own light
// as the air takes of what lies behind it (Koschmieder), worked out per
// pixel from the air's extinction field (AirField) summed along the eye's
// way.
//
// A veil (mode 0) stands at a depth: over everything at that depth and
// behind it - what is drawn above where that depth meets the ground - it
// lays the air between that depth and the next veil toward the eye (or the
// eye). The ground's air (mode 1) lies over the ground band, each row the
// air between the ground there and the next veil nearer than it.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kMaxBanks = 3;
const int kMaxVeils = 6;
const int kSteps = 16;

uniform vec4 u[6 + kMaxBanks * 2 + kMaxVeils / 4 + 1];

#define uProjection  u[0]      // band top, band height, near, far distance
#define uEye         u[1]      // eye height, world units a metre, focus x,
                               // the mode (0 a veil, 1 the ground's air)
#define uDepths      u[2]      // the veil's depth, the nearer veil's (or
                               // below -1e8 for the eye), the air's base
                               // extinction per metre, veils in the list
#define uColor       u[3]      // the air's light, premultiplied
#define uBanks       4         // two vec4 a bank: (extinction, at, cos, sin),
                               // (width, slant, top, top's width); an
                               // extinction of 0 for none
#define uVeils       (4 + kMaxBanks * 2)  // the veils' depths, four a vec4

out vec4 fragColor;

float distanceAt(float depth) {
    float near = uProjection.z;
    float far = uProjection.w;
    float inverse = max(1.0 / far + depth * (1.0 / near - 1.0 / far),
                        0.05 / far);
    return 1.0 / inverse;
}

// Per metre, what the air takes away at (x along the road, ahead of the
// street line, height), metres.
float extinction(vec3 p) {
    float sigma = uDepths.z;
    for (int i = 0; i < kMaxBanks; i++) {
        vec4 a = u[uBanks + i * 2];
        vec4 b = u[uBanks + i * 2 + 1];
        if (a.x <= 0.0) {
            continue;
        }
        // A layer up to its top, thinning out round it (AirBank._layer).
        float s = max(b.w, 1e-3) / 4.0;
        float share = 1.0 / (1.0 + exp(clamp((p.z - b.z) / s, -60.0, 60.0)));
        if (a.y > -1e8) {
            float along = p.x * a.z + p.y * a.w - b.y * p.z;
            float t = clamp((along - a.y) / max(b.x, 1e-6) + 0.5, 0.0, 1.0);
            share *= t * t * (3.0 - 2.0 * t);
        }
        sigma += a.x * share;
    }
    return sigma;
}

// The optical depth of the eye's way to point q from t0 to t1 of the way.
float opticalDepth(vec3 eye, vec3 q, float t0, float t1) {
    vec3 d = q - eye;
    float length_ = length(d) * (t1 - t0);
    if (length_ <= 0.0) {
        return 0.0;
    }
    float sum = 0.0;
    for (int i = 0; i < kSteps; i++) {
        float t = t0 + (t1 - t0) * (float(i) + 0.5) / float(kSteps);
        sum += extinction(eye + d * t);
    }
    return sum / float(kSteps) * length_;
}

// The nearest of the veils nearer than depth, of those in v; nearer below
// -1e8 for none so far.
float nearestOf(vec4 v, float count, float base, float depth, float nearer) {
    for (int k = 0; k < 4; k++) {
        if (base + float(k) >= count) {
            break;
        }
        float d = k == 0 ? v.x : (k == 1 ? v.y : (k == 2 ? v.z : v.w));
        if (d > depth && (nearer < -1e8 || d < nearer)) {
            nearer = d;
        }
    }
    return nearer;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    float top = uProjection.x;
    float band = uProjection.y;
    float far = uProjection.w;
    float metre = max(uEye.y, 1e-6);
    float focus = uEye.z;
    vec3 eye = vec3(focus / metre, far / metre, uEye.x / metre);
    float depth;
    float height;
    if (uEye.w < 0.5) {
        // A veil: over what is drawn above where its depth meets the ground.
        depth = uDepths.x;
        float yd = top + clamp(depth, 0.0, 1.0) * band;
        if (frag.y > yd) {
            fragColor = vec4(0.0);
            return;
        }
        float scale = far / distanceAt(depth);
        height = (yd - frag.y) / scale / metre;
    } else {
        // The ground's air: the ground at this row.
        if (frag.y < top) {
            fragColor = vec4(0.0);
            return;
        }
        depth = clamp((frag.y - top) / max(band, 1e-6), 0.0, 1.0);
        height = 0.0;
    }
    float distance_ = distanceAt(depth);
    float scale = far / distance_;
    vec3 q = vec3((focus + (frag.x - focus) / scale) / metre,
                  (far - distance_) / metre, height);
    // Where the next veil toward the eye stands on this way: from there on
    // it lays its own air.
    float nearer = uDepths.y;
    if (uEye.w > 0.5) {
        nearer = -1e9;
        nearer = nearestOf(u[uVeils], uDepths.w, 0.0, depth, nearer);
        nearer = nearestOf(u[uVeils + 1], uDepths.w, 4.0, depth, nearer);
    }
    // The way's share from the eye to the nearer veil: distance from the eye
    // grows along it from nothing to the point's.
    float t0 = nearer > -1e8
        ? clamp(distanceAt(nearer) / max(distance_, 1e-6), 0.0, 1.0)
        : 0.0;
    float tau = opticalDepth(eye, q, t0, 1.0);
    float a = 1.0 - exp(-tau);
    fragColor = uColor * a;
}
