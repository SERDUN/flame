import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/flame_lighting.dart';
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
/// Waters that differ in line or squash get a pass each.
/// A water out of the view is in none. Drawing the picture is lazy: it is
/// made when the first water of a frame asks for it and kept until one asks
/// a second time, which is the next frame.
class MirrorPass implements Mirror {
  MirrorPass._(this.line, this.squash);

  /// World y of the line the world was mirrored about in the picture.
  final double line;

  /// How tall the mirror is against what it mirrors.
  final double squash;

  final List<WaterSurface> _members = [];

  /// The part of the world the picture covers, world coordinates: the
  /// mirror of it, that is - where the waters are, as much as is in view.
  /// A picture kept while the line drifts ([lineHold]) is laid here moved
  /// with it.
  Rect bounds = Rect.zero;

  /// [bounds] as the picture was drawn, about [line].
  Rect _drawn = Rect.zero;

  /// How far the mirror of what stands on the line may have moved, in
  /// pixels of the picture, before a kept picture is drawn anew: what the
  /// water's line drifts by while it is kept - a road on a hill moving
  /// under the view - moves the picture with it ([shiftFor]), which is
  /// exact for what stands on the line and leaves what stands off it
  /// ([Reflectable.reflectionBase], a drop where it lands) at most this
  /// far from where it is, under what the picture's filtering shows.
  static const double lineHold = 0.5;

  /// How far the mirror of what stands on the line moves, world y, when
  /// the line moves from [line] to [now]: the mirror of a point `y` is
  /// `line - squash * (y - line)`.
  double shiftFor(double now) => (now - line) * (1 + squash);

  /// The farthest [shiftFor] may go for this picture, world units.
  double get _shiftHold => lineHold / scale;

  /// Pixels of the picture per world unit: as fine as its finest water
  /// needs.
  double scale = 1;

  /// The picture; `null` when none of it is in view.
  Image? image;

  // The picture smeared up and down, by the smear's sigma in pixels.
  final Map<double, Image> _smeared = {};

  /// The picture smeared up and down by a Gaussian of [sigma] pixels, made
  /// once for every water that reads it so: what a rough surface's smear
  /// does to it, done once over the picture rather than in fifteen taps for
  /// every pixel of the water. `null` with no picture.
  Image? smeared(double sigma) {
    final image = this.image;
    if (image == null) {
      return null;
    }
    final made = _smeared[sigma];
    if (made != null) {
      return made;
    }
    final recorder = PictureRecorder();
    Canvas(recorder).drawImage(
      image,
      Offset.zero,
      Paint()
        ..imageFilter = ImageFilter.blur(
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
    );
    final picture = recorder.endRecording();
    final smeared = picture.toImageSync(image.width, image.height);
    picture.dispose();
    return _smeared[sigma] = smeared;
  }

  void _dispose() {
    image?.dispose();
    image = null;
    for (final smeared in _smeared.values) {
      smeared.dispose();
    }
    _smeared.clear();
  }

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
  /// The first water to ask in a drawing of the world ([Stage.drawing])
  /// has the passes regrouped and drawn again - the waters may have moved,
  /// dried or come into view; the rest of that drawing reads them.
  static MirrorPass? of(WaterSurface surface) {
    final stage = surface.stage;
    if (stage == null) {
      return null;
    }
    final passes = _passes[stage] ??= _Passes();
    if (passes.drawing != stage.drawing) {
      passes.rebuild(stage);
    }
    return passes.find(surface);
  }

  /// The part of the world [view] needs mirrored: where the waters are,
  /// as much as is in it and as far round it as they bend what they show.
  Rect _needed(Rect view) {
    final (:area, :reach, :slack) = _reach();
    return area.intersect(_around(view, reach, slack));
  }

  /// [view] widened by [reach] each way, and by [slack] more up and down.
  static Rect _around(Rect view, double reach, double slack) => slack <= 0
      ? view.inflate(reach)
      : Rect.fromLTRB(
          view.left - reach,
          view.top - reach - slack,
          view.right + reach,
          view.bottom + reach + slack,
        );

  ({Rect area, double reach, double slack}) _reach() {
    var area = Rect.zero;
    var reach = 0.0;
    var most = 0.0;
    for (final water in _members) {
      var rect = water.toAbsoluteRect();
      // Where the street line rises and falls across it, a column is read
      // as far up or down the picture as its line is off the middle's.
      final slack = water.mirrorSlack;
      most = math.max(most, slack);
      if (slack > 0) {
        rect = Rect.fromLTRB(
          rect.left,
          rect.top - slack,
          rect.right,
          rect.bottom + slack,
        );
      }
      area = area.isEmpty ? rect : area.expandToInclude(rect);
      reach = math.max(reach, rect.left - water.reflectedArea.left);
    }
    return (area: area, reach: reach, slack: most);
  }

  /// Draws the picture of what [view] needs, and [margin] past it each way:
  /// what a view moving on needs of a picture kept for the drawings after
  /// ([kept]), which is drawn taller too, by as far as it may be moved
  /// with the line.
  void _record(
    Stage stage,
    Rect? view, {
    double margin = 0,
    bool kept = false,
  }) {
    final (:area, :reach, :slack) = _reach();
    var left = double.infinity;
    var right = double.negativeInfinity;
    var pixels = 0.0;
    for (final water in _members) {
      final shown = water.reflectedArea;
      left = math.min(left, shown.left);
      right = math.max(right, shown.right);
      pixels = math.max(pixels, water.mirrorPixels);
    }
    _area = Rect.fromLTRB(
      left,
      double.negativeInfinity,
      right,
      double.infinity,
    );
    scale = pixels;
    // Only what is in view needs mirroring, and as far round it as the
    // waters bend what they show; a kept picture up and down past them as
    // far as it may be moved with the line, in whole pixels - the picture
    // still meets the screen's own.
    final shown = view?.inflate(margin);
    final needed = shown == null ? area : area.intersect(_around(shown, reach, slack));
    final hold = kept ? lineHold.ceil() / scale : 0.0;
    bounds = _drawn = Rect.fromLTRB(
      needed.left,
      needed.top - hold,
      needed.right,
      needed.bottom + hold,
    );
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
    ReflectionPass.run(this, () {
      final lit = LitPicture.of(
        Lighting.of(drawer),
        litArea(shown ?? bounds),
      );
      LitPicture.apart(lit, () {
        drawWorld(
          canvas,
          Stage.worldOf(drawer),
          left: left,
          right: right,
          projection: stage.projection,
          shift: mirrorShift,
          line: line,
          lit: lit,
        );
        lit?.finish(canvas);
      });
    });
    final picture = recorder.endRecording();
    image = picture.toImageSync(width, height);
    picture.dispose();
  }

  /// Whether water mirrors [component] at all, by what it is: everything on
  /// the stage stands and is mirrored, except what has no height to mirror
  /// ([LiesFlat], the ground with it), what is no thing in the world
  /// ([OffStage]), water itself (water is not mirrored in water), a light
  /// (water mirrors a light from the light itself, as a [LightReflector],
  /// with the streak a rough surface draws it into), the lighting's own
  /// steps ([LitPicture]) and what is hidden.
  static bool mirrors(Component component) =>
      component is! WaterSurface &&
      component is! LiesFlat &&
      component is! OffStage &&
      component is! Stage &&
      component is! LightSource &&
      !LitPicture.isPass(component) &&
      !(component is HasVisibility && !component.isVisible);

  /// The part of the world a picture's lighting covers for a mirror of
  /// [shown]: the world across from it and above it, as far again as the
  /// view is tall each way - whatever the mirror can bring into it.
  static Rect litArea(Rect shown) => Rect.fromLTRB(
    shown.left - shown.width,
    shown.top - 2 * shown.height,
    shown.right + shown.width,
    shown.bottom + 2 * shown.height,
  );

  /// Draws what [parent] holds that water mirrors ([mirrors]), in world
  /// coordinates onto [canvas]: a component with nothing unmirrored under
  /// it with all it holds, through its own renderTree; one that holds
  /// something unmirrored drawn itself, then its children each as they are
  /// mirrored, through its decorator (a placed one's transform). A placed
  /// thing is drawn only if it stands across from [left] .. [right].
  /// Something standing off the line is moved by [shift] of its base - as
  /// it says ([Reflectable]), or where its depth meets the street's ground.
  ///
  /// [lit] lights the picture as the world is lit, at the lighting's own
  /// steps as they come; without it they are left out.
  ///
  /// [line] is the line the world is mirrored about, world y: over ground
  /// that is not level, a depth's ground is taken as far below it as on
  /// level ground below the street line, and the water moves each column's
  /// mirror to the street line there (the water shader).
  static void drawWorld(
    Canvas canvas,
    Component parent, {
    required double left,
    required double right,
    required StreetProjection? projection,
    required double Function(double base) shift,
    double? line,
    LitPicture? lit,
  }) {
    for (final child in parent.children) {
      if (lit != null && lit.step(canvas, child)) {
        continue;
      }
      if (!mirrors(child) || !_across(child, left, right)) {
        continue;
      }
      lit?.drew();
      final base = child is Reflectable
          ? _baseOf(child, projection, line)
          : null;
      if (base != null) {
        canvas
          ..save()
          ..translate(0, shift(base));
      }
      if (!_holdsUnmirrored(child)) {
        child.renderTree(canvas);
      } else {
        void down(Canvas canvas) {
          child.render(canvas);
          drawWorld(
            canvas,
            child,
            left: left,
            right: right,
            projection: projection,
            shift: shift,
            line: line,
            lit: lit,
          );
        }

        // On the way down, what the component's own drawing does to its
        // children: a placed one's transform and whatever else its decorator
        // adds, as its renderTree would.
        if (child is PositionComponent) {
          child.decorator.applyChain(down, canvas);
        } else {
          down(canvas);
        }
      }
      if (base != null) {
        canvas.restore();
      }
    }
  }

  /// Whether anything under [component] is not mirrored.
  static bool _holdsUnmirrored(Component component) {
    for (final child in component.children) {
      if (!mirrors(child) || _holdsUnmirrored(child)) {
        return true;
      }
    }
    return false;
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
  /// about: as it says, or where its depth puts it on the street's ground -
  /// round the view's middle on level ground; over hills and round a bend,
  /// as far below [line] as the depth's ground is below the street line,
  /// which the water then moves to the street line at each column.
  static double? _baseOf(
    Reflectable thing,
    StreetProjection? projection,
    double? line,
  ) {
    final base = thing.reflectionBase;
    if (base != null) {
      return base;
    }
    final depth = thing.groundDepth;
    if (depth == null || projection == null) {
      return null;
    }
    if (line != null && !projection.lift.isLevel) {
      return line + (projection.yAt(depth) - projection.line);
    }
    return projection.groundYAt(projection.band.center.dx, depth);
  }
}

/// A stage's mirror passes, regrouped each frame.
class _Passes {
  final List<MirrorPass> _list = [];

  /// The drawing of the world they were drawn for ([Stage.drawing]).
  int drawing = -1;

  /// The drawing of the world their pictures were last drawn in.
  int _drawnIn = -1;

  /// The view of the last drawing, and how far it moved in each of the
  /// last [_driftsKept] drawings: a picture kept for the drawings after is
  /// drawn wider by the most of those for each of them, so a view
  /// following the walker does not run past its edge. Not the last move
  /// alone: a view moved by whole steps of the world moves unevenly from
  /// drawing to drawing - a step in one, two in the next - and a picture
  /// drawn after the short one would fall short of the long one.
  Rect? _lastView;
  final List<double> _drifts = [];
  static const int _driftsKept = 8;

  /// Whether this drawing reads the pictures there are
  /// ([WaterSurface.mirrorEvery]): the pictures are younger than the least
  /// any water in view keeps one for, and the waters in view are the ones
  /// they were drawn for, mirroring alike.
  ///
  /// A water's line may have drifted since, by no more than moves the
  /// picture [MirrorPass.lineHold]: the picture is then laid moved with it.
  bool _keeps(Stage stage) {
    if (_list.isEmpty || stage.frame.index <= 0 || _drawnIn < 0) {
      return false;
    }
    final view = stage.frame.view;
    var every = 1 << 30;
    var members = 0;
    // Where each pass's waters mirror about now: alike, as they were.
    final lines = <MirrorPass, double>{};
    for (final water in stage.members<WaterSurface>()) {
      if (!water.mirrorsThroughShader ||
          !view.overlaps(water.toAbsoluteRect())) {
        continue;
      }
      every = math.min(every, water.mirrorEvery);
      final pass = find(water);
      if (pass == null || pass.squash != water.squash) {
        return false;
      }
      final now = water.mirrorLine;
      final other = lines[pass] ??= now;
      if ((now - other).abs() > _hair ||
          pass.shiftFor(now).abs() > pass._shiftHold) {
        return false;
      }
      members++;
    }
    var had = 0;
    for (final pass in _list) {
      had += pass._members.length;
    }
    if (members != had || stage.drawing - _drawnIn >= every) {
      return false;
    }
    // And, laid where the lines moved them, they still hold all this view
    // needs - else a strip at its leading edge would mirror nothing.
    final laid = <MirrorPass, Rect>{
      for (final pass in _list)
        pass: pass._drawn.translate(0, pass.shiftFor(lines[pass] ?? pass.line)),
    };
    for (final pass in _list) {
      if (!_holds(laid[pass]!, pass._needed(view))) {
        return false;
      }
    }
    for (final pass in _list) {
      pass.bounds = laid[pass]!;
    }
    return true;
  }

  static const double _hair = 1e-6;

  /// Whether [outer] holds [inner], to a hair.
  static bool _holds(Rect outer, Rect inner) {
    return inner.isEmpty ||
        (inner.left >= outer.left - _hair &&
            inner.top >= outer.top - _hair &&
            inner.right <= outer.right + _hair &&
            inner.bottom <= outer.bottom + _hair);
  }

  /// The least drawings any water in [view] keeps a picture for.
  static int _every(Stage stage, Rect? view) {
    var every = 1 << 30;
    for (final water in stage.members<WaterSurface>()) {
      if (water.mirrorsThroughShader &&
          (view == null || view.overlaps(water.toAbsoluteRect()))) {
        every = math.min(every, water.mirrorEvery);
      }
    }
    return every == 1 << 30 ? 1 : every;
  }

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
    if (stage.frame.index > 0) {
      final view = stage.frame.view;
      final last = _lastView;
      if (last != null) {
        _drifts.add((view.center - last.center).distance);
        if (_drifts.length > _driftsKept) {
          _drifts.removeAt(0);
        }
      }
      _lastView = view;
    }
    if (_keeps(stage)) {
      drawing = stage.drawing;
      return;
    }
    _drawnIn = stage.drawing;
    for (final pass in _list) {
      pass._dispose();
    }
    _list.clear();
    drawing = stage.drawing;
    final view = stage.frame.index > 0 ? stage.frame.view : null;
    for (final water in stage.members<WaterSurface>()) {
      if (!water.mirrorsThroughShader) {
        continue;
      }
      if (view != null && !view.overlaps(water.toAbsoluteRect())) {
        continue;
      }
      final line = water.mirrorLine;
      final squash = water.squash;
      var pass = _list
          .where((p) => p.line == line && p.squash == squash)
          .firstOrNull;
      if (pass == null) {
        pass = MirrorPass._(line, squash);
        _list.add(pass);
      }
      pass._members.add(water);
    }
    // As far as the view goes while the pictures are kept, at the most it
    // went a drawing of late - and half again, for a view that speeds up.
    // A view that moves that much each drawing comes to the edge of the
    // picture no sooner than the drawing after the last one it is kept
    // for. No wider than the view is: a view jumping further has left
    // the picture whatever its margin.
    final every = _every(stage, view);
    final drift = _drifts.fold<double>(0, math.max);
    final margin = every > 1 && view != null
        ? math.min(drift * (every - 1) * 1.5, view.width)
        : 0.0;
    for (final pass in _list) {
      pass._record(stage, view, margin: margin, kept: every > 1);
    }
  }
}
