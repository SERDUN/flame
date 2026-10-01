#version 460 core

// A cone of light, as the lighting draws it on the night: a disc fading from
// its source out to its radius, masked to its cone, which eases out across
// its edges - no hard line anywhere. The same falloff and edge the canvas
// drew with a radial gradient and a sweep mask in a layer, in one pass.

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;     // the source, world units
uniform float uRadius;    // how far its light reaches
uniform vec4 uColor;      // its colour, alpha how strong here
uniform float uDirection; // the cone's axis, radians (y down)
uniform float uHalf;      // half the cone's angle
uniform float uSoft;      // share of the cone its edges ease over, each side

out vec4 fragColor;

void main() {
    vec2 d = FlutterFragCoord().xy - uCenter;
    float r = length(d) / uRadius;
    if (r >= 1.0) {
        fragColor = vec4(0.0);
        return;
    }
    // The gradient's stops: full at the source, 0.35 at 0.35 of the way,
    // nothing at the radius.
    float falloff = r < 0.35 ? mix(1.0, 0.35, r / 0.35)
                             : mix(0.35, 0.0, (r - 0.35) / 0.65);
    float off = abs(atan(d.y, d.x) - uDirection);
    off = mod(off, 6.2831853);
    if (off > 3.1415927) {
        off = 6.2831853 - off;
    }
    // From the edge in, a linear ease over uSoft of the whole cone.
    float cone = clamp((uHalf - off) / (2.0 * uHalf * uSoft), 0.0, 1.0);
    float a = uColor.a * falloff * cone;
    fragColor = vec4(uColor.rgb * a, a);
}
