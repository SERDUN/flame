// How a light reaches a point: the one copy of the formulas both light
// shaders use - the lighting's own (light.frag) and the GPU buffer's
// (gpu_shaders/light_buffer.frag) - and LightField mirrors in Dart
// (reach, airLightAt, glowLength, airShare), which test/light_math_test.dart
// holds to them. Plain functions of their arguments: each shader reads its
// own uniforms and passes them in.

// How much of a light of [radius] reaches [dist] from it, 0..1: smooth,
// (1 - r/R)^2, or [physical], 1/(1 + 16 r^2/R^2) eased out over its last
// quarter.
float lightFall(float dist, float radius, float physical) {
    float t = max(1.0 - dist / radius, 0.0);
    return physical < 0.5
        ? t * t
        : 1.0 / (1.0 + 16.0 * dist * dist / (radius * radius)) *
              min(1.0, t * 4.0);
}

// How much of a cone's light leaves along [across] (the way from it in the
// view's plane), 0..1: full within its spread ([cosFull]), easing out to
// nothing at its edge ([cosEdge]).
float coneAt(vec2 across, vec2 dir, float cosFull, float cosEdge) {
    float len = length(across);
    if (len <= 1e-6) {
        return 1.0;
    }
    float c = dot(across, dir) / len;
    float full = acos(clamp(cosFull, -1.0, 1.0));
    float edge = acos(clamp(cosEdge, -1.0, 1.0));
    float off = acos(clamp(c, -1.0, 1.0));
    return 1.0 - smoothstep(full, max(edge, full + 1e-4), off);
}

// How long a stretch of air, lit as at the light itself, the eye's way
// passing b from a light of radius R gathers: its falloff summed along the
// way. Smooth, (1 - r/R)^2, in closed form; physical, 1/(1 + 16 r^2/R^2),
// as an arctangent. Largest at the light and falling away from it - the
// glow of the air round a lamp is brightest at the lamp.
float glowLength(float b, float radius, float physical) {
    if (b >= radius) {
        return 0.0;
    }
    float s = sqrt(radius * radius - b * b);
    if (physical > 0.5) {
        float k = 16.0 / (radius * radius);
        float q = sqrt(1.0 + k * b * b);
        return 2.0 / (sqrt(k) * q) * atan(sqrt(k) * s / q);
    }
    float near = max(b, 1e-4 * radius);
    return (2.0 * b * b * s + 2.0 / 3.0 * s * s * s) / (radius * radius) -
        2.0 * b * b / radius * log((s + radius) / near);
}

// How much of the glow the air holds a stretch [lit] long of it, lit as at
// a light, makes against what the whole air between the eye and the street
// ([air] deep) would: in clear air as much as its length, in a fog no more
// than the air one sees through ([visibility], Koschmieder).
float airShareOf(float lit, float air, float visibility) {
    if (air <= 0.0) {
        return 1.0;
    }
    float v = max(visibility, 1e-3);
    lit = min(lit, air);
    float whole = 1.0 - exp(-3.912 * air / v);
    if (whole < 1e-6) {
        return lit / air;
    }
    return (1.0 - exp(-3.912 * lit / v)) / whole;
}

// A bulb as it is drawn (LightSource's gradient): full to 0.55 of its 1.6
// source radii, fading linearly to nothing at 1 - so what the lighting
// leaves of the night round it fits the bulb with no ring.
float bulbItself(float r) {
    return 1.0 - clamp((r - 0.55) / 0.45, 0.0, 1.0);
}

// The radius of the halo [haze] makes round a source of [source] radius
// (LightField.haloRadius).
float haloRadius(float source, float haze) {
    return source * (6.0 + 24.0 * haze);
}

// The halo the haze makes round a source, out to 1 of its radius, as
// LightSource.halo draws it: 1 at the heart, 0.35 at a quarter, 0 at 1.
float halo(float r) {
    if (r >= 1.0) {
        return 0.0;
    }
    return r < 0.25 ? mix(1.0, 0.35, r / 0.25) : mix(0.35, 0.0, (r - 0.25) / 0.75);
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
