import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_water/src/reflection_pass.dart';
import 'package:flame_water/src/water_surface.dart';

/// The world mirrored once a frame, for every water that mirrors it alike.
///
/// What water shows of the world depends only on the line it mirrors about
/// and how much it squeezes the mirror: a point of the world lands at the
/// same place in every water that shares those, and a thing standing nearer
/// the eye is moved about its own base by the same amount in each. So the
/// waters of a scene that share them - the film on the road and every puddle
/// on it - share one picture: the reflected world is drawn once over the part
/// of the view they cover, and each water reads its own rectangle of it,
/// bent by its own rings and smeared by its own roughness. A puddle more
/// costs a shader draw, not another drawing of the world.
///
/// Waters that differ in line, squash or what they reflect get a pass each.
/// A water out of the view is in none. Drawing the picture is lazy: it is
/// made when the first water of a frame asks for it and kept until one asks
/// a second time, which is the next frame.
class MirrorPass implements Mirror {
  MirrorPass._(this.line, this.squash, this.reflects);

  /// World y of the line the world is mirrored about.
  final double line;

  /// How tall the mirror is against what it mirrors.
  final double squash;

  /// Which components it mirrors.
  final bool Function(Component) reflects;

  final List<WaterSurface> _members = [];

  /// The part of the world the picture covers, world coordinates: the
  /// mirror of it, that is - where the waters are, as much as is in view.
  Rect bounds = Rect.zero;

  /// Pixels of the picture per world unit: as fine as its finest water
  /// needs.
  double scale = 1;

  /// The picture; `null` when none of it is in view.
  Image? image;

  Rect _area = Rect.zero;

  @override
  Rect get area => _area;

  @override
  Component get drawer => _members.first;

  @override
  double mirrorShift(double base) => -(base - line) * (1 + squash) / squash;

  /// How many times the world has been drawn into a picture, for tests.
  static int recordings = 0;

  static final Expando<_Passes> _passes = Expando();

  /// The pass [surface] reads its mirror from this frame, its picture
  /// drawn; `null` when the surface is in none (no stage, out of view, not
  /// mirroring through the shader).
  ///
  /// The first water to ask a second time starts a new frame: the passes
  /// are regrouped and drawn again - the waters may have moved, dried or
  /// come into view.
  static MirrorPass? of(WaterSurface surface) {
    final stage = surface.stage;
    if (stage == null) {
      return null;
    }
    final passes = _passes[stage] ??= _Passes();
    if (!passes.fresh(surface)) {
      passes.rebuild(stage);
    }
    passes.served.add(surface);
    return passes.find(surface);
  }

  void _record(Stage stage, Rect? view) {
    var area = Rect.zero;
    var left = double.infinity;
    var right = double.negativeInfinity;
    var reach = 0.0;
    var pixels = 0.0;
    for (final water in _members) {
      final rect = water.toAbsoluteRect();
      area = area.isEmpty ? rect : area.expandToInclude(rect);
      final shown = water.reflectedArea;
      left = math.min(left, shown.left);
      right = math.max(right, shown.right);
      reach = math.max(reach, rect.left - shown.left);
      pixels = math.max(pixels, water.mirrorPixels);
    }
    _area = Rect.fromLTRB(
      left,
      double.negativeInfinity,
      right,
      double.infinity,
    );
    // Only what is in view needs mirroring, and as far round it as the
    // waters bend what they show.
    bounds = view == null ? area : area.intersect(view.inflate(reach));
    scale = pixels;
    final width = (bounds.width * scale).ceil();
    final height = (bounds.height * scale).ceil();
    if (width <= 0 || height <= 0) {
      return;
    }
    recordings++;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      // Mirrored about the water line and squeezed; the picture's corner
      // is the bounds' corner.
      ..translate(0, line - bounds.top)
      ..scale(1, -squash)
      ..translate(-bounds.left, -line);
    ReflectionPass.run(
      this,
      () => drawWorld(
        canvas,
        Stage.worldOf(drawer),
        reflects: reflects,
        left: left,
        right: right,
        projection: stage.projection,
        shift: mirrorShift,
      ),
    );
    final picture = recorder.endRecording();
    image = picture.toImageSync(width, height);
    picture.dispose();
  }

  /// Draws what [parent] holds that [reflects] takes, in world coordinates
  /// onto [canvas]: a reflected component with all it holds, through its
  /// own renderTree; any other only as a way down to its children, through
  /// its decorator (a placed one's transform). A hidden component is
  /// skipped with all it holds. A component that draws its children its own
  /// way - a parallax layer - is mirrored with them only if it is reflected
  /// itself. Water is never reflected, and a placed thing only if it stands
  /// across from [left] .. [right]. Something standing off the line is moved
  /// by [shift] of its base - as it says, or where its depth meets the
  /// street's ground.
  static void drawWorld(
    Canvas canvas,
    Component parent, {
    required bool Function(Component) reflects,
    required double left,
    required double right,
    required StreetProjection? projection,
    required double Function(double base) shift,
  }) {
    for (final child in parent.children) {
      if (child is WaterSurface ||
          (child is HasVisibility && !child.isVisible)) {
        continue;
      }
      if (reflects(child)) {
        if (_across(child, left, right)) {
          final base = child is Reflectable ? _baseOf(child, projection) : null;
          if (base == null) {
            child.renderTree(canvas);
          } else {
            canvas
              ..save()
              ..translate(0, shift(base));
            child.renderTree(canvas);
            canvas.restore();
          }
        }
        continue;
      }
      if (child.children.isEmpty) {
        continue;
      }
      void down(Canvas canvas) => drawWorld(
        canvas,
        child,
        reflects: reflects,
        left: left,
        right: right,
        projection: projection,
        shift: shift,
      );
      // On the way down, what the component's own drawing does to its
      // children: a placed one's transform and whatever else its decorator
      // adds, as its renderTree would.
      if (child is PositionComponent) {
        child.decorator.applyChain(down, canvas);
      } else {
        down(canvas);
      }
    }
  }

  /// Whether [c] stands where its reflection can reach the water: anything
  /// that is not placed on the plane may; a placed one only if it overlaps
  /// [left] .. [right] across.
  static bool _across(Component c, double left, double right) {
    if (c is! PositionComponent) {
      return true;
    }
    final r = c.toAbsoluteRect();
    return r.right >= left && r.left <= right;
  }

  /// Where [thing] stands, world y, if not on the line the water mirrors
  /// about: as it says, or where its depth puts it on the street's ground.
  static double? _baseOf(Reflectable thing, StreetProjection? projection) {
    final base = thing.reflectionBase;
    if (base != null) {
      return base;
    }
    final depth = thing.groundDepth;
    return depth == null ? null : projection?.yAt(depth);
  }
}

/// A stage's mirror passes, regrouped each frame.
class _Passes {
  final List<MirrorPass> _list = [];

  /// The waters the passes were grouped from.
  final Set<WaterSurface> _grouped = {};

  /// The waters that have asked since.
  final Set<WaterSurface> served = {};

  /// Whether the passes are this frame's for [surface]: it was grouped and
  /// has not asked yet.
  bool fresh(WaterSurface surface) =>
      _grouped.contains(surface) && !served.contains(surface);

  MirrorPass? find(WaterSurface surface) {
    for (final pass in _list) {
      if (pass._members.contains(surface)) {
        return pass;
      }
    }
    return null;
  }

  /// Groups the stage's waters that mirror through the shader and are in
  /// view by what they mirror alike, and draws each group's picture.
  void rebuild(Stage stage) {
    for (final pass in _list) {
      pass.image?.dispose();
    }
    _list.clear();
    _grouped.clear();
    served.clear();
    final view = stage.frame.index > 0 ? stage.frame.view : null;
    for (final water in stage.members<WaterSurface>()) {
      _grouped.add(water);
      if (!water.mirrorsThroughShader) {
        continue;
      }
      if (view != null && !view.overlaps(water.toAbsoluteRect())) {
        continue;
      }
      final line = water.mirrorLine;
      final squash = water.squash;
      final reflects = water.reflects;
      var pass = _list
          .where(
            (p) =>
                p.line == line &&
                p.squash == squash &&
                identical(p.reflects, reflects),
          )
          .firstOrNull;
      if (pass == null) {
        pass = MirrorPass._(line, squash, reflects);
        _list.add(pass);
      }
      pass._members.add(water);
    }
    for (final pass in _list) {
      pass._record(stage, view);
    }
  }
}
