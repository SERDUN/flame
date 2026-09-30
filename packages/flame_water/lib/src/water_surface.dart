import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_water/src/rain.dart';
import 'package:flame_water/src/rain_catcher.dart';
import 'package:flame_water/src/reflection_pass.dart';
import 'package:flame_water/src/ripple_rings.dart';
import 'package:flame_water/src/water_shader.dart';
import 'package:flame_water/src/wettable.dart';

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
class WaterSurface extends PositionComponent
    with LightMirror, RainCatcher, Wettable {
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
    this.depth = 1,
    this.edgeSoftness = 0.35,
    RippleRings? ripples,
    this.rippleColor = const Color(0x99FFFFFF),
    this.reflects = _isReflectable,
    this.quality = WaterQuality.rippled,
    this.resolution = 1,
    double? waveAmplitude,
    double? wavelength,
    this.streak = 0,
    this.chopPerRain = 0,
    this.film = false,
    this.glowGain = 4,
    double wetness = 1,
  }) : ripples = ripples ?? RippleRings.forDepth(depth),
       waveAmplitude = waveAmplitude ?? 1.5 + 3.5 * depth.clamp(0.0, 1.0),
       wavelength =
           wavelength ??
           (ripples ?? RippleRings.forDepth(depth)).maxRadius * 0.4 {
    // A film starts as wet as the scene says; standing water is water.
    this.wetness = wetness;
  }

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

  /// How gently a puddle fades out at its rim, `0..1`: the share of its
  /// radius over which the water thins to nothing. 0 a hard line. Only an
  /// [WaterShape.ellipse] fades: a rect is a road, and its edge is the
  /// road's.
  double edgeSoftness;

  /// How much water lies here, `0..1`: 0 a film on asphalt, 1 a puddle.
  /// Drops break on all of it; the deeper, the wider, slower and plainer
  /// the rings they leave and the more those bend the reflection - unless
  /// [ripples] and [waveAmplitude] are given outright.
  final double depth;

  final RippleRings ripples;

  /// Colour of the ripple rings at full depth; shallower water shows them
  /// fainter.
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

  /// How far a rough surface smears its reflection up and down, local units
  /// (the spread of a vertical blur): 0 still water, a clear mirror; a wet
  /// road smears a lamp into a streak many times its size, and the street
  /// with it - the same roughness for everything it mirrors. Water on a road
  /// mirrors as much as a puddle does; only how rough it lies differs.
  double streak;

  /// How far the restless chop the world's [Rain] keeps on the surface
  /// shifts what it mirrors, local units per unit of rain intensity: 0
  /// still water; on a road in the rain it breaks every reflection into
  /// wavering bands, stronger the harder it rains. Drawn by the water
  /// shader, so only at [WaterQuality.rippled].
  double chopPerRain;

  /// The chop now, from the rain over the world.
  double get chop => chopPerRain * (Rain.of(this)?.intensity ?? 0);

  /// A film of water on the ground rather than standing water: it comes as
  /// the ground gets wet ([wetness]) and goes as it dries, mirroring only as
  /// much as it is wet. A puddle is not a film: it is water all the time.
  bool film;

  /// How much it mirrors now: [reflectivity], times its wetness for a film.
  double get _shown => film ? reflectivity * wetness : reflectivity;

  // Rain lands on it: at its depth on the ground, if the water covers that
  // spot; a deeper water takes a drop from a shallower one under it.

  @override
  double? catchDrop(double x, double fromY, double toY, double depth) {
    if (depth < 0) {
      // Rain behind the street line never reaches water on the ground.
      return null;
    }
    final origin = absoluteTopLeftPosition;
    final band =
        Ground.of(this)?.groundBand() ??
        Rect.fromLTWH(origin.x, origin.y, size.x, size.y);
    final y = band.top + 4 + depth * (band.height - 8);
    if (y <= fromY || y > toY || !covers(Vector2(x, y))) {
      return null;
    }
    return y;
  }

  @override
  int get catchOrder => (depth * 100).round();

  @override
  void onDrop(Vector2 at, double strength) => splash(at, strength: strength);

  double _time = 0;

  /// How much brighter than the screen's white a light's source is. The
  /// glow is mirrored through an image that stops at white, so a lamp
  /// smeared thin over a rough surface would fade to nothing; this gives it
  /// back its real brightness. A property of the lights, the same for every
  /// surface: a still puddle shows the lamp burnt out white, a rough road a
  /// bright streak. Only the sources: the light the haze scatters round
  /// them comes back as bright as it is.
  double glowGain;

  /// How much more water gives back of a light seen low across it than its
  /// [reflectivity] says: at a grazing angle it mirrors most of what falls
  /// on it (Fresnel), so a puddle shows a lamp nearly as bright as the lamp.
  static const double grazing = 1.6;

  @override
  void renderMirroredGlow(
    Canvas canvas,
    void Function(Canvas canvas, double headroom) glow,
  ) {
    final strength = (_shown * grazing).clamp(0.0, 1.0);
    if (strength <= 0) {
      return;
    }
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = (waterLine ?? origin.y) - origin.y;
    canvas
      ..save()
      ..translate(origin.x, origin.y);
    _openArea(canvas, rect, _glowArea);
    final program = WaterShader.program;
    if (quality == WaterQuality.rippled && program != null) {
      _throughShader(
        canvas,
        _glowSlot,
        program,
        rect,
        (c) => _smeared(
          c,
          streak,
          () => _mirror(c, line, origin, () => glow(c, glowGain)),
        ),
        gain: strength * glowGain,
        paint: _glowPaint,
      );
    } else {
      canvas.saveLayer(
        rect,
        _glowLayer..color = Color.fromRGBO(0, 0, 0, strength),
      );
      _smeared(
        canvas,
        streak,
        () => _mirror(canvas, line, origin, () => glow(canvas, 1)),
      );
      canvas.restore();
    }
    // The rings' crests glint with the light round them - bright by a lamp,
    // faint but there in the dark, lit by the sky.
    final lighting = Lighting.current;
    ripples.render(
      canvas,
      _ringPaint(),
      lightAt: lighting == null
          ? null
          : (x, y) =>
                0.35 +
                lighting.lightAt(Vector2(origin.x + x, origin.y + y)).light,
    );
    _litLastFrame = true;
    _closeArea(canvas, rect);
    canvas.restore();
  }

  /// Whether a Lighting drew the rings with the glow last frame.
  bool _litLastFrame = false;

  /// The rings' paint: [rippleColor], plainer the more water there is - and
  /// the wetter it is (barely wet asphalt hardly shows a ring).
  Paint _ringPaint() {
    final plain = (0.5 + 0.5 * depth.clamp(0.0, 1.0)) * wetness.clamp(0.0, 1.0);
    return _ripplePaint
      ..color = rippleColor.withValues(alpha: rippleColor.a * plain);
  }

  /// Runs [draw] blurred up and down by [spread]: a rough surface mirrors
  /// every point over a range of heights. A real blur, continuous - not
  /// copies of the point at steps.
  void _smeared(Canvas canvas, double spread, void Function() draw) {
    if (spread < 0.5) {
      canvas.save();
      draw();
      canvas.restore();
      return;
    }
    canvas.saveLayer(
      null,
      _smear
        ..imageFilter = ImageFilter.blur(
          sigmaX: 0.6,
          sigmaY: spread / 3,
          tileMode: TileMode.decal,
        ),
    );
    draw();
    canvas.restore();
  }

  final _ShaderSlot _sceneSlot = _ShaderSlot();
  final _ShaderSlot _glowSlot = _ShaderSlot();
  final Paint _shaderPaint = Paint();
  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _glowLayer = Paint()..blendMode = BlendMode.plus;
  final Paint _smear = Paint();
  final Paint _area = Paint();
  final Paint _glowArea = Paint()..blendMode = BlendMode.plus;
  final Paint _edgeMask = Paint()..blendMode = BlendMode.dstIn;

  final Paint _water = Paint();
  final Paint _layer = Paint();
  final Paint _fadePaint = Paint()..blendMode = BlendMode.dstIn;
  final Paint _tintPaint = Paint();
  final Paint _ripplePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  /// How much of its shape a pool fills now: standing water shrinks as the
  /// ground dries - a puddle on barely wet ground is a small dark patch.
  /// A film always covers its ground; its wetness shows in its mirror.
  double get _fill => film ? 1 : 0.3 + 0.7 * wetness.clamp(0.0, 1.0);

  /// The water's outline in its own coordinates.
  Path outline() {
    final whole = size.toRect();
    final rect = Rect.fromCenter(
      center: whole.center,
      width: whole.width * _fill,
      height: whole.height * _fill,
    );
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
    _time += dt;
    ripples.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = (waterLine ?? origin.y) - origin.y;
    final outline = this.outline();
    _openArea(canvas, rect, _area);
    canvas.drawPath(outline, _water..color = color);

    if (_shown > 0) {
      canvas.saveLayer(
        rect,
        _layer..color = Color.fromRGBO(0, 0, 0, _shown.clamp(0.0, 1.0)),
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
          (c) => _smeared(c, streak, () => scene(c)),
          gain: 1,
          paint: _shaderPaint,
        );
      } else {
        _smeared(canvas, streak, () => scene(canvas));
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
    // Under a Lighting the rings are glints over the night, drawn with the
    // glow; without one they are drawn here.
    final lit = _litLastFrame;
    _litLastFrame = false;
    if (!lit) {
      ripples.render(canvas, _ringPaint());
    }
    _closeArea(canvas, rect);
  }

  bool get _softEdge => shape == WaterShape.ellipse && edgeSoftness > 0;

  /// Opens the water's area on [canvas] (in the surface's coordinates):
  /// clipped hard to its outline, or a layer landing with [layer]'s blend,
  /// whose rim [_closeArea] fades out.
  void _openArea(Canvas canvas, Rect rect, Paint layer) {
    if (_softEdge) {
      canvas.saveLayer(rect, layer);
    } else {
      canvas
        ..save()
        ..clipPath(outline());
    }
  }

  /// Closes what [_openArea] opened; a soft edge first fades the water out
  /// towards its rim - over the whole rectangle, so nothing outside the
  /// ellipse stays.
  void _closeArea(Canvas canvas, Rect rect) {
    if (_softEdge) {
      // The water as it stands now: a drying pool is smaller than its rect.
      final pool = outline().getBounds();
      final soft = edgeSoftness.clamp(0.0, 1.0);
      _edgeMask.shader = Gradient.radial(
        Offset.zero,
        1,
        const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        [0, 1 - soft, 1],
      );
      canvas
        ..save()
        ..translate(pool.center.dx, pool.center.dy)
        ..scale(pool.width / 2, pool.height / 2)
        // Over the whole rectangle, in the pool's own scale: past the pool's
        // rim the mask is clear, so nothing outside it stays.
        ..drawRect(
          Rect.fromLTRB(
            (rect.left - pool.center.dx) / (pool.width / 2) - 0.01,
            (rect.top - pool.center.dy) / (pool.height / 2) - 0.01,
            (rect.right - pool.center.dx) / (pool.width / 2) + 0.01,
            (rect.bottom - pool.center.dy) / (pool.height / 2) + 0.01,
          ),
          _edgeMask,
        )
        ..restore();
    }
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
  /// newest rings, at [gain] brightness.
  void _throughShader(
    Canvas canvas,
    _ShaderSlot slot,
    FragmentProgram program,
    Rect rect,
    void Function(Canvas canvas) record, {
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
        ..setFloat(gain)
        ..setFloat(_time)
        ..setFloat(chop);
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
