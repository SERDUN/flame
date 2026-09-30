import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/src/reflection_pass.dart';
import 'package:flame_water/src/ripple_rings.dart';
import 'package:flame_water/src/water_shader.dart';

/// How a surface draws its reflection.
enum WaterQuality {
  /// The mirrored components drawn straight through the canvas: no offscreen
  /// render, rings drawn over a still reflection. Works everywhere.
  mirror,

  /// The mirror rendered into an image once a frame and drawn through the
  /// water shader, which bends it around every ring. Needs
  /// [WaterShader.load]; falls back to [mirror] until then.
  rippled,
}

/// The outline of a stretch of water inside its component's rectangle.
enum WaterShape {
  /// Fills the rectangle: a wet road, a pool seen edge on.
  rect,

  /// An ellipse in the rectangle: a puddle.
  ellipse,
}

/// A stretch of water that mirrors the world above it.
///
/// Everything [Reflectable] is drawn again upside down about [waterLine],
/// clipped to the water's [shape], squeezed by [squash] and faded with depth,
/// over the water's own [color] and under its [tint].
///
/// At [WaterQuality.mirror] no image of the scene is made: the reflected
/// components are drawn a second time through the canvas, so this costs draw
/// calls, not an offscreen render, and works on every renderer (the web
/// included). At [WaterQuality.rippled] the mirror is rendered into an image
/// of [resolution] pixels per unit and the water shader bends it around each
/// ring, [waveAmplitude] units at most, so drops visibly disturb what the
/// water shows.
///
/// Rain hitting it is [splash]ed into [ripples].
///
/// Under a `Lighting` it is a [LightMirror]: the world's glow (lamps, lit
/// windows, their halos) is mirrored in it through the same shader, so drops
/// bend a lamp's reflection as they bend the street's, and a rough surface
/// ([streak]) smears it down into a long broken streak, as a wet road does.
///
/// The surface must not be rotated or scaled, nor its parents: it maps world
/// coordinates to its own by its absolute top-left corner.
class WaterSurface extends PositionComponent with LightMirror {
  WaterSurface({
    super.position,
    super.size,
    super.anchor,
    super.priority,
    this.shape = WaterShape.ellipse,
    this.waterLine,
    this.color = const Color(0xFF2B3440),
    this.reflectivity = 0.6,
    this.squash = 1,
    this.fade = 0.8,
    this.tint = const Color(0x00000000),
    RippleRings? ripples,
    this.rippleColor = const Color(0x99FFFFFF),
    this.reflects = _isReflectable,
    this.quality = WaterQuality.rippled,
    this.resolution = 1,
    this.waveAmplitude = 3,
    double? wavelength,
    this.streak = 0,
    this.glowGain = 1.4,
  }) : ripples = ripples ?? RippleRings(),
       wavelength = wavelength ?? (ripples?.maxRadius ?? 24) * 0.4;

  static bool _isReflectable(Component c) => c is Reflectable;

  WaterShape shape;

  /// World y of the line the world is mirrored about; `null`: the surface's
  /// top edge. A puddle on a road lies below the line things stand on - set
  /// it to that line, and the feet meet their reflection.
  double? waterLine;

  /// The water under its reflection.
  Color color;

  /// How much of the world shows in it, `0..1`: a puddle on dark asphalt
  /// reflects a lot, a thin film on a road a little.
  double reflectivity;

  /// How tall a reflection is against what it reflects: 1 is a true mirror;
  /// below 1 squeezes it, as water seen at a low angle shows a shorter image.
  double squash;

  /// How much the reflection fades from the water line to the bottom of the
  /// surface, `0..1`.
  double fade;

  /// Laid over the reflection: water takes on its own colour.
  Color tint;

  final RippleRings ripples;

  /// Colour of the ripple rings.
  Color rippleColor;

  /// Which components the water mirrors, and with them everything under
  /// them. By default the [Reflectable] ones.
  bool Function(Component) reflects;

  WaterQuality quality;

  /// Pixels of the reflection image per local unit at
  /// [WaterQuality.rippled]: lower is cheaper and softer.
  double resolution;

  /// How far a ring shifts the reflection at its crest, local units.
  double waveAmplitude;

  /// Length of a ring's wave, local units.
  double wavelength;

  /// How far a rough surface smears its reflection down towards the
  /// viewer, local units: 0 still water, a clear mirror; a wet road smears a
  /// lamp into a streak many times its size. The mirrored street takes a
  /// tenth of it (a soft mirror), the glow all of it.
  double streak;

  /// How bright the mirrored glow comes out, against the glow itself.
  double glowGain;

  /// How much more water gives back of a light seen low across it than its
  /// [reflectivity] says: at a grazing angle it mirrors most of what falls
  /// on it (Fresnel), so a puddle shows a lamp nearly as bright as the lamp.
  static const double grazing = 1.6;

  @override
  void renderMirroredGlow(Canvas canvas, void Function(Canvas canvas) glow) {
    final strength = (reflectivity * grazing).clamp(0.0, 1.0);
    if (strength <= 0) {
      return;
    }
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = (waterLine ?? origin.y) - origin.y;
    canvas
      ..save()
      ..translate(origin.x, origin.y)
      ..clipPath(outline());
    final program = WaterShader.program;
    if (quality == WaterQuality.rippled && program != null) {
      _throughShader(
        canvas,
        _glowSlot,
        program,
        rect,
        (c) => _mirror(c, line, origin, () => glow(c)),
        streak: streak,
        gain: strength * glowGain,
        paint: _glowPaint,
      );
    } else {
      canvas.saveLayer(
        rect,
        _glowLayer..color = Color.fromRGBO(0, 0, 0, strength),
      );
      _mirror(canvas, line, origin, () => glow(canvas));
      canvas.restore();
    }
    canvas.restore();
  }

  final _ShaderSlot _sceneSlot = _ShaderSlot();
  final _ShaderSlot _glowSlot = _ShaderSlot();
  final Paint _shaderPaint = Paint();
  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _glowLayer = Paint()..blendMode = BlendMode.plus;

  final Paint _water = Paint();
  final Paint _layer = Paint();
  final Paint _fadePaint = Paint()..blendMode = BlendMode.dstIn;
  final Paint _tintPaint = Paint();
  final Paint _ripplePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  /// The water's outline in its own coordinates.
  Path outline() {
    final rect = size.toRect();
    return switch (shape) {
      WaterShape.rect => Path()..addRect(rect),
      WaterShape.ellipse => Path()..addOval(rect),
    };
  }

  /// Starts a ripple where a drop hit, [worldPoint] in world coordinates.
  void splash(Vector2 worldPoint, {double strength = 1}) {
    final origin = absoluteTopLeftPosition;
    ripples.add(
      worldPoint.x - origin.x,
      worldPoint.y - origin.y,
      strength: strength,
    );
  }

  /// Whether [worldPoint] lies on the water.
  bool covers(Vector2 worldPoint) {
    final origin = absoluteTopLeftPosition;
    return outline().contains(
      Offset(worldPoint.x - origin.x, worldPoint.y - origin.y),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    ripples.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = (waterLine ?? origin.y) - origin.y;
    final outline = this.outline();
    canvas
      ..save()
      ..clipPath(outline)
      ..drawPath(outline, _water..color = color);

    if (reflectivity > 0) {
      canvas.saveLayer(
        rect,
        _layer..color = Color.fromRGBO(0, 0, 0, reflectivity.clamp(0.0, 1.0)),
      );
      final program = WaterShader.program;
      void scene(Canvas c) => _mirror(
        c,
        line,
        origin,
        () => ReflectionPass.run(this, () => _renderReflected(_root(), c)),
      );
      if (quality == WaterQuality.rippled && program != null) {
        _throughShader(
          canvas,
          _sceneSlot,
          program,
          rect,
          scene,
          streak: streak * 0.1,
          gain: 1,
          paint: _shaderPaint,
        );
      } else {
        canvas.save();
        scene(canvas);
        canvas.restore();
      }
      if (fade > 0) {
        _fadePaint.shader = Gradient.linear(
          Offset(0, line),
          Offset(0, rect.bottom),
          [
            const Color(0xFFFFFFFF),
            Color.fromRGBO(255, 255, 255, 1 - fade.clamp(0.0, 1.0)),
          ],
        );
        canvas.drawRect(rect, _fadePaint);
      }
      canvas.restore();
    }

    if (tint.a > 0) {
      canvas.drawRect(rect, _tintPaint..color = tint);
    }
    ripples.render(canvas, _ripplePaint..color = rippleColor);
    canvas.restore();
  }

  /// Sets [canvas] (in the surface's own coordinates) to mirror the world
  /// about the water line, squeezed, and runs [draw] there, in world
  /// coordinates.
  void _mirror(
    Canvas canvas,
    double line,
    Vector2 origin,
    void Function() draw,
  ) {
    canvas
      ..translate(0, line)
      ..scale(1, -squash)
      ..translate(-origin.x, -origin.y - line);
    draw();
  }

  /// [record] (drawing in the surface's own coordinates) rendered into an
  /// image and drawn over [rect] through the water shader: bent around the
  /// newest rings, smeared [streak] down, at [gain] brightness.
  void _throughShader(
    Canvas canvas,
    _ShaderSlot slot,
    FragmentProgram program,
    Rect rect,
    void Function(Canvas canvas) record, {
    required double streak,
    required double gain,
    required Paint paint,
  }) {
    final width = (size.x * resolution).ceil();
    final height = (size.y * resolution).ceil();
    if (width <= 0 || height <= 0) {
      return;
    }
    final recorder = PictureRecorder();
    record(Canvas(recorder)..scale(resolution));
    final picture = recorder.endRecording();
    slot.image?.dispose();
    final image = slot.image = picture.toImageSync(width, height);
    picture.dispose();

    final shader = slot.shader ??= program.fragmentShader();
    var count = 0;
    shader.setFloatUniforms((u) {
      u
        ..setVector(size)
        ..setFloat(0) // the ring count, set below
        ..setFloat(ripples.flatten)
        ..setFloat(wavelength)
        ..setFloat(streak)
        ..setFloat(gain);
      ripples.forEachNewest(WaterShader.maxRings, (x, y, radius, opacity) {
        u.setFloats([x, y, radius, waveAmplitude * opacity]);
        count++;
      });
      for (var i = count; i < WaterShader.maxRings; i++) {
        u.setFloats(const [0, 0, 0, 0]);
      }
    });
    shader
      ..setFloat(2, count.toDouble())
      ..setImageSampler(0, image);
    canvas.drawRect(rect, paint..shader = shader);
  }

  @override
  void onRemove() {
    _sceneSlot.dispose();
    _glowSlot.dispose();
    super.onRemove();
  }

  Component _root() {
    Component top = this;
    for (final a in ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top;
  }

  /// Draws what [parent] holds that the water reflects: a reflected component
  /// with all it holds; any other one only as a way down to its children,
  /// with its transform. Water surfaces are never reflected.
  void _renderReflected(Component parent, Canvas canvas) {
    for (final child in parent.children) {
      if (child is WaterSurface) {
        continue;
      }
      if (reflects(child)) {
        if (_beside(child)) {
          child.renderTree(canvas);
        }
        continue;
      }
      if (child.children.isEmpty) {
        continue;
      }
      if (child is PositionComponent) {
        canvas
          ..save()
          ..transform2D(child.transform);
        _renderReflected(child, canvas);
        canvas.restore();
      } else {
        _renderReflected(child, canvas);
      }
    }
  }

  /// Whether [c] stands where its reflection can reach the water: anything
  /// that is not placed on the plane may; a placed one only if it overlaps
  /// the water across.
  bool _beside(Component c) {
    if (c is! PositionComponent) {
      return true;
    }
    final r = c.toAbsoluteRect();
    final origin = absoluteTopLeftPosition;
    return r.right >= origin.x && r.left <= origin.x + size.x;
  }
}

/// One image the water renders a reflection into each frame, and the shader
/// instance that draws it (each draw keeps its own uniforms).
class _ShaderSlot {
  Image? image;
  FragmentShader? shader;

  void dispose() {
    image?.dispose();
    image = null;
  }
}
