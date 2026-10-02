import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_stage/src/depth.dart';
import 'package:flame_stage/src/form.dart';
import 'package:flame_stage/src/light_field.dart';
import 'package:flame_stage/src/shadow.dart';
import 'package:flame_stage/src/sky_view.dart';
import 'package:flame_stage/src/street_projection.dart';
import 'package:flame_stage/src/weather.dart';

/// What a frame of a scene holds, made once at its start by the [Stage] and
/// read by everything after: the view, the street's projection, the light.
class StageFrame {
  StageFrame._();

  /// Frames since the stage started.
  int index = 0;

  /// Seconds since the stage started.
  double time = 0;

  /// Seconds the last step took.
  double dt = 0;

  /// The weather now; a still dry day without a [Weather].
  final WeatherState weather = WeatherState();

  /// The part of the world in view, world coordinates.
  Rect view = Rect.zero;

  /// The street's depth projection; null with no [Ground] on the stage.
  StreetProjection? projection;

  /// What stands in the light's way.
  final ShadowSet shadows = ShadowSet();

  /// Every light of the scene, and its night; it knows what is in the way.
  late final LightField light = LightField()..shadows = shadows;

  /// The sky behind the world, as whatever draws it says; not [SkyView.present]
  /// until something does.
  final SkyView sky = SkyView();
}

/// A component on a [Stage]: on it while mounted, so systems find it in the
/// stage's registry rather than by walking the tree.
mixin OnStage on Component {
  Stage? _stage;

  /// The stage it is on while mounted.
  Stage? get stage => _stage;

  @override
  void onMount() {
    super.onMount();
    _stage = Stage.of(this)..join(this);
  }

  @override
  void onRemove() {
    _stage?.leave(this);
    _stage = null;
    super.onRemove();
  }
}

/// The ground of a side-view street: the band of the view from the line
/// things stand on (its top edge) down towards the viewer. The stage builds
/// the frame's [StreetProjection] from it.
///
/// It lies flat ([LiesFlat]): water lying on it does not mirror it. It is at
/// the street line, under everything there ([DepthOrder.ground]).
mixin Ground on OnStage implements LiesFlat, AtDepth {
  @override
  double depthIn(StreetProjection? projection) => 0;

  @override
  DepthOrder get depthOrder => DepthOrder.ground;

  @override
  bool get placedByDepth => true;

  /// The band, world coordinates.
  Rect groundBand();

  /// How the eye stands before the street.
  DepthCamera get depthCamera => DepthCamera.street;

  /// How high the ground stands at world [x], world units up: the road's
  /// hills. Level by default.
  double groundLiftAt(double x) => 0;
}

/// A step of a frame's drawing that comes before anything is drawn: a
/// resource made once a frame for everything drawn after it - the light of
/// every lamp added up, say, which a wet wall reads as it draws itself,
/// before the lighting draws the night.
///
/// The stage draws first in its world and runs every step on the stage
/// then, in the order they joined, with the canvas as the world's
/// components get it.
mixin FrameStep on OnStage {
  /// Makes what this frame needs from [frame], drawing nothing onto
  /// [canvas] (it is there for its transform).
  void prepareFrame(Canvas canvas, StageFrame frame);
}

/// The stage a side-view scene plays on: who is on it, and what each frame
/// of it holds.
///
/// One a world. A frame runs in a fixed order:
/// 1. it updates before everything else in the world (the lowest priority)
///    and builds the [frame]: the view, the street's projection from its
///    [Ground], what stands in the light's way ([ShadowCaster]), every
///    light its [LightCarrier]s carry and the night its [Ambience] makes;
/// 2. the rest of the world updates, reading the frame;
/// 3. it draws before everything else and runs the [FrameStep]s: what the
///    frame's drawing needs made once;
/// 4. the rest of the world draws: what is at a depth ([AtDepth]) far to
///    near, ordered in step 1 by its depth under the frame's projection.
/// Components that light, mirror, catch rain or need the depth read the
/// frame and the registry, and never walk the tree or ask the camera
/// themselves.
///
/// A world gets one when the first component asks for it; a scene can also
/// add its own, with [viewOf] when its view is not the game camera's.
class Stage extends Component {
  Stage({this.viewOf}) : super(priority: -(1 << 30));

  /// Where the view is, world coordinates; the game camera's by default.
  final Rect Function()? viewOf;

  /// This frame.
  final StageFrame frame = StageFrame._();

  final List<Component> _members = [];
  final Map<Type, Object> _byType = {};
  StreetProjection? _projection;

  /// The stage of the world [component] is in, made and added to it if it
  /// has none yet.
  // A lookup that may make the stage, not a constructor of one.
  // ignore: prefer_constructors_over_static_methods
  static Stage of(Component component) {
    final world = worldOf(component);
    final known = _stages[world];
    if (known != null && !known.isRemoved) {
      return known;
    }
    final found = world.children.whereType<Stage>().firstOrNull;
    if (found != null) {
      return _stages[world] = found;
    }
    final made = Stage();
    world.add(made);
    return _stages[world] = made;
  }

  /// The stage of the world [component] is in, if it has one.
  static Stage? maybeOf(Component component) {
    final world = worldOf(component);
    final known = _stages[world];
    if (known != null && !known.isRemoved) {
      return known;
    }
    final found = world.children.whereType<Stage>().firstOrNull;
    if (found != null) {
      _stages[world] = found;
    }
    return found;
  }

  static final Expando<Stage> _stages = Expando();

  /// The world [component] is in: its nearest [World], or its root.
  static Component worldOf(Component component) {
    if (component is World) {
      return component;
    }
    var top = component;
    for (final a in component.ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top;
  }

  /// Puts [member] on the stage.
  void join(Component member) {
    if (!_members.contains(member)) {
      _members.add(member);
      _byType.clear();
    }
  }

  /// Takes [member] off the stage.
  void leave(Component member) {
    if (_members.remove(member)) {
      _byType.clear();
    }
  }

  /// Everyone on the stage that is a [T], in the order they joined. The
  /// list is kept until someone joins or leaves: do not change it.
  List<T> members<T>() {
    final list = _byType[T];
    if (list != null) {
      return list as List<T>;
    }
    final fresh = _members.whereType<T>().toList(growable: false);
    _byType[T] = fresh;
    return fresh;
  }

  /// The street's projection now: this frame's, or - before the first frame
  /// is built - made from the ground at once.
  StreetProjection? get projection => frame.projection ?? _currentProjection();

  /// Samples of the ground's height over the band.
  static const int _liftSamples = 128;

  StreetProjection? _currentProjection() {
    final grounds = members<Ground>();
    if (grounds.isEmpty) {
      return null;
    }
    final ground = grounds.first;
    final band = ground.groundBand();
    // The hills over the band, a sample every quarter of a metre-ish: the
    // band spans the view and some.
    final lift = GroundLift.sampled(
      band.left,
      band.right,
      _liftSamples,
      ground.groundLiftAt,
    );
    final known = _projection;
    if (known != null &&
        known.band == band &&
        known.camera == ground.depthCamera &&
        known.lift == lift) {
      return known;
    }
    return _projection = StreetProjection(
      band,
      camera: ground.depthCamera,
      lift: lift,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    frame
      ..index += 1
      ..time += dt
      ..dt = dt
      ..view = _view() ?? frame.view
      ..projection = _currentProjection();
    frame.weather.read(members<Weather>().firstOrNull);
    _gatherLight();
    _orderByDepth();
  }

  /// Where the things at a depth start, in their parents' priorities: above
  /// everything else drawn at the default 0, below the lighting's passes.
  static const int firstDepthPriority = 1;

  final List<(AtDepth, double, int, int)> _byDepth = [];

  /// Gives every thing at a depth its place in the drawing: far to near,
  /// then by what it is at its depth, then by when it joined.
  void _orderByDepth() {
    final placed = members<AtDepth>();
    if (placed.isEmpty) {
      return;
    }
    final projection = frame.projection;
    _byDepth
      ..clear()
      ..addAll([
        for (final (i, c) in placed.indexed)
          if (c.placedByDepth)
            (c, c.depthIn(projection), c.depthOrder.index, i),
      ])
      ..sort((a, b) {
        final depth = a.$2.compareTo(b.$2);
        if (depth != 0) {
          return depth;
        }
        final order = a.$3.compareTo(b.$3);
        return order != 0 ? order : a.$4.compareTo(b.$4);
      });
    for (final (rank, (thing, _, _, _)) in _byDepth.indexed) {
      final priority = firstDepthPriority + rank;
      if (thing.priority != priority) {
        thing.priority = priority;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (final step in members<FrameStep>()) {
      step.prepareFrame(canvas, frame);
    }
  }

  Rect? _view() {
    final of = viewOf;
    if (of != null) {
      return of();
    }
    final game = findGame();
    return game is FlameGame ? game.camera.visibleWorldRect : null;
  }

  final Vector2 _at = Vector2.zero();

  void _gatherLight() {
    frame.shadows.clear();
    for (final caster in members<ShadowCaster>()) {
      caster.castShadow(frame.shadows);
    }
    // A shader takes only so many: those in the middle of the view first.
    final middle = frame.view.center;
    frame.shadows.nearestFirst(middle.dx, middle.dy);
    final field = frame.light;
    final ambiences = members<Ambience>();
    field.begin(
      ambiences.isEmpty ? null : ambiences.first,
      weather: frame.weather,
      projection: frame.projection,
      viewX: frame.view.center.dx,
    );
    final projection = frame.projection;
    for (final carrier in members<LightCarrier>()) {
      final placed = carrier is PositionComponent
          ? carrier as PositionComponent
          : null;
      final angle = placed?.absoluteAngle ?? 0;
      for (final light in carrier.lights) {
        if (placed != null) {
          _at.setFrom(placed.absolutePositionOf(light.offset));
        } else {
          _at.setFrom(light.offset);
        }
        field.add(light, _at.x, _at.y, angle, frame.time, projection);
      }
    }
    field.finish(frame.dt, frame.view, projection);
  }
}
