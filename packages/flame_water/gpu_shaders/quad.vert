#version 320 es

// A triangle over the whole target; the uv runs 0..1 across it and 0..1 down
// it, as the target's rows are stored: NDC y points up, a texture's first row
// is its top. With uv up, every step read the field upside down, and the
// part of a wave that is not symmetric top to bottom changed sign each step
// and grew without bound.
in vec2 position;
out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position, 0.0, 1.0);
}
