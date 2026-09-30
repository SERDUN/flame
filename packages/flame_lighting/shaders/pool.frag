#version 460 core

// The light a lamp lays on the ground, seen from the side.
//
// Each point of the ground band is a point on a real ground: its row says how
// far in front of the street line it lies (the depth), its column how far
// along the street. The lamp hangs uHeight above the ground on the street
// line. The light falling on a point is the lamp's light that reaches it -
// fading to nothing at uRadius, full along the beam and easing out across
// its edge - times the cosine of the angle it falls at: bright under the
// lamp, thinning as it comes in low. The shape of the pool is what that
// gives: a round pool under a lamp pointing down, a long tongue ahead of a
// torch tilted down.

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uLight;      // the lamp, world units
uniform float uHeight;    // how high above the ground it hangs
uniform vec2 uAxis;       // its beam, a unit vector on the screen (y down)
uniform float uHalf;      // half the cone's angle, radians; 0 all round
uniform float uEdge;      // how much of that the edge eases over, radians
uniform float uRadius;    // how far its light reaches
uniform float uTop;       // the ground band's top: the street line
uniform float uBand;      // the band's height on the screen
uniform float uSpan;      // how far in front of the line its bottom lies
uniform vec4 uColor;      // the light's colour, alpha its strength here

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy;
    float depth = clamp((p.y - uTop) / uBand, 0.0, 1.0);
    // From the lamp to the point, x along the street, y up, z to the eye.
    vec3 v = vec3(p.x - uLight.x, -uHeight, depth * uSpan);
    float dist = length(v);
    if (dist >= uRadius || dist < 1e-3) {
        fragColor = vec4(0.0);
        return;
    }
    float cone = 1.0;
    if (uHalf > 0.0) {
        vec3 axis = vec3(uAxis.x, -uAxis.y, 0.0);
        float off = acos(clamp(dot(v / dist, axis), -1.0, 1.0));
        cone = 1.0 - smoothstep(uHalf - uEdge, uHalf, off);
    }
    float reach = 1.0 - dist / uRadius;
    float incidence = uHeight / dist;
    float e = uColor.a * reach * reach * incidence * cone;
    fragColor = vec4(uColor.rgb * e, e);
}
