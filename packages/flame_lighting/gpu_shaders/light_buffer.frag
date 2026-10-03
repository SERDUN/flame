#version 320 es

// Every light of a frame, added up once into a float target: what each
// pixel of the view gets of them, brighter than white where it is.
//
// rgb: the light cast, each light's colour times how much of it arrives
// (shape, falloff, cone, the spill round a cone's source, on the ground
// the angle it comes in at, the shadows on its way).
// a: what glows there itself, as white light: the halo the haze makes
// round each source, and the source itself - a bulb, a lit pane, a tube -
// at as much as lets it show as bright as it is drawn once the eye's
// exposure is applied.
//
// The same light as light.frag works out for one light on the canvas path,
// and LightField.reach on the CPU.

precision highp float;

#include "shaders/light_math.glsl"

const int kMaxLights = 16;
const int kMaxShadows = 24;
// Samples of the ground's height across the band (GroundLift), four a vec4.
const int kLift = 8;

const float kCone = 1.0;
const float kArea = 2.0;
const float kLine = 3.0;
const float kSun = 4.0;
// As far as LightField.sunDistance.
const float kSunDistance = 1e5;

uniform Params {
  vec4 view;      // the world rect the target covers: left, top, width, height
  vec4 street;    // band top, band height, near distance, far distance
  vec4 info;      // eye height, lights in use, capsules in use, haze
  vec4 look;      // the eye's exposure, the wall plane's distance in front
                  // of the street line (behind it, negative), the depth of
                  // air the light fills (0: it falls on surfaces), how far
                  // one sees through it (Koschmieder), the world's units
  vec4 lights[kMaxLights * 5];   // LightField.writeLight's five vectors each
  vec4 capsules[kMaxShadows * 2];
  vec4 lift[kLift];   // the ground's height across the band, world units up
  vec4 liftSpan;      // the band's left and right, samples in use (0: level)
} params;

// How high the ground stands at world x: its hill there.
float liftAt(float x) {
  float n = params.liftSpan.z;
  if (n < 1.5) {
    return 0.0;
  }
  float u = clamp((x - params.liftSpan.x) /
                      max(params.liftSpan.y - params.liftSpan.x, 1e-6),
                  0.0, 1.0) * (n - 1.0);
  int i = int(min(floor(u), n - 2.0));
  float t = u - float(i);
  float a = params.lift[i / 4][i % 4];
  float b = params.lift[(i + 1) / 4][(i + 1) % 4];
  return mix(a, b, t);
}

in vec2 v_uv;
out vec4 frag_color;

float aheadAt(float d) {
  float inverse = max(1.0 / params.street.w +
                          d * (1.0 / params.street.z - 1.0 / params.street.w),
                      0.05 / params.street.w);
  return params.street.w - 1.0 / inverse;
}

// How much light gets from l to p past every capsule (ShadowSet.through).
float through(vec3 l, vec3 p, float source) {
  float light = 1.0;
  int count = int(params.info.z);
  for (int i = 0; i < kMaxShadows; i++) {
    if (i >= count) {
      break;
    }
    vec4 seg = params.capsules[i * 2];
    vec4 info = params.capsules[i * 2 + 1];
    float radius = info.x;
    float cz = info.y;
    float slab = info.z * 0.5;
    // Near either end of the way, as a share of it: a capsule's radius, no
    // more than 2 % (ShadowSet.through).
    float end = min(0.02, radius / max(length(p - l), 1e-9));
    // The part of the way through the capsule's depth, then the nearest it
    // comes to the capsule on screen; from the point back, for precision.
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
    vec2 nearest = segments(p.xy - e.xy * (1.0 - t0), p.xy - e.xy * (1.0 - t1),
                            seg.xy, seg.zw);
    float t = t0 + (t1 - t0) * nearest.x;
    float dist = nearest.y;
    float blur = max(source * (1.0 - t), radius * 1e-3);
    float s = clamp((dist - radius) / blur + 0.5, 0.0, 1.0);
    float visible = s * s * (3.0 - 2.0 * s);
    // In the air a capsule darkens the eye's way only over its own depth.
    float share = params.look.z > 0.0 ? min(1.0, 2.0 * slab / params.look.z)
                                      : 1.0;
    light *= 1.0 - info.w * share * (1.0 - visible);
  }
  return light;
}

// The air's share of the glow [lit] makes (airShareOf), in this pass's air.
float airShare(float lit) {
  return airShareOf(lit, params.look.z, params.look.w);
}

void main() {
  vec2 frag = params.view.xy + v_uv * params.view.zw;
  // Above the street line, the wall plane at its distance; below it, the
  // ground at the depth of its row.
  // The hill here: the street line and the ground in front of it raised.
  float lift = liftAt(frag.x);
  bool ground = params.street.y > 0.0 && frag.y > params.street.x - lift;
  vec3 p = vec3(frag, params.look.y);
  if (ground) {
    float depth = clamp((frag.y + lift - params.street.x) / params.street.y, 0.0, 1.0);
    p.z = aheadAt(depth);
  }
  vec3 sum = vec3(0.0);
  float glows = 0.0;
  float exposure = max(params.look.x, 1e-6);
  int count = int(params.info.y);
  float haze = params.info.w;
  for (int i = 0; i < kMaxLights; i++) {
    if (i >= count) {
      break;
    }
    vec4 a = params.lights[i * 5];
    vec4 c = params.lights[i * 5 + 1];
    vec4 g = params.lights[i * 5 + 2];
    vec4 h = params.lights[i * 5 + 3];
    vec4 k = params.lights[i * 5 + 4];
    vec2 pos = a.xy;
    float shape = a.w;
    float strength = c.a;
    if (abs(shape - kSun) < 0.5) {
      // The sun: from far off along its way, everywhere; on the ground as
      // steeply as it comes down, on the house fronts as much as it comes
      // from the eye's side.
      vec3 way = vec3(g.yz, a.z);
      vec3 from = p - way * kSunDistance;
      float facing = ground ? max(way.y, 0.0) : max(-way.z, 0.0);
      float lit = params.info.z > 0.5 ? through(from, p, h.w) : 1.0;
      sum += c.rgb * strength * facing * lit;
      continue;
    }
    // The nearest point of what glows.
    vec2 e = pos;
    if (abs(shape - kArea) < 0.5) {
      vec2 halfSize = h.yz * 0.5;
      e = clamp(p.xy, pos - halfSize, pos + halfSize);
    } else if (abs(shape - kLine) < 0.5) {
      float along = clamp(dot(p.xy - pos, g.yz), -h.y * 0.5, h.y * 0.5);
      e = pos + g.yz * along;
    }
    vec3 l = vec3(e, a.z);
    vec3 v = p - l;
    float dist = length(v);
    float radius = g.x;
    float spillRadius = k.x > 0.0 ? k.y : 0.0;
    float reach = 0.0;
    float lit = 0.0;
    if (dist < radius) {
      // The falloff: smooth, or physical (k.z).
      float fall = lightFall(dist, radius, k.z);
      float cone = abs(shape - kCone) < 0.5 ? coneAt(v.xy, g.yz, g.w, h.x) : 1.0;
      reach = fall * cone;
      if (params.look.z > 0.0) {
        // The air: the light summed along the eye's way past it.
        lit = cone * glowLength(dist, radius, k.z);
      }
    }
    if (dist < spillRadius) {
      float ts = 1.0 - dist / spillRadius;
      reach = max(reach, k.x * ts * ts);
      if (params.look.z > 0.0) {
        lit = max(lit, k.x * glowLength(dist, spillRadius, 0.0));
      }
    }
    if (reach > 0.0) {
      float incidence = 1.0;
      if (ground) {
        incidence = dist < 1e-3 ? 1.0 : clamp(v.y / dist, 0.0, 1.0);
      }
      float shade = params.info.z > 0.5 ? through(l, p, h.w) : 1.0;
      // In the air its light summed along the eye's way; on a surface as it
      // falls there.
      float amount = params.look.z > 0.0
          ? strength * shade * airShare(lit)
          : strength * reach * incidence * shade;
      sum += c.rgb * amount;
    }
    // What glows itself shows as bright as it is drawn.
    float source = h.w;
    float itself = 0.0;
    if (abs(shape - kArea) < 0.5) {
      vec2 d = abs(frag - pos) - h.yz * 0.5;
      itself = (d.x <= 0.0 && d.y <= 0.0) ? 1.0 : 0.0;
    } else if (abs(shape - kLine) < 0.5) {
      float along = clamp(dot(frag - pos, g.yz), -h.y * 0.5, h.y * 0.5);
      float width = max(source, h.y * 0.02);
      itself = length(frag - (pos + g.yz * along)) <= width * 0.5 ? 1.0 : 0.0;
    } else if (source > 0.0) {
      // As the bulb is drawn (bulbItself), over 1.6 source radii.
      itself = bulbItself(length(frag - pos) / (source * 1.6));
    }
    glows += itself / exposure;
    // The halo the haze makes round its source.
    if (haze > 0.0 && source > 0.0) {
      float r = length(frag - pos) / haloRadius(source, haze);
      // A share of the source as it is drawn, unexposed like it: the
      // halo never outshines what it is the halo of.
      glows += haze * min(strength, 1.0) * 0.6 * halo(r) / exposure;
    }
  }
  frag_color = vec4(sum, glows);
}
