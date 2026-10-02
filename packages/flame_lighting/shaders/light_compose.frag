#version 460 core

// The light buffer laid over the scene: the illumination, as the eye's
// exposure makes it (to multiply the scene by), or the light in the air,
// or a wet wall's sheen of it. One draw each, however many lights there
// are.

precision highp float;

#include <flutter/runtime_effect.glsl>

// One array of vectors, named below (see light.frag for why).
uniform vec4 u[3];

#define uArea    u[0]      // the world rect the buffer covers
#define uSky     u[1].rgb  // the sky's light, in lights' units
#define uExpose  u[1].a    // the eye's exposure
#define uMode    u[2].x    // 0 the illumination, 1 the light cast (a sheen)
#define uAmount  u[2].y    // how much of the light cast
#define uNoWhite u[2].z    // 1: alpha is coverage, its white already in the
                           // colour (the canvas path's image)

uniform sampler2D uLight;

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec4 light = texture(uLight, (p - uArea.xy) / uArea.zw);
    if (uMode < 0.5) {
        // The sky's light as the eye takes it, and the lamps' filling what
        // is left up to white the way film and the eye do: in proportion
        // while faint, more and more slowly as it nears white, never at a
        // hard stop. A clamp turned a cone's soft edge, lit far past white,
        // into a straight line where it met the clamp.
        vec3 base = min(uSky * uExpose, vec3(1.0));
        vec3 lamps = (light.rgb + vec3(light.a) * (1.0 - uNoWhite)) * uExpose;
        vec3 room = max(vec3(1.0) - base, vec3(1e-4));
        vec3 seen = vec3(1.0) - room * exp(-lamps / room);
        fragColor = vec4(seen, 1.0);
        return;
    }
    vec3 given = light.rgb * uAmount;
    fragColor = vec4(given, clamp(max(given.r, max(given.g, given.b)), 0.0, 1.0));
}
