#version 320 es

// One step of the wave equation over a water's surface: each cell's next
// height is the mean of its neighbours' now, less its own a step ago, damped.
// Drops landing this step push the surface down under them.

precision highp float;

const int kMaxDrops = 16;

uniform sampler2D prev_tex;
uniform sampler2D curr_tex;

uniform Params {
  vec4 texel_damping;      // texel x, texel y, damping, drops in use
  vec4 drops[kMaxDrops];   // uv x, uv y, radius (in x texels), depth
} params;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  vec2 t = params.texel_damping.xy;
  float n = texture(curr_tex, v_uv + vec2(t.x, 0.0)).r +
            texture(curr_tex, v_uv - vec2(t.x, 0.0)).r +
            texture(curr_tex, v_uv + vec2(0.0, t.y)).r +
            texture(curr_tex, v_uv - vec2(0.0, t.y)).r;
  float next = (n * 0.5 - texture(prev_tex, v_uv).r) * params.texel_damping.z;
  int count = int(params.texel_damping.w);
  for (int i = 0; i < kMaxDrops; i++) {
    if (i >= count) {
      break;
    }
    vec4 drop = params.drops[i];
    // Cells are square on the water: distance in x texels both ways.
    vec2 d = (v_uv - drop.xy) / t;
    float r = drop.z;
    float k = dot(d, d) / (r * r);
    if (k < 1.0) {
      // A smooth dent: a sharp-edged one rings on the grid's four
      // directions and shows as a star.
      float s = 1.0 - k;
      next -= drop.w * s * s;
    }
  }
  frag_color = vec4(next, 0.0, 0.0, 1.0);
}
