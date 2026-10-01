import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/glossy.dart';
import 'package:flame_lighting/src/light_reflector.dart';
import 'package:flame_lighting/src/light_shader.dart';
import 'package:flame_lighting/src/light_source.dart';
import 'package:flame_stage/flame_stage.dart';

/// The night over a world, and how its lights cut it.
///
/// It is the stage's [Ambience]: how dark it is, the colour of the dark, the
/// haze, how much colour lights add. It draws, over everything below its
/// priority:
/// - the night: the view covered with [ambient] at [darkness], every light
///   of the stage's frame cutting its shape out of that dark - on the wall
///   plane and as the pool it lays on the ground - with the halo the haze
///   makes round its source, and the moon or sky ([LightShape.directional])
///   lifting the dark everywhere;
/// - the light cast: each light's colour added on top at [glow].
///
/// Whatever stands in a light's way on the stage ([ShadowCaster]) cuts it
/// there: the walker's shadow on the road under a lamp, the umbrella's on
/// the house front behind. Wet walls ([Glossy]) catch every light as a
/// sheen. Surfaces that mirror ([LightReflector]) draw the lights in them
/// last, over the night.
///
/// By day with no light on, it draws nothing at all.
class Lighting extends Component with OnStage, Ambience {
  Lighting({
    this.ambient = const Color(0xFF060A16),
    this.darkness = 0.65,
    this.glow = 0.35,
    this.haze = 0.4,
    super.priority = 1000,
  });

  @override
  Color ambient;

  @override
  double darkness;

  @override
  double glow;

  @override
  double haze;

  /// The lighting of the world [component] is in, if it has one.
  static Lighting? of(Component component) =>
      Stage.maybeOf(component)?.members<Lighting>().firstOrNull;

  final Paint _layer = Paint();
  final Paint _dark = Paint();
  final Paint _cut = Paint()..blendMode = BlendMode.dstOut;
  final Paint _add = Paint()..blendMode = BlendMode.plus;
  final Paint _halo = Paint()..blendMode = BlendMode.dstOut;

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
    var lift = 0.0;
    for (var i = 0; i < field.count; i++) {
      if (field.shapeOf(i) == LightShape.directional) {
        lift += field.strengthOf(i);
      }
    }
    final dark = field.darkness * (1 - lift.clamp(0.0, 1.0));

    if (dark > 0) {
      canvas
        ..saveLayer(view, _layer)
        ..drawRect(view, _dark..color = ambient.withValues(alpha: dark));
      for (var i = 0; i < field.count; i++) {
        if (field.shapeOf(i) == LightShape.directional) {
          continue;
        }
        _cast(canvas, frame, i, _cut, 1);
        _cutHalo(canvas, field, i);
      }
      canvas.restore();
    }
    if (field.glow > 0) {
      for (var i = 0; i < field.count; i++) {
        if (field.shapeOf(i) != LightShape.directional) {
          _cast(canvas, frame, i, _add, field.glow);
        }
      }
    }
    for (final mirror in stage!.members<LightReflector>()) {
      mirror.renderReflectedLights(canvas, frame);
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

  /// Cuts light [i]'s halo out of the night, as the haze makes it.
  void _cutHalo(Canvas canvas, LightField field, int i) {
    final a = (field.haze * field.strengthOf(i) * 0.6).clamp(0.0, 1.0);
    final source = field.sourceRadiusOf(i);
    if (a <= 0 || source <= 0) {
      return;
    }
    final center = Offset(field.xOf(i), field.yOf(i));
    final radius = field.haloRadiusOf(i);
    // The same profile as the halo the light draws, or a ring would show.
    _halo.shader = LightSource.halo(
      center,
      radius,
      const Color(0xFFFFFFFF),
      a,
    );
    canvas.drawCircle(center, radius, _halo);
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
    for (var i = 0; i < field.count; i++) {
      if (field.shapeOf(i) != LightShape.directional) {
        _cast(canvas, frame, i, _sheen, gloss * 0.45, clip: bounds);
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
