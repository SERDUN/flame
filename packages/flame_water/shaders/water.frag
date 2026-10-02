#version 460 core

// A stretch of water: the world mirrored in it, or the lights mirrored in
// it, bent by the rings rain makes on it.
//
// In the scene mode uReflection is the mirrored world, rendered into an
// image the size of the water's rectangle. Each ring is a travelling bump on
// the surface: where it passes, the surface tilts, and the reflection there
// is looked up a little to one side, so the mirrored world wobbles around
// every drop.
//
// In the lights mode no image is read: each light of the frame is worked out
// where it is mirrored - a bulb, a lit window, a tube, with the halo the
// haze makes round it - at the same bent point, smeared as rough as the
// surface is. A lamp's streak on a wet road breaks where drops land, as the
// street's reflection does, and is the lamp as it is drawn times what water
// reflects: never brighter than the lamp itself.
//
// Rain keeps the whole surface astir besides: the chop, a small restless
// wave everywhere, changing fastest from row to row, so a lamp's reflection
// breaks into wavering horizontal bands, as it does on a road in the rain.

precision highp float;

#include <flutter/runtime_effect.glsl>

const int kMaxRings = 32;
const int kMaxLights = 8;
const int kHeader = 12;
const int kRings = kHeader;
const int kLights = kRings + kMaxRings;

// One array of vectors, named below: a lone float before a vector is laid
// out differently on Vulkan than the floats are set, and Metal binds each
// uniform on its own, 31 at most. The Dart side (WaterShader) writes the
// same layout.
uniform vec4 u[kLights + kMaxLights * 6];

#define uSize        u[0].xy   // the water's rectangle, local units
#define uCount       u[0].z    // rings in use
#define uFlatten     u[0].w    // ring height over width: water seen low
#define uWavelength  u[1].x    // length of a ring's wave, local units
#define uGain        u[1].y    // how much of the mirror comes out
#define uTime        u[1].z    // seconds, for the chop
#define uChop        u[1].w    // how far the chop shifts the mirror, units
#define uElevTop     u[2].x    // sine of the angle the eye looks down, top
#define uElevBottom  u[2].y    // ... and bottom row
#define uFresnel     u[2].z    // 1: mirror as much as water does at that angle
#define uSpread      u[2].w    // how long a rough surface smears a point
#define uBase        u[3]      // the water (or wet ground) under it, premult.
#define uTint        u[4]      // laid over the reflection, premultiplied
#define uFade        u[5].x    // how much it fades from the line down, 0..1
#define uLine        u[5].y    // the water line, local y
#define uPool        u[5].zw   // the water's outline: its centre ...
#define uPoolHalf    u[6].xy   // ... and half extents
#define uSoft        u[6].z    // share of an ellipse's radius its rim fades
#define uRound       u[6].w    // 1 an ellipse, 0 a rectangle
#define uPixels      u[7].x    // pixels of the image per local unit
#define uLightMode   u[7].y    // 1: the lights, not the image
#define uLightCount  u[7].z    // lights in use
#define uHaze        u[7].w    // the air's haze, 0..1: halos round lights
#define uWave        u[8]      // field on (1), a cell across and down, gain
#define uGlint       u[9]      // what a crest catches, premultiplied
#define uSquash      u[10].y   // the mirror's height over the thing's
#define uAir         u[10].z   // how much of the light cast on what stands
                               // on the street (walls, the air) is mirrored
#define uAirMap      u[10].w   // 1: in the lights mode uReflection is the
                               // lighting's light buffer, uImage its rect
#define uImage       u[11]     // the mirror's picture: its corner and size,
                               // local units (it covers other waters too)

uniform sampler2D uReflection;
uniform sampler2D uHeights;

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
        vec4 ring = u[kRings + i];
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

// The field's height at uv, read between cell centres by hand: not every GPU
// filters a float texture, and read cell by cell the rings come out stepped.
float height(vec2 uv) {
    vec2 cells = 1.0 / uWave.yz;
    vec2 at = uv * cells - 0.5;
    vec2 i = floor(at);
    vec2 f = at - i;
    vec2 t = uWave.yz;
    vec2 c = (i + 0.5) * t;
    float a = texture(uHeights, c).r;
    float b = texture(uHeights, c + vec2(t.x, 0.0)).r;
    float d = texture(uHeights, c + vec2(0.0, t.y)).r;
    float e = texture(uHeights, c + t).r;
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

// The surface's slope at p from the field's heights, across and down the
// water as seen (down flattened as the rings are): central differences,
// one cell each way.
vec2 slope(vec2 p) {
    vec2 uv = p / uSize;
    vec2 t = uWave.yz;
    float dx = height(uv + vec2(t.x, 0.0)) - height(uv - vec2(t.x, 0.0));
    float dy = height(uv + vec2(0.0, t.y)) - height(uv - vec2(0.0, t.y));
    return vec2(dx, dy) * 0.5;
}

// Water's reflectance seen at an angle whose sine above it is s (Schlick).
float fresnel(float s) {
    float c = 1.0 - clamp(s, 0.0, 1.0);
    return 0.02 + 0.98 * c * c * c * c * c;
}

// The mirror at local point p, nothing outside its picture: the sampler
// clamps, and a clamped edge would run on as a line.
vec4 mirrored(vec2 p) {
    vec2 uv = (p - uImage.xy) / uImage.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0);
    }
    return texture(uReflection, uv);
}

// How much water there is at p: 1 inside the outline, easing to nothing
// over an ellipse's soft rim.
float pool(vec2 p) {
    vec2 d = (p - uPool) / max(uPoolHalf, vec2(1e-3));
    if (uRound < 0.5) {
        return (abs(d.x) <= 1.0 && abs(d.y) <= 1.0) ? 1.0 : 0.0;
    }
    float r = length(d);
    if (uSoft <= 0.0) {
        return r <= 1.0 ? 1.0 : 0.0;
    }
    return clamp((1.0 - r) / uSoft, 0.0, 1.0);
}

// How far light reaches at dist from its source, by its falloff (as the
// lighting's light.frag has it).
float falloff(float dist, float radius, float physical) {
    float t = 1.0 - dist / radius;
    if (physical < 0.5) {
        return t * t;
    }
    return 1.0 / (1.0 + 16.0 * dist * dist / (radius * radius)) *
        min(1.0, t * 4.0);
}

// The lights mirrored at p (local units), seen at an angle whose sine is
// s. Each light is six vectors:
//   (x, y, shape, body sigma) of its image in the mirror;
//   (r, g, b, strength);
//   (half across, half down, direction x, y) of its image's glowing part;
//   (the y it stands on, radius, direction x, y) as it is, unmirrored - a
//   cone's way, a tube's length;
//   (cos full, cos edge or a tube's half length, physical, its body's
//   strength as its source is drawn: no more than white, unexposed);
//   (spill, spill radius, how far in front of the street line it stands, 0):
//   what a cone's source throws all round.
// Its glowing body and the halo the haze makes round it are smeared up and
// down by the surface's roughness and across by that times s; the light it
// casts on what stands on the street (walls, the air) is mirrored too,
// worked out where the mirror puts the point back in the street.
vec3 lights(vec2 p, float s) {
    vec3 sum = vec3(0.0);
    float across = uSpread * s;
    float down = uSpread;
    for (int i = 0; i < kMaxLights; i++) {
        if (float(i) >= uLightCount) {
            break;
        }
        // Indexed by the loop's own counter: SkSL takes no other index.
        vec4 a = u[kLights + i * 6];
        vec4 c = u[kLights + i * 6 + 1];
        vec4 e = u[kLights + i * 6 + 2];
        vec4 g = u[kLights + i * 6 + 3];
        vec4 h = u[kLights + i * 6 + 4];
        vec4 k = u[kLights + i * 6 + 5];
        vec2 d = p - a.xy;
        vec2 half_;
        if (a.z > 2.5) {
            // A tube: from its nearest point along it.
            float t = clamp(dot(d, e.zw), -e.x, e.x);
            d -= e.zw * t;
            half_ = abs(e.zw) * e.x;
        } else if (a.z > 1.5) {
            // A window: from its nearest point, nothing inside it.
            d -= clamp(d, -e.xy, e.xy);
            half_ = e.xy;
        } else {
            half_ = vec2(0.0);
        }
        float bx = a.w;
        float by = a.w * uSquash;
        float sx2 = bx * bx + across * across;
        float sy2 = by * by + down * down;
        // A smear spreads the light out: dimmer by as much as wider, each
        // way.
        float wide = (half_.x + bx) / (half_.x + sqrt(sx2)) *
            ((half_.y + by) / (half_.y + sqrt(sy2)));
        float q = d.x * d.x / sx2 + d.y * d.y / sy2;
        float body = exp(-0.5 * q) * wide;
        // Nearly white at its heart, as the source itself is drawn.
        vec3 color = mix(c.rgb, vec3(1.0), 0.6 * exp(-q));
        // The halo: the source's glow in the wet air, as wide as the haze
        // makes it, and smeared the same.
        float hs = a.w * (6.0 + 24.0 * uHaze) / 2.5;
        float hx2 = hs * hs + across * across;
        float hy2 = hs * hs * uSquash * uSquash + down * down;
        float halo = uHaze * 0.6 *
            exp(-0.5 * (d.x * d.x / hx2 + d.y * d.y / hy2)) *
            (hs * hs * uSquash / sqrt(hx2 * hy2));
        sum += color * body * h.w + c.rgb * halo * c.w;

        // What it casts on the street, seen in the mirror: the point the
        // mirror shows here, back where it is on the street line, and the
        // light reaching it as the lighting works it out there (light.frag):
        // from where the light stands in front of the line, by how far, and
        // as steeply as it comes down.
        if (uAir > 0.0 && uAirMap < 0.5) {
            float base = g.x;
            vec2 w = vec2(p.x, base - (p.y - base) / uSquash);
            vec2 l = vec2(a.x, base - (a.y - base) / uSquash);
            vec2 v = w - l;
            if (a.z > 2.5) {
                v -= g.zw * clamp(dot(v, g.zw), -h.y, h.y);
            } else if (a.z > 1.5) {
                vec2 box = vec2(e.x, e.y / uSquash);
                v -= clamp(v, -box, box);
            }
            float dist = length(vec3(v, k.z));
            float reach = 0.0;
            if (dist < g.y) {
                float cone = 1.0;
                float across = length(v);
                if (a.z > 0.5 && a.z < 1.5 && across > 1e-6) {
                    // Its cone on the screen's plane, as light.frag has it.
                    float off = acos(clamp(dot(v, g.zw) / across, -1.0, 1.0));
                    float full = acos(clamp(h.x, -1.0, 1.0));
                    float edge = acos(clamp(h.y, -1.0, 1.0));
                    cone = 1.0 - smoothstep(full, max(edge, full + 1e-4), off);
                }
                float incidence = clamp(v.y / max(dist, 1e-6), 0.0, 1.0);
                reach = falloff(dist, g.y, h.z) * cone * incidence;
            }
            if (dist < k.y) {
                float ts = 1.0 - dist / k.y;
                reach = max(reach, k.x * ts * ts);
            }
            sum += c.rgb * (uAir * c.w * reach);
        }
    }
    return sum;
}

// The light in the air the lighting laid above the street, seen in the
// mirror at p: read from its buffer - a soft copy, half a metre across: light
// in the air has no edges, and a thin post throws no shadow in it - where the
// mirror puts p back, and smeared down by the surface's roughness as the
// street's reflection is (a sigma of uSpread, five taps).
vec3 airMirrored(vec2 p) {
    vec3 sum = vec3(0.0);
    for (int k = -2; k <= 2; k++) {
        float weight = k == 0 ? 6.0 : (k == 1 || k == -1 ? 4.0 : 1.0);
        float y = p.y + float(k) * uSpread;
        vec2 w = vec2(p.x, uLine - (y - uLine) / uSquash);
        sum += mirrored(w).rgb * weight;
    }
    return sum / 16.0;
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float water = pool(p);
    if (water <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    bool waves = uWave.x > 0.5;
    vec2 tilt = waves ? slope(p) : vec2(0.0);
    vec2 bend = ripple(p);
    if (waves) {
        // Many drops' waves add up under heavy rain; past a point the mirror
        // would be read from outside its image. uWave.w is a drop's ring at
        // about waveAmplitude, so no more than one and a half of those.
        bend = vec2(tilt.x, tilt.y * uFlatten) * uWave.w;
        float most = uWave.w * 0.15 * 1.5;
        float l = length(bend);
        if (l > most) {
            bend *= most / l;
        }
    }
    vec2 at = p + bend + chop(p);
    float s = mix(uElevTop, uElevBottom, clamp(p.y / uSize.y, 0.0, 1.0));
    float reflectance = uFresnel > 0.5 ? fresnel(s) : 1.0;
    float below = clamp((p.y - uLine) / max(uSize.y - uLine, 1.0), 0.0, 1.0);
    float shown = uGain * reflectance * (1.0 - uFade * below);
    if (uLightMode > 0.5) {
        vec3 light = lights(at, s);
        if (uAirMap > 0.5) {
            light += airMirrored(at) * uAir;
        }
        light *= shown * water;
        float most = max(light.r, max(light.g, light.b));
        fragColor = vec4(light, clamp(most, 0.0, 1.0));
        return;
    }
    // A rough surface smears a point into a column: down by uSpread (a
    // sigma), and across that times the sine of the angle it is seen at -
    // a thin streak far off, where the eye looks along the water, rounder
    // near. Taps a fraction of a sigma apart over an image rendered no
    // finer than that, read smooth: a blur, not copies.
    float down = uSpread;
    float across = uSpread * s;
    vec4 color;
    // Under half a pixel of smear is none.
    if (down * uPixels < 0.5) {
        color = mirrored(at);
    } else {
        int side = across * uPixels < 0.75 ? 0 : 2;
        vec4 sum = vec4(0.0);
        float total = 0.0;
        for (int j = -7; j <= 7; j++) {
            float y = float(j) * (2.0 / 7.0);
            float wy = exp(-0.5 * y * y);
            for (int k = -2; k <= 2; k++) {
                if (k < -side || k > side) {
                    continue;
                }
                float x = float(k) * 0.8;
                float w = wy * exp(-0.5 * x * x);
                sum += mirrored(at + vec2(x * across, y * down)) * w;
                total += w;
            }
        }
        color = sum / total;
    }
    vec4 mirror = color * shown;
    // The mirror over the water, the tint over both; all premultiplied.
    vec4 base = uBase;
    vec4 tint = uTint;
    vec4 c = mirror + base * (1.0 - clamp(mirror.a, 0.0, 1.0));
    c = tint + c * (1.0 - tint.a);
    // The wave crests catch the light.
    if (waves) {
        // A ring's crest, where it leans most: a drop's ring leans about
        // 0.1-0.3 as it spreads.
        float catchLight = smoothstep(0.01, 0.06, length(tilt)) * 0.6;
        c = uGlint * catchLight + c * (1.0 - uGlint.a * catchLight);
    }
    fragColor = c * water;
}
