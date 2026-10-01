import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/glossy.dart';
import 'package:flame_lighting/src/light_buffer.dart';
import 'package:flame_lighting/src/light_reflector.dart';
import 'package:flame_lighting/src/light_shader.dart';
import 'package:flame_lighting/src/light_source.dart';
import 'package:flame_stage/flame_stage.dart';

/// The light a world is seen in: the sky's and its lamps', laid over
/// everything below its priority.
///
/// It is the stage's [Ambience]: the [sky]'s colour and how much light it
/// gives ([skyLight]), the haze, how much colour lights add in the air.
/// Everything drawn under it is a surface, and it shows as much as light
/// falls on it: it is multiplied by the illumination there, as the eye has
/// adapted to it ([LightField.exposure]) - the sky's light, every light of
/// the stage's frame on the wall plane and as the pool it lays on the
/// ground, what glows itself (a bulb, a lit pane, a tube) and the halo the
/// haze makes round it. Then each light's colour is added in the air, at
/// [glow].
///
/// There is no night mode and no day mode: under a bright sky the eye
/// adapts down and the lamps vanish against it; under a dark one the
/// lamps carry the scene. By day with no light on, it draws nothing at
/// all.
///
/// Whatever stands in a light's way on the stage ([ShadowCaster]) shades
/// it there: the walker's shadow on the road under a lamp, the umbrella's
/// on the house front behind. Wet walls ([Glossy]) catch every light as a
/// sheen. Surfaces that mirror ([LightReflector]) draw the lights in them
/// last.
///
/// Where flutter_gpu is on, every light is added up once a frame into a
/// float image of the view ([LightBuffer]) before anything draws, and the
/// illumination, the light in the air and every sheen are each one draw of
/// it; elsewhere (the web, tests) each light is drawn on the canvas.
class Lighting extends Component with OnStage, Ambience, FrameStep {
  Lighting({
    this.sky = const Color(0xFFFFFFFF),
    this.skyLight = 40,
    this.adaptation = 1,
    this.glow = 0.35,
    this.haze = 0.4,
    this.useBuffer = true,
    this.bufferScale = 0.5,
    super.priority = 1000,
  });

  @override
  Color sky;

  @override
  double skyLight;

  @override
  double adaptation;

  @override
  double glow;

  @override
  double haze;

  /// Whether to add the lights up on the GPU where it can ([LightBuffer]).
  /// Off, every light is drawn on the canvas.
  bool useBuffer;

  /// How fine the light buffer is against the screen, each way: light
  /// changes slowly across the view, and half the pixels is plenty.
  double bufferScale;

  LightBuffer? _buffer;
  bool _bufferAsked = false;
  Image? _lightImage;
  Rect _lightArea = Rect.zero;

  @override
  void onMount() {
    super.onMount();
    if (_bufferAsked || !useBuffer || LightBuffer.available == false) {
      return;
    }
    _bufferAsked = true;
    LightBuffer.create().then((buffer) {
      if (isRemoved || isRemoving) {
        buffer?.dispose();
        return;
      }
      _buffer = buffer;
    });
  }

  @override
  void onRemove() {
    _buffer?.dispose();
    _buffer = null;
    _bufferAsked = false;
    _lightImage = null;
    super.onRemove();
  }

  /// Adds the frame's lights up into the buffer, before anything draws,
  /// so a wet wall drawn before the night reads this frame's light.
  @override
  void prepareFrame(Canvas canvas, StageFrame frame) {
    _lightImage = null;
    final buffer = _buffer;
    if (buffer == null || !useBuffer || LightShader.compose == null) {
      return;
    }
    if (!frame.light.isLit || frame.light.count == 0) {
      return;
    }
    final view = frame.view.inflate(frame.view.width * 0.01);
    final m = canvas.getTransform();
    final pixels = math.sqrt(m[0] * m[0] + m[1] * m[1]) * bufferScale;
    _lightArea = view;
    _lightImage = buffer.render(
      frame,
      view,
      (view.width * pixels).ceil(),
      (view.height * pixels).ceil(),
    );
  }

  /// Lays the light buffer over [area] with [paint]: the illumination as
  /// seen under [field]'s sky (mode 0, to multiply), or the light in the
  /// air at [amount] (mode 1, to add).
  void _drawBuffer(
    Canvas canvas,
    Rect area,
    Paint paint,
    LightField field, {
    required int mode,
    double amount = 0,
  }) {
    final shader = LightShader.compose!;
    final image = _lightImage!;
    final a = _lightArea;
    shader
      ..setFloat(0, a.left)
      ..setFloat(1, a.top)
      ..setFloat(2, a.width)
      ..setFloat(3, a.height)
      ..setFloat(4, field.skyRed)
      ..setFloat(5, field.skyGreen)
      ..setFloat(6, field.skyBlue)
      ..setFloat(7, field.exposure)
      ..setFloat(8, mode.toDouble())
      ..setFloat(9, amount)
      ..setFloat(10, 0)
      ..setFloat(11, 0)
      ..setImageSampler(0, image, filterQuality: FilterQuality.low);
    canvas.drawRect(area, paint..shader = shader);
    paint.shader = null;
  }

  /// The lighting of the world [component] is in, if it has one.
  static Lighting? of(Component component) =>
      Stage.maybeOf(component)?.members<Lighting>().firstOrNull;

  final Paint _illumination = Paint()..blendMode = BlendMode.modulate;
  final Paint _sky = Paint();
  final Paint _add = Paint()..blendMode = BlendMode.plus;
  final Paint _emit = Paint()..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final frame = stage?.frame;
    if (frame == null) {
      return;
    }
    final field = frame.light;
    if (!field.isLit) {
      return;
    }
    // A little past the view, so nothing shows at its edge.
    final view = frame.view.inflate(frame.view.width * 0.01);
    final e = field.exposure;
    if (_lightImage != null) {
      _drawBuffer(canvas, view, _illumination, field, mode: 0);
      if (field.glow > 0) {
        _drawBuffer(canvas, view, _add, field, mode: 1, amount: field.glow * e);
      }
    } else {
      _lightAll(canvas, frame, view);
    }
    for (final mirror in stage!.members<LightReflector>()) {
      mirror.renderReflectedLights(canvas, frame);
    }
  }

  /// The canvas path: the illumination built in a layer - the sky's light,
  /// every light added on each plane, what glows itself and its halo - and
  /// multiplied onto the scene; then each light added in the air.
  void _lightAll(Canvas canvas, StageFrame frame, Rect view) {
    final field = frame.light;
    final e = field.exposure;
    canvas
      ..saveLayer(view, _illumination)
      ..drawRect(
        view,
        _sky
          ..color = Color.from(
            alpha: 1,
            red: math.min(field.skyRed * e, 1),
            green: math.min(field.skyGreen * e, 1),
            blue: math.min(field.skyBlue * e, 1),
          ),
      );
    for (var i = 0; i < field.count; i++) {
      _cast(canvas, frame, i, _add, e);
      _glowItself(canvas, field, i, e);
    }
    canvas.restore();
    if (field.glow > 0) {
      for (var i = 0; i < field.count; i++) {
        _cast(canvas, frame, i, _add, field.glow * e);
      }
    }
  }

  /// Light [i] on the wall plane above the street line and on the ground
  /// below it, with [paint]'s blend, at [amount].
  void _cast(
    Canvas canvas,
    StageFrame frame,
    int i,
    Paint paint,
    double amount, {
    Rect? clip,
  }) {
    final field = frame.light;
    final reach = _bounds(field, i);
    if (!reach.overlaps(frame.view)) {
      return;
    }
    final projection = frame.projection;
    final line = projection?.line;
    final wall = line == null
        ? reach
        : reach.intersect(
            Rect.fromLTRB(reach.left, reach.top, reach.right, line),
          );
    final planes = [
      if (!wall.isEmpty) (LightPlane.wall, wall),
      if (projection != null && line != null)
        (
          LightPlane.ground,
          reach.intersect(
            Rect.fromLTRB(
              reach.left,
              line,
              reach.right,
              projection.band.bottom,
            ),
          ),
        ),
    ];
    for (final (plane, rect) in planes) {
      final area = clip == null ? rect : rect.intersect(clip);
      if (area.isEmpty) {
        continue;
      }
      final shader = LightShader.shader;
      if (shader == null) {
        _castPlain(canvas, field, i, paint, amount, area);
        continue;
      }
      LightShader.write(
        shader,
        field,
        i,
        plane: plane,
        amount: amount,
        projection: projection,
        shadows: frame.shadows,
      );
      canvas.drawRect(area, paint..shader = shader);
      paint.shader = null;
    }
  }

  /// Where light [i] can reach on screen.
  Rect _bounds(LightField field, int i) {
    final r = field.reachOf(i);
    final x = field.xOf(i);
    final y = field.yOf(i);
    final ex = field.shapeOf(i) == LightShape.area ? field.extentXOf(i) / 2 : 0;
    final ey = field.shapeOf(i) == LightShape.area ? field.extentYOf(i) / 2 : 0;
    final el = field.shapeOf(i) == LightShape.line ? field.extentXOf(i) / 2 : 0;
    return Rect.fromLTRB(
      x - r - ex - el,
      y - r - ey - el,
      x + r + ex + el,
      y + r + ey + el,
    );
  }

  /// Light [i] as a soft disc, before the shader is loaded.
  void _castPlain(
    Canvas canvas,
    LightField field,
    int i,
    Paint paint,
    double amount,
    Rect area,
  ) {
    final a = (amount * field.strengthOf(i)).clamp(0.0, 1.0);
    if (a <= 0) {
      return;
    }
    final center = Offset(field.xOf(i), field.yOf(i));
    final color = field.colorOf(i);
    paint.shader = Gradient.radial(
      center,
      field.radiusOf(i),
      [
        color.withValues(alpha: a),
        color.withValues(alpha: a * 0.35),
        color.withValues(alpha: 0),
      ],
      const [0, 0.35, 1],
    );
    canvas
      ..save()
      ..clipRect(area)
      ..drawCircle(center, field.radiusOf(i), paint)
      ..restore();
    paint.shader = null;
  }

  /// Into the illumination: what of light [i] glows itself - a bulb, a lit
  /// pane, a tube - fully, so it shows as bright as it is drawn, and the
  /// halo the haze makes round it, as much light as it is ([exposure]).
  void _glowItself(Canvas canvas, LightField field, int i, double exposure) {
    final center = Offset(field.xOf(i), field.yOf(i));
    final source = field.sourceRadiusOf(i);
    switch (field.shapeOf(i)) {
      case LightShape.area:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: field.extentXOf(i),
            height: field.extentYOf(i),
          ),
          _emit
            ..shader = null
            ..color = const Color(0xFFFFFFFF),
        );
      case LightShape.line:
        final half = field.extentXOf(i) / 2;
        final angle = field.directionOf(i);
        final along = Offset(math.cos(angle), math.sin(angle)) * half;
        canvas.drawLine(
          center - along,
          center + along,
          _emit
            ..shader = null
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(source, field.extentXOf(i) * 0.02),
        );
        _emit.style = PaintingStyle.fill;
      case LightShape.point:
      case LightShape.cone:
      case LightShape.directional:
        if (source > 0) {
          // As the bulb is drawn: full to 0.55 of 1.6 source radii.
          _emit.shader = Gradient.radial(
            center,
            source * 1.6,
            const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            const [0, 0.55, 1],
          );
          canvas.drawCircle(center, source * 1.6, _emit);
        }
    }
    final a = (field.haze * field.strengthOf(i) * 0.6 * exposure).clamp(
      0.0,
      1.0,
    );
    if (a > 0 && source > 0) {
      final radius = field.haloRadiusOf(i);
      // The same profile as the halo the light draws, or a ring would show.
      _emit.shader = LightSource.halo(
        center,
        radius,
        const Color(0xFFFFFFFF),
        a,
      );
      canvas.drawCircle(center, radius, _emit);
    }
    _emit.shader = null;
  }

  final Paint _sheen = Paint()..blendMode = BlendMode.plus;
  final LightSample _sample = LightSample();
  double _time = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  /// The lights glinting off [wet]: each light's cast once more over its
  /// wet area, as strong as it is glossy (shadows included) - and damp
  /// trails where water runs down it, only where light falls. [canvas] is
  /// in world coordinates; [Glossy] calls this right after drawing itself.
  void drawSheen(Canvas canvas, Glossy wet) {
    final frame = stage?.frame;
    final gloss = wet.gloss.clamp(0.0, 1.0);
    if (frame == null || gloss <= 0 || frame.light.count == 0) {
      return;
    }
    final field = frame.light;
    final area = wet.glossArea();
    final bounds = area.getBounds();
    canvas
      ..save()
      ..clipPath(area);
    final amount = gloss * 0.45 * field.exposure;
    if (_lightImage != null) {
      _drawBuffer(canvas, bounds, _sheen, field, mode: 1, amount: amount);
    } else {
      for (var i = 0; i < field.count; i++) {
        _cast(canvas, frame, i, _sheen, amount, clip: bounds);
      }
    }
    final every = math.max(wet.rivuletSpacing, 1e-3);
    var k = 0;
    for (var x = bounds.left + every / 2; x < bounds.right; x += every) {
      k++;
      final h = _unit(k * 12.9898);
      final rx = x + (h - 0.5) * every * 0.8;
      // Water gathers where it will: a rivulet starts anywhere down the
      // wall and runs some way, not from roof to ground like a seam.
      final top = bounds.top + bounds.height * 0.7 * _unit(k * 3.7);
      final bottom = math.min(
        bounds.bottom,
        top + bounds.height * (0.15 + 0.45 * _unit(k * 7.3)),
      );
      field.sample(rx, (top + bottom) / 2, _sample);
      final lit = _sample.added.clamp(0.0, 1.0);
      if (lit <= 0.02) {
        continue;
      }
      // A damp trail, not a line: wide, soft, fading in and out along its
      // length, only just lighter than the wall round it, in the colour of
      // the light on it. It breathes slowly as the water on it thickens and
      // thins.
      final breath = 0.75 + 0.25 * math.sin(_time * (0.4 + 0.5 * h) + h * 6);
      final a = gloss * lit * (0.08 + 0.1 * h) * breath;
      final halfWidth = wet.rivuletWidth * (0.8 + 0.5 * _unit(k * 5.1)) / 2;
      final middle = Offset(rx, top + (bottom - top) * 0.4);
      final color = Color.lerp(_sample.color, const Color(0xFFFFFFFF), 0.3)!;
      _rivulet.shader = Gradient.radial(
        Offset.zero,
        1,
        [
          color.withValues(alpha: a),
          color.withValues(alpha: a * 0.6),
          color.withValues(alpha: 0),
        ],
        const [0, 0.45, 1],
      );
      canvas
        ..save()
        ..translate(middle.dx, middle.dy)
        ..scale(halfWidth, (bottom - top) / 2)
        ..drawRect(const Rect.fromLTRB(-1, -1, 1, 1), _rivulet)
        ..restore();
    }
    canvas.restore();
  }

  static double _unit(double x) {
    final s = math.sin(x) * 43758.5453;
    return s - s.floorToDouble();
  }

  final Paint _rivulet = Paint()..blendMode = BlendMode.plus;
}
