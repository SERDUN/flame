import 'dart:math' as math;
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
    this.reflectivity = 1,
    this.squash = 1,
    this.fade = 0.8,
    this.tint = const Color(0x00000000),
    this.depth = 1,
    this.edgeSoftness = 0.35,
    RippleRings? ripples,
    this.rippleColor = const Color(0x99FFFFFF),
    this.rippleWidth = 1.2,
    this.reflects = _isReflectable,
    this.quality = WaterQuality.rippled,
    this.resolution = 1,
    double? waveAmplitude,
    double? wavelength,
    this.streak = 0,
    this.chopPerRain = 0,
    this.film = false,
    this.glowGain = 10,
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

  /// World y of the line the world is mirrored about; `null`: the line
  /// things stand on - the top of the world's [Ground] - or, with no
  /// ground, the surface's top edge. A puddle on a road lies below that
  /// line and still mirrors about it, so feet meet their reflection;
  /// something standing elsewhere says so itself
  /// (`Reflectable.reflectionBase`).
  double? waterLine;

  /// The line the world is mirrored about now, world y.
  double get _line =>
      waterLine ??
      Ground.of(this)?.groundBand().top ??
      absoluteTopLeftPosition.y;

  /// The water under its reflection.
  Color color;

  /// How much of it is clear water, `0..1`: 1 still water, less a film
  /// broken by the asphalt poking through. How much clear water mirrors is
  /// water's own - most of the light seen low across it, little seen from
  /// above (Fresnel) - and follows from the world's [Ground], the angle each
  /// row of it is seen at.
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

  /// Water dries as long as it is deep: a film on the asphalt goes at the
  /// usual rate, a puddle ten times as deep takes ten times as long. Unless
  /// set outright.
  @override
  double get dryRate => _dryRate ?? 0.002 / math.max(depth, 0.1);

  @override
  set dryRate(double value) => _dryRate = value;
  double? _dryRate;

  final RippleRings ripples;

  /// Colour of the ripple rings at full depth; shallower water shows them
  /// fainter.
  Color rippleColor;

  /// How thick a ring's line is, world units: 1.2 in pixels, 1.2 cm in a
  /// world measured in metres.
  double rippleWidth;

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

  /// How much it mirrors now: [reflectivity]; a film only once it has
  /// formed ([wetGloss]) - wet asphalt is dark before it is a mirror.
  double get _shown => film ? reflectivity * wetGloss : reflectivity;

  // Rain lands on it: at its depth on the ground, if the water covers that
  // spot; a deeper water takes a drop from a shallower one under it.

  @override
  double? catchDrop(double x, double fromY, double toY, double depth) {
    if (depth < 0) {
      // Rain behind the street line never reaches water on the ground.
      return null;
    }
    // Where a drop at its depth meets the ground: the world's projection, or
    // with no ground, across this water from its top to its bottom.
    final origin = absoluteTopLeftPosition;
    final y =
        Ground.of(this)?.yAt(depth) ?? origin.y + depth.clamp(0, 1) * size.y;
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

  /// How the eye sees this water, from the world's [Ground]: the sine of
  /// the angle it looks down at its top and bottom rows. `null` without a
  /// ground: then it mirrors evenly, as much as [reflectivity] says.
  ({double top, double bottom})? _view() {
    final ground = Ground.of(this);
    if (ground == null) {
      return null;
    }
    final origin = absoluteTopLeftPosition;
    return (
      top: ground.sinElevation(ground.depthAt(origin.y)),
      bottom: ground.sinElevation(ground.depthAt(origin.y + size.y)),
    );
  }

  /// Water's reflectance where it is seen at its middle: what a surface
  /// drawn without the shader mirrors all over.
  double _meanReflectance(({double top, double bottom})? view) =>
      view == null ? 1 : Ground.fresnel((view.top + view.bottom) / 2);

  @override
  void renderMirroredGlow(
    Canvas canvas,
    void Function(Canvas canvas, double headroom) glow,
  ) {
    final strength = _shown.clamp(0.0, 1.0);
    if (strength <= 0 || _dry) {
      return;
    }
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = _line - origin.y;
    canvas
      ..save()
      ..translate(origin.x, origin.y);
    final program = WaterShader.program;
    final shaded = quality == WaterQuality.rippled && program != null;
    if (shaded) {
      // The shader smears it, fades it at the rim and adds it: no layers.
      _throughShader(
        canvas,
        _glowSlot,
        program,
        rect,
        (c) => _mirror(c, line, origin, () => glow(c, glowGain)),
        gain: strength * glowGain,
        paint: _glowPaint,
      );
      canvas.clipPath(outline());
    } else {
      _openArea(canvas, rect, _glowArea);
      canvas.saveLayer(
        rect,
        _glowLayer
          ..color = Color.fromRGBO(
            0,
            0,
            0,
            strength * _meanReflectance(_view()),
          ),
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
    if (!shaded) {
      _closeArea(canvas, rect);
    }
    canvas.restore();
  }

  /// Whether a Lighting drew the rings with the glow last frame.
  bool _litLastFrame = false;

  /// The rings' paint: [rippleColor], plainer the more water there is - and
  /// the wetter it is (barely wet asphalt hardly shows a ring).
  Paint _ringPaint() {
    final plain = (0.5 + 0.5 * depth.clamp(0.0, 1.0)) * wetness.clamp(0.0, 1.0);
    return _ripplePaint
      ..strokeWidth = rippleWidth
      ..color = rippleColor.withValues(alpha: rippleColor.a * plain);
  }

  /// Runs [draw] blurred up and down by [spread]: a rough surface mirrors
  /// every point over a range of heights. A real blur, continuous - not
  /// copies of the point at steps.
  void _smeared(Canvas canvas, double spread, void Function() draw) {
    if (spread * resolution < 0.5) {
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
  final Paint _ripplePaint = Paint()..style = PaintingStyle.stroke;

  /// How much of its shape a pool fills now, across: standing water
  /// shrinks as the ground dries - its area goes with the water in it, so
  /// on barely wet ground a puddle is a small patch, and on dry ground there
  /// is none. A film always covers its ground; its wetness shows in its
  /// mirror.
  double get _fill => film ? 1 : math.sqrt(wetness.clamp(0.0, 1.0));

  /// Whether there is any water to draw.
  bool get _dry => film ? _shown <= 0 : _fill <= 0;

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
    if (!film && _dry) {
      return;
    }
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    final line = _line - origin.y;
    final outline = this.outline();
    final program = WaterShader.program;
    if (quality == WaterQuality.rippled && program != null && _shown > 0) {
      // The water, its mirror, its tint and its rim, all in the shader: one
      // draw, no layers.
      _throughShader(
        canvas,
        _sceneSlot,
        program,
        rect,
        (c) => _mirror(
          c,
          line,
          origin,
          () => ReflectionPass.run(this, () => _renderReflected(_root(), c)),
        ),
        gain: _shown.clamp(0.0, 1.0),
        paint: _shaderPaint,
        base: _base(),
        tint: tint,
        fade: fade.clamp(0.0, 1.0),
        line: line,
      );
      final lit = _litLastFrame;
      _litLastFrame = false;
      if (!lit) {
        canvas
          ..save()
          ..clipPath(outline);
        ripples.render(canvas, _ringPaint());
        canvas.restore();
      }
      return;
    }
    _openArea(canvas, rect, _area);
    canvas.drawPath(outline, _water..color = color);
    if (film && wetDarkening > 0) {
      // The ground under a film, darker as it soaks it up.
      canvas.drawPath(
        outline,
        _water..color = Color.fromRGBO(0, 0, 0, wetDarkening),
      );
    }

    if (_shown > 0) {
      // Drawn plainly, water mirrors as much as it does at its middle.
      canvas.saveLayer(
        rect,
        _layer
          ..color = Color.fromRGBO(
            0,
            0,
            0,
            (_shown * _meanReflectance(_view())).clamp(0.0, 1.0),
          ),
      );
      _smeared(
        canvas,
        streak,
        () => _mirror(
          canvas,
          line,
          origin,
          () => ReflectionPass.run(
            this,
            () => _renderReflected(_root(), canvas),
          ),
        ),
      );
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

  /// What lies under the mirror: the water's colour, and under a film the
  /// ground it darkens over it.
  Color _base() {
    final dark = film ? wetDarkening.clamp(0.0, 1.0) : 0.0;
    return Color.alphaBlend(Color.fromRGBO(0, 0, 0, dark), color);
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

  /// Where [thing] stands, world y, if not on the line the water mirrors
  /// about: as it says, or where its depth puts it on the world's ground.
  double? _baseOf(Reflectable thing) {
    final base = thing.reflectionBase;
    if (base != null) {
      return base;
    }
    final depth = thing.groundDepth;
    return depth == null ? null : Ground.of(this)?.yAt(depth);
  }

  /// What of the world this water can show, world coordinates: everything
  /// standing across from it (any height - each thing is mirrored about where
  /// it stands), widened by how far its rings, chop and roughness move what
  /// it mirrors.
  Rect get reflectedArea {
    final origin = absoluteTopLeftPosition;
    final reach = waveAmplitude + chop + streak;
    return Rect.fromLTRB(
      origin.x - reach,
      double.negativeInfinity,
      origin.x + size.x + reach,
      double.infinity,
    );
  }

  /// How far to move something (world units, down) for the mirror about
  /// the water line to show it mirrored about [base] instead - the line it
  /// stands on, or a drop the spot it falls to.
  double mirrorShift(double base) {
    final line = _line;
    return -(base - line) * (1 + squash) / squash;
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
  /// newest rings, smeared as rough as the surface is, mirrored as much as
  /// water does at the angle each row is seen at, at [gain] brightness,
  /// over [base], under [tint], faded by [fade] below [line] and eased out
  /// at the rim.
  void _throughShader(
    Canvas canvas,
    _ShaderSlot slot,
    FragmentProgram program,
    Rect rect,
    void Function(Canvas canvas) record, {
    required double gain,
    required Paint paint,
    Color base = const Color(0x00000000),
    Color tint = const Color(0x00000000),
    double fade = 0,
    double line = 0,
  }) {
    // The smear is done in the shader: the image need be no finer than it.
    final sigma = streak / 3;
    // Under half a pixel of smear is none; above, the image need be no finer
    // than a few pixels a sigma.
    final pixels = sigma * resolution;
    final scale =
        resolution * (pixels < 0.5 ? 1 : (2.5 / pixels).clamp(0.25, 1));
    final width = (size.x * scale).ceil();
    final height = (size.y * scale).ceil();
    if (width <= 0 || height <= 0) {
      return;
    }
    final recorder = PictureRecorder();
    record(Canvas(recorder)..scale(scale));
    final picture = recorder.endRecording();
    slot.image?.dispose();
    final image = slot.image = picture.toImageSync(width, height);
    picture.dispose();

    final shader = slot.shader ??= program.fragmentShader();
    final view = _view();
    final pool = outline().getBounds();
    var count = 0;
    void color(UniformsSetter u, Color c) => u
      ..setFloat(c.r * c.a)
      ..setFloat(c.g * c.a)
      ..setFloat(c.b * c.a)
      ..setFloat(c.a);
    shader.setFloatUniforms((u) {
      u
        ..setVector(size)
        ..setFloat(0) // the ring count, set below
        ..setFloat(ripples.flatten)
        ..setFloat(wavelength)
        ..setFloat(gain)
        ..setFloat(_time)
        ..setFloat(chop)
        ..setFloat(view?.top ?? 0)
        ..setFloat(view?.bottom ?? 0)
        ..setFloat(view == null ? 0 : 1)
        ..setFloat(sigma);
      color(u, base);
      color(u, tint);
      u
        ..setFloat(fade)
        ..setFloat(line)
        ..setFloat(pool.center.dx)
        ..setFloat(pool.center.dy)
        ..setFloat(pool.width / 2)
        ..setFloat(pool.height / 2)
        ..setFloat(_softEdge ? edgeSoftness.clamp(0.0, 1.0) : 0)
        ..setFloat(shape == WaterShape.ellipse ? 1 : 0)
        ..setFloat(scale);
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
      ..setImageSampler(0, image, filterQuality: FilterQuality.low);
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
          final base = child is Reflectable ? _baseOf(child) : null;
          if (base == null) {
            child.renderTree(canvas);
          } else {
            canvas
              ..save()
              ..translate(0, mirrorShift(base));
            child.renderTree(canvas);
            canvas.restore();
          }
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
