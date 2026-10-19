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
#include "light_math.glsl"

const int kShadows = 24;
const int kCapsules = 8;
// Samples of the ground's height across the band (GroundLift), four a vec4,
// and the band's span after them.
const int kLift = 8;

uniform vec4 u[kCapsules + kShadows * 2 + kLift + 1];

#define LIFT0 (kCapsules + kShadows * 2)
#define LIFT_SPAN u[kCapsules + kShadows * 2 + kLift]   // left, right, samples

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
// The depth of air the light fills, along the eye's way; 0: it falls on a
// surface. A capsule darkens a way through the air only over its own
// depth, so its shadow there is as deep as it is thick against the air's.
#define S_AIR u[7].y
// How far one sees through the air, in the world's units (Koschmieder).
#define S_VIS u[7].z

const float kArea = 2.0;
const float kLine = 3.0;
const float kCone = 1.0;
const float kSun = 4.0;
// As far as LightField.sunDistance.
const float kSunDistance = 1e5;

out vec4 fragColor;

// How high the ground stands at world x: its hill there. Level (no
// samples): nothing.
float liftAt(float x) {
    float n = LIFT_SPAN.z;
    if (n < 1.5) {
        return 0.0;
    }
    float s = clamp((x - LIFT_SPAN.x) / max(LIFT_SPAN.y - LIFT_SPAN.x, 1e-6),
                    0.0, 1.0) * (n - 1.0);
    float i0 = min(floor(s), n - 2.0);
    float t = s - i0;
    float a = 0.0;
    float b = 0.0;
    // A uniform array is read by a loop's own index only.
    for (int k = 0; k < kLift * 4; k++) {
        float fk = float(k);
        if (fk == i0 || fk == i0 + 1.0) {
            vec4 q = u[LIFT0 + k / 4];
            int c = k - (k / 4) * 4;
            float v = c == 0 ? q.x : (c == 1 ? q.y : (c == 2 ? q.z : q.w));
            if (fk == i0) {
                a = v;
            } else {
                b = v;
            }
        }
    }
    return mix(a, b, t);
}

// How far in front of the street line ground at depth d lies.
float ahead(float d) {
    float inverse = max(1.0 / P_FAR + d * (1.0 / P_NEAR - 1.0 / P_FAR),
                        0.05 / P_FAR);
    return P_FAR - 1.0 / inverse;
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
        float share = S_AIR > 0.0 ? min(1.0, 2.0 * slab / S_AIR) : 1.0;
        light *= 1.0 - info.w * share * (1.0 - visible);
    }
    return light;
}

// The air's share of the glow [lit] makes (airShareOf), in this pass's air.
float airShare(float lit) {
    return S_AIR <= 0.0 ? 1.0 : airShareOf(lit, S_AIR, S_VIS);
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec3 p;
    // The hill here: the street line and the ground in front of it raised.
    // Over a hill the planes' rects overlap; each keeps to its own side.
    float lift = liftAt(frag.x);
    float line = P_TOP - lift;
    if (LIFT_SPAN.z > 1.5 && (MODE > 0.5) != (frag.y > line)) {
        fragColor = vec4(0.0);
        return;
    }
    if (MODE > 0.5) {
        float depth = clamp((frag.y - line) / P_BAND, 0.0, 1.0);
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
    float fall = lightFall(dist, L_RADIUS, FALLOFF);
    float cone = abs(L_SHAPE - kCone) < 0.5
        ? coneAt(v.xy, L_DIR, L_COS_FULL, L_COS_EDGE)
        : 1.0;
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
    if (S_AIR > 0.0) {
        // The air: the light summed along the eye's way past it.
        float lit = cone * glowLength(dist, L_RADIUS, FALLOFF);
        if (dist < spillRadius) {
            lit = max(lit, L_SPILL * glowLength(dist, spillRadius, 0.0));
        }
        float glow = AMOUNT * L_STRENGTH * shade * airShare(lit);
        fragColor = vec4(L_COLOR * glow, glow);
        return;
    }
    float a = AMOUNT * L_STRENGTH * reach * incidence * shade;
    fragColor = vec4(L_COLOR * a, a);
}
