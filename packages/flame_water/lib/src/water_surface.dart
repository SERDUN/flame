import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_lighting/flame_lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flame_water/src/rain.dart';
import 'package:flame_water/src/rain_catcher.dart';
import 'package:flame_water/src/reflection_pass.dart';
import 'package:flame_water/src/ripple_rings.dart';
import 'package:flame_water/src/water_shader.dart';
import 'package:flame_water/src/wave_field.dart';
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
/// Under a `Lighting` it is a [LightReflector]: every light of the stage's
/// frame - bulbs, lit windows, tubes, their halos - is mirrored in it, over
/// the night, through the same shader in its lights mode: worked out from
/// the light's numbers where the mirror puts it, bent by the same drops as
/// the street's reflection and smeared down into a long broken streak by a
/// rough surface ([streak]), as a wet road does. A lamp is as bright in it
/// as a lamp is ([glowGain]), not as bright as an image's white.
///
/// The surface must not be rotated or scaled, nor its parents: it maps world
/// coordinates to its own by its absolute top-left corner.
class WaterSurface extends PositionComponent
    with OnStage, RainCatcher, Wettable, LightReflector {
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
  /// things stand on - the street line of the stage's projection - or, with
  /// no ground, the surface's top edge. A puddle on a road lies below that
  /// line and still mirrors about it, so feet meet their reflection;
  /// something standing elsewhere says so itself
  /// (`Reflectable.reflectionBase`).
  double? waterLine;

  /// The line the world is mirrored about now, world y.
  double get _line =>
      waterLine ?? _projection?.line ?? absoluteTopLeftPosition.y;

  /// The street's projection now, if the stage has a ground.
  StreetProjection? get _projection => stage?.projection;

  /// The water under its reflection.
  Color color;

  /// How much of it is clear water, `0..1`: 1 still water, less a film
  /// broken by the asphalt poking through. How much clear water mirrors is
  /// water's own - most of the light seen low across it, little seen from
  /// above ([fresnel]) - and follows from the stage's projection, the angle
  /// each row of it is seen at.
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

  /// How far a unit of the GPU field's slope shifts the reflection, in
  /// [waveAmplitude]s: a drop's rings there bend it about as far as a ring
  /// does.
  double waveGain = 4;

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
    final y = _projection?.yAt(depth) ?? origin.y + depth.clamp(0, 1) * size.y;
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

  /// How much brighter than the screen's white a light's source is: a
  /// still puddle shows a lamp burnt out white, a rough road smears it
  /// into a streak that is still bright, as a real lamp's is. Only the
  /// sources: the light the haze scatters round them comes back as bright
  /// as it is.
  double glowGain;

  /// Water's reflectance seen at an angle whose sine above the surface is
  /// [sinElevation] (Fresnel, Schlick's approximation for water): most of
  /// the light far off, where the eye looks along it, little near, where
  /// it looks down. The shader works it out the same way.
  static double fresnel(double sinElevation) {
    const f0 = 0.02;
    final c = 1 - sinElevation.clamp(0.0, 1.0);
    return f0 + (1 - f0) * c * c * c * c * c;
  }

  /// How the eye sees this water, from the stage's projection: the sine of
  /// the angle it looks down at its top and bottom rows. `null` without a
  /// ground: then it mirrors evenly, as much as [reflectivity] says.
  ({double top, double bottom})? _view() {
    final projection = _projection;
    if (projection == null) {
      return null;
    }
    final origin = absoluteTopLeftPosition;
    return (
      top: projection.sinElevation(projection.depthAt(origin.y)),
      bottom: projection.sinElevation(projection.depthAt(origin.y + size.y)),
    );
  }

  /// Water's reflectance where it is seen at its middle: what a surface
  /// drawn without the shader mirrors all over.
  double _meanReflectance(({double top, double bottom})? view) =>
      view == null ? 1 : fresnel((view.top + view.bottom) / 2);

  @override
  void renderReflectedLights(Canvas canvas, StageFrame frame) {
    final strength = _shown.clamp(0.0, 1.0);
    if (strength <= 0 || _dry) {
      return;
    }
    final field = frame.light;
    final rect = size.toRect();
    final origin = absoluteTopLeftPosition;
    canvas
      ..save()
      ..translate(origin.x, origin.y);
    final count = _gatherLights(field, origin);
    final program = WaterShader.program;
    if (count > 0) {
      if (quality == WaterQuality.rippled && program != null) {
        _drawLights(canvas, program, rect, count, strength, field);
      } else {
        _drawLightsPlain(canvas, count, strength, field.haze);
      }
    }
    // The rings' crests glint with the light round them - bright by a lamp,
    // faint but there in the dark, lit by the sky. The field's crests glint
    // in the water shader instead.
    if (_waves?.heights == null) {
      canvas
        ..save()
        ..clipPath(outline());
      ripples.render(
        canvas,
        _ringPaint(),
        lightAt: (x, y) {
          field.sample(origin.x + x, origin.y + y, _sample);
          return 0.35 + _sample.light;
        },
      );
      canvas.restore();
    }
    canvas.restore();
  }

  final LightSample _sample = LightSample();

  /// Whether the lighting draws the rings this frame, glinting with the
  /// light, over the night ([renderReflectedLights]); otherwise [render]
  /// draws them plain.
  bool get _ringsLit {
    final stage = this.stage;
    return stage != null &&
        stage.frame.light.isLit &&
        stage.members<Lighting>().isNotEmpty;
  }

  /// The mirrored lights for the shader, [WaterShader.lightFloats] each.
  final Float32List _lights = Float32List(
    WaterShader.maxLights * WaterShader.lightFloats,
  );
  final List<int> _candidates = [];

  /// Picks the strongest lights of [field] whose mirror image, or the light
  /// they cast, can reach the water, and writes them into [_lights] as the
  /// shader reads them (see `lights` in water.frag): their images mirrored
  /// into local units, and as they are, for the light they cast. Returns
  /// how many.
  int _gatherLights(LightField field, Vector2 origin) {
    _candidates.clear();
    final line = _line;
    for (var i = 0; i < field.count; i++) {
      if (field.shapeOf(i) == LightShape.directional) {
        continue;
      }
      // What it casts reaches its radius round it; the mirror shows that
      // much round its image.
      final x = field.xOf(i) - origin.x;
      final out = field.radiusOf(i) + field.haloRadiusOf(i) + streak;
      if (x < -out || x > size.x + out) {
        continue;
      }
      final base = field.standsAtOf(i) ?? line;
      final y = base + (base - field.yOf(i)) * squash - origin.y;
      if (y < -out * squash || y > size.y + out * squash) {
        continue;
      }
      _candidates.add(i);
    }
    if (_candidates.length > WaterShader.maxLights) {
      _candidates.sort(
        (a, b) => field.strengthOf(b).compareTo(field.strengthOf(a)),
      );
    }
    final n = math.min(_candidates.length, WaterShader.maxLights);
    for (var k = 0; k < n; k++) {
      final i = _candidates[k];
      final o = k * WaterShader.lightFloats;
      final shape = field.shapeOf(i);
      final base = field.standsAtOf(i) ?? line;
      final color = field.colorOf(i);
      final angle = field.directionOf(i);
      var halfX = 0.0;
      var halfY = 0.0;
      var dirX = 0.0;
      var dirY = 0.0;
      // A bulb as a Gaussian as bright through its middle as the disc its
      // light source draws (full to 0.55 of 1.6 radii, then fading): a sigma
      // of one source radius.
      var body = field.sourceRadiusOf(i);
      // A bulb is brighter than white; a window or a tube is drawn as
      // bright as it is.
      var headroom = glowGain;
      // A cone's outer edge; a tube's half length instead.
      var spreadOrLength = math.cos(field.halfSpreadOf(i));
      switch (shape) {
        case LightShape.area:
          halfX = field.extentXOf(i) / 2;
          halfY = field.extentYOf(i) / 2 * squash;
          body = 0.04 * math.min(field.extentXOf(i), field.extentYOf(i)) + 0.5;
          headroom = 1;
        case LightShape.line:
          // Its direction mirrored and squeezed: y flips, by squash.
          final mx = math.cos(angle);
          final my = -math.sin(angle) * squash;
          final length = math.sqrt(mx * mx + my * my);
          dirX = mx / length;
          dirY = my / length;
          halfX = field.extentXOf(i) / 2 * length;
          body = 0.5 * math.max(field.sourceRadiusOf(i), 2);
          headroom = 1;
          spreadOrLength = field.extentXOf(i) / 2;
        case LightShape.point:
        case LightShape.cone:
        case LightShape.directional:
          break;
      }
      _lights
        ..[o] = field.xOf(i) - origin.x
        ..[o + 1] = base + (base - field.yOf(i)) * squash - origin.y
        ..[o + 2] = shape.index.toDouble()
        ..[o + 3] = math.max(body, 0.5)
        ..[o + 4] = color.r
        ..[o + 5] = color.g
        ..[o + 6] = color.b
        ..[o + 7] = field.strengthOf(i)
        ..[o + 8] = halfX
        ..[o + 9] = halfY
        ..[o + 10] = dirX
        ..[o + 11] = dirY
        ..[o + 12] = base - origin.y
        ..[o + 13] = field.radiusOf(i)
        ..[o + 14] = math.cos(angle)
        ..[o + 15] = math.sin(angle)
        ..[o + 16] = math.cos(field.halfSpreadOf(i) - field.edgeOf(i))
        ..[o + 17] = spreadOrLength
        ..[o + 18] = field.isPhysicalOf(i) ? 1 : 0
        ..[o + 19] = headroom;
    }
    return n;
  }

  /// The [count] gathered lights through the water shader, bent and
  /// smeared as the street's reflection is.
  void _drawLights(
    Canvas canvas,
    FragmentProgram program,
    Rect rect,
    int count,
    double strength,
    LightField field,
  ) {
    final shader = _lightSlot.shader ??= program.fragmentShader();
    final haze = field.haze;
    final glow = field.glow;
    final f =
        _uniforms(
            _lightSlot,
            gain: strength,
            line: _line - absoluteTopLeftPosition.y,
          )
          ..[WaterShader.lightMode] = 1
          ..[WaterShader.lightCount] = count.toDouble()
          ..[WaterShader.haze] = haze
          ..[WaterShader.air] = glow * (0.2 + 0.5 * haze)
          ..setRange(
            WaterShader.lights,
            WaterShader.lights + count * WaterShader.lightFloats,
            _lights,
          );
    WaterShader.upload(shader, f);
    final blank = _blank ??= _makeBlank();
    shader
      ..setImageSampler(0, blank)
      ..setImageSampler(1, _waves?.heights ?? blank);
    canvas.drawRect(rect, _glowPaint..shader = shader);
  }

  /// The [count] gathered lights as soft ellipses, for water drawn without
  /// the shader: smeared, not bent.
  void _drawLightsPlain(
    Canvas canvas,
    int count,
    double strength,
    double haze,
  ) {
    final view = _view();
    final s = view == null ? 1.0 : (view.top + view.bottom) / 2;
    final gain = strength * _meanReflectance(view);
    final down = streak / 3;
    final across = down * s;
    canvas
      ..save()
      ..clipPath(outline());
    for (var k = 0; k < count; k++) {
      final o = k * WaterShader.lightFloats;
      final body = _lights[o + 3];
      final sx = math.sqrt(body * body + across * across) + _lights[o + 8];
      final sy =
          math.sqrt(body * body * squash * squash + down * down) +
          _lights[o + 9];
      final wide = body * body * squash / (sx * sy);
      final a = (gain * _lights[o + 7] * _lights[o + 19] * wide).clamp(
        0.0,
        1.0,
      );
      final color = Color.from(
        alpha: 1,
        red: _lights[o + 4],
        green: _lights[o + 5],
        blue: _lights[o + 6],
      );
      _plainLight.shader = Gradient.radial(
        Offset.zero,
        1,
        [
          color.withValues(alpha: a),
          color.withValues(alpha: a * (0.2 + 0.4 * haze)),
          color.withValues(alpha: 0),
        ],
        const [0, 0.4, 1],
      );
      canvas
        ..save()
        ..translate(_lights[o], _lights[o + 1])
        ..scale(2.5 * sx, 2.5 * sy)
        ..drawCircle(Offset.zero, 1, _plainLight)
        ..restore();
    }
    canvas.restore();
  }

  final Paint _plainLight = Paint()..blendMode = BlendMode.plus;

  /// A 1x1 image for the sampler the lights mode does not read.
  static Image? _blank;
  static Image _makeBlank() {
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

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
  final _ShaderSlot _lightSlot = _ShaderSlot();
  final Paint _shaderPaint = Paint();
  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _smear = Paint();
  final Paint _area = Paint();
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
    final x = worldPoint.x - origin.x;
    final y = worldPoint.y - origin.y;
    ripples.add(x, y, strength: strength);
    final waves = _waves;
    if (waves != null) {
      _splashes++;
      waves.drop(
        x / size.x,
        y / size.y,
        radius: _dropCells,
        depth: strength / math.sqrt(math.max(1, _overlap)),
      );
    }
  }

  /// Splashes since the last update, and how many land a second, smoothed.
  int _splashes = 0;
  double _splashRate = 0;

  /// How many drops' waves cross a point at once: the drops landing a
  /// second on a ring's area, times how long a ring lasts. Their waves add
  /// up at random, as the square root of how many; each drop's is made that
  /// much smaller, so heavy rain stirs the surface about as much as one ring
  /// does, the way the rings (the newest few) do.
  double get _overlap {
    final plan = size.x * size.y / ripples.flatten;
    if (plan <= 0) {
      return 1;
    }
    final ring = math.pi * ripples.maxRadius * ripples.maxRadius;
    return _splashRate / plan * ring * ripples.lifeSec;
  }

  /// Whether the surface moves by the wave equation on the GPU rather than
  /// by its rings: at [WaterQuality.rippled], where flutter_gpu is on. Off
  /// for a surface that should keep to the rings.
  bool gpuWaves = true;

  WaveField? _waves;
  bool _wavesAsked = false;
  double _waveSteps = 0;

  /// The field's cell, local units: a sixth of the rings' wavelength (any
  /// coarser and a ring comes out many-sided), or more for a big surface,
  /// 256 cells at most each way.
  double get _cell {
    final plan = math.max(size.x, size.y / ripples.flatten);
    return math.max(wavelength / 6, plan / 256);
  }

  /// A drop's dent, cells across: wide enough to come out round.
  static const double _dropCells = 2.5;

  /// Steps of the wave equation a second: a wave in it crosses 1/sqrt(2) of
  /// a cell a step, and should go as fast as a ring grows.
  double get _stepsPerSecond =>
      ripples.maxRadius / ripples.lifeSec / (math.sqrt1_2 * _cell);

  /// Starts making the field once the surface has a size.
  void _askForWaves() {
    if (_wavesAsked || !gpuWaves || quality != WaterQuality.rippled) {
      return;
    }
    if (size.x <= 0 || size.y <= 0 || WaveField.available == false) {
      return;
    }
    _wavesAsked = true;
    final cell = _cell;
    WaveField.create(
      columns: (size.x / cell).ceil().clamp(2, 256),
      rows: (size.y / ripples.flatten / cell).ceil().clamp(2, 256),
    ).then((field) {
      if (isRemoved || isRemoving) {
        field?.dispose();
        return;
      }
      _waves = field;
    });
  }

  void _stepWaves(double dt) {
    final waves = _waves;
    if (waves == null) {
      return;
    }
    if (dt > 0) {
      final k = 1 - math.exp(-dt);
      _splashRate += (_splashes / dt - _splashRate) * k;
    }
    _splashes = 0;
    final rate = _stepsPerSecond;
    _waveSteps += dt * rate;
    // A slow frame skips steps rather than taking a burst of them.
    final steps = _waveSteps.floor().clamp(0, 6);
    _waveSteps -= _waveSteps.floor();
    // A ring fades out over its life; the field's waves, which spread and
    // cross, over twice that.
    final damping = math
        .pow(
          0.05,
          1 / (2 * ripples.lifeSec * rate),
        )
        .toDouble();
    waves.step(steps, damping: damping);
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
    _askForWaves();
    _stepWaves(dt);
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
      if (!_ringsLit && _waves?.heights == null) {
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
    // lights; without one they are drawn here.
    if (!_ringsLit) {
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
    return depth == null ? null : _projection?.yAt(depth);
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
  /// at the rim; the crests glint.
  void _throughShader(
    Canvas canvas,
    _ShaderSlot slot,
    FragmentProgram program,
    Rect rect,
    void Function(Canvas canvas) record, {
    required double gain,
    required Paint paint,
    required Color base,
    required Color tint,
    required double fade,
    required double line,
  }) {
    // The smear is done in the shader: the image need be no finer than it.
    // Under half a pixel of smear is none; above, the image need be no finer
    // than a few pixels a sigma.
    final pixels = streak / 3 * resolution;
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
    final f = _uniforms(slot, gain: gain, line: line)
      ..[WaterShader.fade] = fade
      ..[WaterShader.pixels] = scale;
    WaterShader.color(f, WaterShader.base, base);
    WaterShader.color(f, WaterShader.tint, tint);
    WaterShader.color(f, WaterShader.glint, _ringPaint().color);
    WaterShader.upload(shader, f);
    shader
      ..setImageSampler(0, image, filterQuality: FilterQuality.low)
      // Unfiltered (the default): not every GPU filters a float texture.
      // With no field the slot still needs an image; the shader does not
      // read it.
      ..setImageSampler(1, _waves?.heights ?? image);
    canvas.drawRect(rect, paint..shader = shader);
  }

  /// The uniforms both modes share - the surface, its rings and field, how
  /// it is seen, its outline - in [slot]'s array, the rest cleared.
  Float32List _uniforms(
    _ShaderSlot slot, {
    required double gain,
    required double line,
  }) {
    final f = slot.uniforms..fillRange(0, slot.uniforms.length, 0);
    final view = _view();
    final pool = outline().getBounds();
    final waves = _waves;
    f
      ..[WaterShader.size] = size.x
      ..[WaterShader.size + 1] = size.y
      ..[WaterShader.flatten] = ripples.flatten
      ..[WaterShader.wavelength] = wavelength
      ..[WaterShader.gain] = gain
      ..[WaterShader.time] = _time
      ..[WaterShader.chop] = chop
      ..[WaterShader.elevTop] = view?.top ?? 0
      ..[WaterShader.elevBottom] = view?.bottom ?? 0
      ..[WaterShader.fresnel] = view == null ? 0 : 1
      ..[WaterShader.spread] = streak / 3
      ..[WaterShader.line] = line
      ..[WaterShader.pool] = pool.center.dx
      ..[WaterShader.pool + 1] = pool.center.dy
      ..[WaterShader.poolHalf] = pool.width / 2
      ..[WaterShader.poolHalf + 1] = pool.height / 2
      ..[WaterShader.soft] = _softEdge ? edgeSoftness.clamp(0.0, 1.0) : 0
      ..[WaterShader.round] = shape == WaterShape.ellipse ? 1 : 0
      ..[WaterShader.wave] = waves?.heights == null ? 0 : 1
      ..[WaterShader.wave + 1] = waves == null ? 0 : 1 / waves.columns
      ..[WaterShader.wave + 2] = waves == null ? 0 : 1 / waves.rows
      ..[WaterShader.wave + 3] = waveAmplitude * waveGain
      ..[WaterShader.squash] = squash;
    var count = 0;
    ripples.forEachNewest(WaterShader.maxRings, (x, y, radius, opacity) {
      f
        ..[WaterShader.rings + count * 4] = x
        ..[WaterShader.rings + count * 4 + 1] = y
        ..[WaterShader.rings + count * 4 + 2] = radius
        ..[WaterShader.rings + count * 4 + 3] = waveAmplitude * opacity;
      count++;
    });
    f[WaterShader.count] = count.toDouble();
    return f;
  }

  @override
  void onRemove() {
    _sceneSlot.dispose();
    _lightSlot.dispose();
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
  final Float32List uniforms = Float32List(WaterShader.floats);

  void dispose() {
    image?.dispose();
    image = null;
  }
}
