#version 460 core

// One light, as it falls on a plane of a side-view street: on the wall plane
// (what stands on the street line - house fronts, the air in front of them)
// or on the ground (the band from the street line down to the nearest ground
// in view, its rows at the depths the street's projection gives).
//
// Everything is in one space: x and y on the screen, z how far in front of
// the street line, as the projection lays it out. A light reaches a point
// over the way between them, falling off to nothing at its radius, inside
// its cone if it has one, from the nearest part of what glows (a window,
// a tube). Whatever stands in the way - capsules at their depths - cuts it,
// with a penumbra as wide as the light's source makes it. On the ground it
// comes in at an angle: bright under a lamp, thin where it grazes.
//
// One vec4 array, named by #define: every value 16-byte aligned on every
// backend, and one binding - Metal binds each uniform on its own, at most 31.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kShadows = 24;
const int kCapsules = 8;

uniform vec4 u[kCapsules + kShadows * 2];

// The light (LightField's layout).
#define L_POS u[0].xy
#define L_AHEAD u[0].z
#define L_SHAPE u[0].w
#define L_COLOR u[1].rgb
#define L_STRENGTH u[1].a
#define L_RADIUS u[2].x
#define L_DIR u[2].yz
#define L_COS_FULL u[2].w
#define L_COS_EDGE u[3].x
#define L_EXTENT u[3].yz
#define L_SOURCE u[3].w
#define L_SPILL u[4].x
#define L_SPILL_RADIUS u[4].y
#define FALLOFF u[4].z
// The street's projection.
#define P_TOP u[5].x
#define P_BAND u[5].y
#define P_NEAR u[5].z
#define P_FAR u[5].w
#define P_EYE u[6].x
// How to draw: on the wall (0) or the ground (1), and how much.
#define MODE u[6].y
#define AMOUNT u[6].z
// The wall plane's distance in front of the street line (behind, negative).
#define WALL_AHEAD u[6].w
// What stands in the way: capsules from u[kCapsules], two vec4 each.
#define S_COUNT u[7].x

const float kArea = 2.0;
const float kLine = 3.0;
const float kCone = 1.0;
const float kSun = 4.0;
// As far as LightField.sunDistance.
const float kSunDistance = 1e5;

out vec4 fragColor;

// How far in front of the street line ground at depth d lies.
float ahead(float d) {
    float inverse = max(1.0 / P_FAR + d * (1.0 / P_NEAR - 1.0 / P_FAR),
                        0.05 / P_FAR);
    return P_FAR - 1.0 / inverse;
}

// The nearest the segment p1-p2 comes to the segment q1-q2: where along
// the first, 0..1, and how far apart there (ShadowSet._segments).
vec2 segments(vec2 p1, vec2 p2, vec2 q1, vec2 q2) {
    vec2 d1 = p2 - p1;
    vec2 d2 = q2 - q1;
    vec2 r = p1 - q1;
    float a = dot(d1, d1);
    float e = dot(d2, d2);
    float f = dot(d2, r);
    float s = 0.0;
    float t = 0.0;
    if (a <= 1e-12 && e <= 1e-12) {
        s = 0.0;
        t = 0.0;
    } else if (a <= 1e-12) {
        t = clamp(f / e, 0.0, 1.0);
    } else {
        float c = dot(d1, r);
        if (e <= 1e-12) {
            s = clamp(-c / a, 0.0, 1.0);
        } else {
            float b = dot(d1, d2);
            float denom = a * e - b * b;
            s = denom > 1e-12 ? clamp((b * f - c * e) / denom, 0.0, 1.0) : 0.0;
            t = (b * s + f) / e;
            if (t < 0.0) {
                t = 0.0;
                s = clamp(-c / a, 0.0, 1.0);
            } else if (t > 1.0) {
                t = 1.0;
                s = clamp((b - c) / a, 0.0, 1.0);
            }
        }
    }
    return vec2(s, length(p1 + d1 * s - (q1 + d2 * t)));
}

// How much light gets from the source at l to the point at p past every
// capsule (ShadowSet.through, on the GPU).
float through(vec3 l, vec3 p, float source) {
    float light = 1.0;
    for (int i = 0; i < kShadows; i++) {
        if (float(i) >= S_COUNT) {
            break;
        }
        vec4 seg = u[kCapsules + i * 2];
        vec4 info = u[kCapsules + i * 2 + 1];
        float radius = info.x;
        float cz = info.y;
        float slab = info.z * 0.5;
        // Near either end of the way, as a share of it: a capsule's
        // radius, no more than 2 % (ShadowSet.through).
        float end = min(0.02, radius / max(length(p - l), 1e-9));
        // The part of the way through the capsule's depth, then the nearest
        // it comes to the capsule on screen; from the point back, for
        // precision.
        vec3 e = p - l;
        float t0;
        float t1;
        if (abs(e.z) < 1e-9) {
            if (abs(l.z - cz) > slab) {
                continue;
            }
            t0 = 0.0;
            t1 = 1.0;
        } else {
            float ta = (cz - slab - l.z) / e.z;
            float tb = (cz + slab - l.z) / e.z;
            t0 = min(ta, tb);
            t1 = max(ta, tb);
        }
        t0 = max(t0, end);
        t1 = min(t1, 1.0 - end);
        if (t0 >= t1) {
            continue;
        }
        vec2 nearest = segments(p.xy - e.xy * (1.0 - t0),
                                p.xy - e.xy * (1.0 - t1), seg.xy, seg.zw);
        float t = t0 + (t1 - t0) * nearest.x;
        float dist = nearest.y;
        float blur = max(source * (1.0 - t), radius * 1e-3);
        float s = clamp((dist - radius) / blur + 0.5, 0.0, 1.0);
        float visible = s * s * (3.0 - 2.0 * s);
        light *= 1.0 - info.w * (1.0 - visible);
    }
    return light;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec3 p;
    if (MODE > 0.5) {
        float depth = clamp((frag.y - P_TOP) / P_BAND, 0.0, 1.0);
        p = vec3(frag, ahead(depth));
    } else {
        p = vec3(frag, WALL_AHEAD);
    }
    if (abs(L_SHAPE - kSun) < 0.5) {
        // The sun: from far off along its way, everywhere; on the ground as
        // steeply as it comes down, on the house fronts as much as it comes
        // from the eye's side.
        vec3 way = vec3(L_DIR, L_AHEAD);
        vec3 from = p - way * kSunDistance;
        float facing = MODE > 0.5 ? max(way.y, 0.0) : max(-way.z, 0.0);
        float lit = S_COUNT > 0.5 ? through(from, p, L_SOURCE) : 1.0;
        float a = AMOUNT * L_STRENGTH * facing * lit;
        fragColor = vec4(L_COLOR * a, a);
        return;
    }
    // The nearest point of what glows.
    vec2 e = L_POS;
    if (abs(L_SHAPE - kArea) < 0.5) {
        vec2 halfSize = L_EXTENT * 0.5;
        e = clamp(p.xy, L_POS - halfSize, L_POS + halfSize);
    } else if (abs(L_SHAPE - kLine) < 0.5) {
        float along = clamp(dot(p.xy - L_POS, L_DIR), -L_EXTENT.x * 0.5,
                            L_EXTENT.x * 0.5);
        e = L_POS + L_DIR * along;
    }
    vec3 l = vec3(e, L_AHEAD);
    vec3 v = p - l;
    float dist = length(v);
    float spillRadius = L_SPILL > 0.0 ? L_SPILL_RADIUS : 0.0;
    if ((dist >= L_RADIUS && dist >= spillRadius) || L_STRENGTH <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    float t = max(1.0 - dist / L_RADIUS, 0.0);
    float fall = FALLOFF < 0.5
        ? t * t
        : 1.0 / (1.0 + 16.0 * dist * dist / (L_RADIUS * L_RADIUS)) *
              min(1.0, t * 4.0);
    float cone = 1.0;
    if (abs(L_SHAPE - kCone) < 0.5) {
        float across = length(v.xy);
        if (across > 1e-6) {
            float c = dot(v.xy, L_DIR) / across;
            float full = acos(clamp(L_COS_FULL, -1.0, 1.0));
            float edge = acos(clamp(L_COS_EDGE, -1.0, 1.0));
            float off = acos(clamp(c, -1.0, 1.0));
            cone = 1.0 - smoothstep(full, max(edge, full + 1e-4), off);
        }
    }
    float incidence = 1.0;
    if (MODE > 0.5) {
        // On the ground light comes in at an angle: as much as it falls.
        incidence = dist < 1e-3 ? 1.0 : clamp(v.y / dist, 0.0, 1.0);
    }
    float shade = S_COUNT > 0.5 ? through(l, p, L_SOURCE) : 1.0;
    float reach = fall * cone;
    if (dist < spillRadius) {
        // What the source throws all round, near it.
        float ts = 1.0 - dist / spillRadius;
        reach = max(reach, L_SPILL * ts * ts);
    }
    float a = AMOUNT * L_STRENGTH * reach * incidence * shade;
    fragColor = vec4(L_COLOR * a, a);
}
