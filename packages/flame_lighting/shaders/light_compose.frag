#version 460 core

// The light buffer laid over the scene: the illumination, as the eye's
// exposure makes it (to multiply the scene by), or the light in the air,
// or a wet wall's sheen of it; or a picture of the air divided by that
// illumination, to go into the lit layer and come out of its multiply as the
// air's own light. One draw each, however many lights there are.

precision highp float;

#include <flutter/runtime_effect.glsl>

// One array of vectors, named below (see light.frag for why).
uniform vec4 u[5];

#define uArea    u[0]      // the world rect the buffer covers
#define uSky     u[1].rgb  // the sky's light, in lights' units
#define uExpose  u[1].a    // the eye's exposure
#define uMode    u[2].x    // 0 the illumination, 1 the light cast (a sheen)
#define uAmount  u[2].y    // how much of the light cast
#define uNoWhite u[2].z    // 1: alpha is coverage, its white already in the
                           // colour (the canvas path's image)
#define uAirArea u[3]      // mode 2: the world rect the air's picture is laid on
#define uAirSrc  u[4]      // mode 2: the part of the picture, in its 0..1

uniform sampler2D uLight;
uniform sampler2D uAir;    // mode 2: the air's picture; any image otherwise

out vec4 fragColor;

// The sky's light as the eye takes it, and the lamps' filling what is left
// up to white the way film and the eye do: in proportion while faint, more
// and more slowly as it nears white, never at a hard stop. A clamp turned a
// cone's soft edge, lit far past white, into a straight line where it met the
// clamp.
vec3 illumination(vec4 light) {
    vec3 base = min(uSky * uExpose, vec3(1.0));
    vec3 lamps = (light.rgb + vec3(light.a) * (1.0 - uNoWhite)) * uExpose;
    vec3 room = max(vec3(1.0) - base, vec3(1e-4));
    return vec3(1.0) - room * exp(-lamps / room);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec4 light = texture(uLight, (p - uArea.xy) / uArea.zw);
    if (uMode < 0.5) {
        fragColor = vec4(illumination(light), 1.0);
        return;
    }
    if (uMode > 1.5) {
        // The air divided by what will multiply it: laid into the lit layer
        // over what is there (premultiplied), the multiply gives back the
        // air's own light and lights only what shows through it. Past what a
        // layer holds - the light too faint to divide by - it is darker.
        vec2 t = (p - uAirArea.xy) / uAirArea.zw;
        vec4 air = texture(uAir, uAirSrc.xy + t * uAirSrc.zw);
        vec3 seen = max(illumination(light), vec3(1.0 / 255.0));
        fragColor = vec4(air.rgb / seen, air.a);
        return;
    }
    vec3 given = light.rgb * uAmount;
    fragColor = vec4(given, clamp(max(given.r, max(given.g, given.b)), 0.0, 1.0));
}
