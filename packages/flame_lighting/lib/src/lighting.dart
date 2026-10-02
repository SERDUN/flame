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
    this.adaptsIn = 0,
    double? darkAdaptsIn,
    this.glow = 0.35,
    this.haze,
    this.useBuffer = true,
    this.bufferScale = 0.5,
    this.lightsBackdrop = true,
    super.priority = 1000,
  }) : darkAdaptsIn = darkAdaptsIn ?? 4 * adaptsIn;

  /// Whether the lights fall on what was drawn before the world (a sky in
  /// the camera's backdrop). Off, the world below the lighting's priority is
  /// drawn into a layer of its own ([LitLayer], added beside the lighting),
  /// lit there, and only then laid over the backdrop: a lamp's cone and the
  /// shadows in it fall on what stands in the street, not on the sky behind
  /// it, which is no wall. The light in the air still glows over it, soft.
  final bool lightsBackdrop;
  LitLayer? _litLayer;

  @override
  Color sky;

  @override
  double skyLight;

  @override
  double adaptation;

  @override
  double glow;

  @override
  double adaptsIn;

  @override
  double darkAdaptsIn;

  /// How thick the air is, `0..1`; `null`: as the stage's weather makes it.
  @override
  double? haze;

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

  /// This frame's light buffer - every light added up where it falls, with
  /// its shadows, unexposed - and the world rect it covers; null without a
  /// buffer.
  Image? get lightImage => _lightImage;
  Rect get lightArea => _lightArea;

  /// [lightImage] at a thirty-second of its size each way, over the same
  /// [lightArea]: the light as it fills the air, half a metre soft in a
  /// world in metres. Light in the air is scattered all through its depth,
  /// so a thin post throws next to no shadow in it and a cone has no edge;
  /// and a wet road blurs what it mirrors. A mirror reads the light in the
  /// air from this. Made once a frame, when first asked for.
  Image? get lightImageSoft {
    final image = _castLights ?? _lightImage;
    if (image == null) {
      return null;
    }
    if (identical(_softOf, image)) {
      return _soft;
    }
    final current = _halved(image, 5);
    _soft?.dispose();
    _soft = current;
    _softOf = image;
    return _soft;
  }

  /// [image] halved [times] times, each a bilinear 2 x 2 average: a true
  /// box filter whether or not the image has mipmaps (one step down by many
  /// would only pick a few of the pixels, and a thin shadow could survive).
  /// Disposes what it makes on the way, not [image].
  static Image _halved(Image image, int times) {
    var current = image;
    for (var step = 0; step < times; step++) {
      final w = math.max(1, current.width ~/ 2);
      final h = math.max(1, current.height ~/ 2);
      final recorder = PictureRecorder();
      Canvas(recorder).drawImageRect(
        current,
        Rect.fromLTWH(
          0,
          0,
          current.width.toDouble(),
          current.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        _softPaint,
      );
      final next = recorder.endRecording().toImageSync(w, h);
      if (!identical(current, image)) {
        current.dispose();
      }
      current = next;
    }
    return current;
  }

  Image? _soft;
  Image? _softOf;
  static final Paint _softPaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void onMount() {
    super.onMount();
    if (!lightsBackdrop && _litLayer == null) {
      parent!.add(_litLayer = LitLayer._(this));
    }
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
    if (_ownsImage) {
      _lightImage?.dispose();
      _castLights?.dispose();
    }
    _castLights = null;
    _ownsImage = false;
    _lightImage = null;
    _litLayer?.removeFromParent();
    _litLayer = null;
    _soft?.dispose();
    _soft = null;
    _softOf = null;
    super.onRemove();
  }

  /// Adds the frame's lights up into the buffer, before anything draws,
  /// so a wet wall drawn before the night reads this frame's light.
  @override
  void prepareFrame(Canvas canvas, StageFrame frame) {
    if (_ownsImage) {
      _lightImage?.dispose();
      _castLights?.dispose();
    }
    _castLights = null;
    _lightImage = null;
    _ownsImage = false;
    for (final cut in stage?.members<LitCut>() ?? const <LitCut>[]) {
      cut._set(null);
    }
    if (LightShader.compose == null) {
      return;
    }
    if (!frame.light.isLit || frame.light.count == 0) {
      return;
    }
    final view = frame.view.inflate(frame.view.width * 0.01);
    final m = canvas.getTransform();
    final pixels = math.sqrt(m[0] * m[0] + m[1] * m[1]) * bufferScale;
    final w = math.max(1, (view.width * pixels).ceil());
    final h = math.max(1, (view.height * pixels).ceil());
    _lightArea = view;
    final buffer = _buffer;
    if (buffer != null && useBuffer) {
      _lightImage = buffer.render(frame, view, w, h);
      _lightGain = 1;
      _alphaIsWhite = true;
    } else if (LightShader.shader != null) {
      final (:lights, :all) = _castImages(frame, view, w, h);
      _castLights = lights;
      _lightImage = all;
      _ownsImage = true;
      _lightGain = canvasGain;
      _alphaIsWhite = false;
    }
    // Each cut's plane: what stands behind the street line lit where it
    // stands.
    if (lightsBackdrop || _lightImage == null) {
      return;
    }
    final cuts = stage?.members<LitCut>() ?? const <LitCut>[];
    for (final (k, cut) in cuts.indexed) {
      final wall = cut.ahead();
      if (buffer != null && useBuffer) {
        cut._set(
          buffer.render(frame, view, w, h, wallAhead: wall, slot: k + 1),
        );
      } else {
        final (:lights, :all) = _castImages(frame, view, w, h, wall: wall);
        lights.dispose();
        cut._set(all, owned: true);
      }
    }
  }

  /// Without the GPU buffer, the same light on the canvas, in two images
  /// (an 8-bit image cannot hold colour past its alpha, so it cannot keep
  /// the buffer's white light apart): [_castLights], the lights cast on
  /// their planes - what the light in the air and the mirrors read, as they
  /// read the buffer's colour - and the illumination, those with what glows
  /// itself and the haze's halo round it added as white. Both at a
  /// [canvasGain]th of the light, so an 8-bit image holds it.
  ({Image lights, Image all}) _castImages(
    StageFrame frame,
    Rect view,
    int w,
    int h, {
    double wall = 0,
  }) {
    final field = frame.light;
    final lights = PictureRecorder();
    final into = Canvas(lights)
      ..scale(w / view.width, h / view.height)
      ..translate(-view.left, -view.top);
    for (var i = 0; i < field.count; i++) {
      _cast(into, frame, i, _add, 1 / canvasGain, wallAhead: wall);
    }
    final cast = lights.endRecording().toImageSync(w, h);
    final all = PictureRecorder();
    final over = Canvas(all)..drawImage(cast, Offset.zero, Paint());
    over
      ..scale(w / view.width, h / view.height)
      ..translate(-view.left, -view.top);
    // What glows itself as bright as it is drawn whatever the exposure (as
    // the buffer has it), its halo as much light as it is.
    final e = math.max(field.exposure, 1e-6);
    for (var i = 0; i < field.count; i++) {
      _glowItself(over, field, i, 1 / canvasGain, scale: 1 / (e * canvasGain));
    }
    return (lights: cast, all: all.endRecording().toImageSync(w, h));
  }

  /// The canvas path's lights alone ([_castImages]).
  Image? _castLights;

  /// How many times the light the canvas path's image holds is its value:
  /// a lamp's light near it is several times white before the eye's
  /// exposure, and an 8-bit image stops at one.
  static const double canvasGain = 4;

  bool _ownsImage = false;
  double _lightGain = 1;

  /// Whether [lightImage]'s alpha is white light (the buffer's) or its
  /// coverage (the canvas path's, with the white already in its colour).
  bool _alphaIsWhite = true;

  /// How many times its value the light in [lightImage] is (1 for the GPU
  /// buffer, [canvasGain] for the canvas path's image).
  double get lightGain => _lightGain;

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
    Image? image,
    double? gain,
    bool? alphaIsWhite,
  }) {
    final g = gain ?? _lightGain;
    final white = alphaIsWhite ?? _alphaIsWhite;
    final shader = LightShader.compose!;
    image ??= _lightImage!;
    final a = _lightArea;
    shader
      ..setFloat(0, a.left)
      ..setFloat(1, a.top)
      ..setFloat(2, a.width)
      ..setFloat(3, a.height)
      ..setFloat(4, field.skyRed / g)
      ..setFloat(5, field.skyGreen / g)
      ..setFloat(6, field.skyBlue / g)
      ..setFloat(7, field.exposure * g)
      ..setFloat(8, mode.toDouble())
      ..setFloat(9, amount * g)
      ..setFloat(10, white ? 0 : 1)
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
    if (frame == null || !frame.light.isLit) {
      _litLayer?._close(canvas);
      return;
    }
    final field = frame.light;
    // A little past the view, so nothing shows at its edge.
    final view = frame.view.inflate(frame.view.width * 0.01);
    final e = field.exposure;
    if (_lightImage != null) {
      _drawBuffer(canvas, view, _illumination, field, mode: 0);
    } else {
      _illuminateAll(canvas, frame, view);
    }
    for (final mirror in stage!.members<LightReflector>()) {
      mirror.renderReflectedLights(canvas, frame);
    }
    // The world lit, laid over the backdrop; the light in the air over both.
    _litLayer?._close(canvas);
    if (field.glow > 0) {
      final soft = lightImageSoft;
      if (soft != null) {
        // Light in the air is scattered all through its depth: soft, with
        // no edge to a cone and next to no shadow of a thin post in it.
        _drawBuffer(
          canvas,
          view,
          _add,
          field,
          mode: 1,
          amount: field.glow * e,
          image: soft,
        );
      } else {
        // No shaders: each light in the air as it is cast.
        for (var i = 0; i < field.count; i++) {
          _cast(canvas, frame, i, _add, field.glow * e);
        }
      }
    }
  }

  /// Without shaders: the illumination built in a layer - the sky's light,
  /// every light added on each plane, what glows itself and its halo - and
  /// multiplied onto the scene, clamped at white.
  void _illuminateAll(Canvas canvas, StageFrame frame, Rect view) {
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
    double wallAhead = 0,
  }) {
    final field = frame.light;
    final view = frame.view.inflate(frame.view.width * 0.01);
    final bounds = _bounds(field, i);
    if (!bounds.overlaps(view)) {
      return;
    }
    final reach = bounds.intersect(view);
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
        wall: wallAhead,
      );
      canvas.drawRect(area, paint..shader = shader);
      paint.shader = null;
    }
  }

  /// Where light [i] can reach on screen: the sun everywhere.
  Rect _bounds(LightField field, int i) {
    if (field.isSunOf(i)) {
      return Rect.largest;
    }
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
    final color = field.colorOf(i);
    if (field.isSunOf(i)) {
      paint
        ..shader = null
        ..color = color.withValues(alpha: a);
      canvas.drawRect(area, paint);
      return;
    }
    final center = Offset(field.xOf(i), field.yOf(i));
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
  void _glowItself(
    Canvas canvas,
    LightField field,
    int i,
    double exposure, {
    double scale = 1,
  }) {
    // Fully lit, as much as [scale] of white (the canvas path's image holds
    // a fraction of the light).
    final white = Color.fromRGBO(255, 255, 255, scale);
    if (field.isSunOf(i)) {
      // The sun is not in the scene.
      return;
    }
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
            ..color = white,
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
            ..color = white
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(source, field.extentXOf(i) * 0.02),
        );
        _emit.style = PaintingStyle.fill;
      case LightShape.directional:
        break;
      case LightShape.point:
      case LightShape.cone:
        if (source > 0) {
          // As the bulb is drawn: full to 0.55 of 1.6 source radii.
          _emit.shader = Gradient.radial(
            center,
            source * 1.6,
            [white, white, const Color(0x00FFFFFF)],
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
    // No closer than a two-hundredth of the wet area, whatever its units.
    final every = math.max(wet.rivuletSpacing, bounds.width / 200);
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

/// The layer the world is drawn into under a [Lighting] that spares the
/// backdrop ([Lighting.lightsBackdrop] off): opened before anything of the
/// world draws, closed by the lighting once it has lit what is in it. What
/// the layer leaves empty stays empty under the lighting's multiply, so the
/// backdrop shows through unlit.
class LitLayer extends Component {
  LitLayer._(this.lighting) : super(priority: -(1 << 30));

  /// The lighting that closes it.
  final Lighting lighting;

  int? _openAt;
  static final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    _openAt = canvas.getSaveCount();
    canvas.saveLayer(null, _paint);
  }

  void _close(Canvas canvas) {
    final at = _openAt;
    if (at == null) {
      return;
    }
    _openAt = null;
    canvas.restoreToCount(at);
  }

  /// Lays what is in the layer over what is below it and opens the next.
  void _turn(Canvas canvas) {
    final at = _openAt;
    if (at == null) {
      return;
    }
    canvas
      ..restoreToCount(at)
      ..saveLayer(null, _paint);
  }
}

/// A cut in the world's depth under a [Lighting] that spares the backdrop:
/// what was drawn below its priority stands [ahead] of the street line
/// (behind it, negative - a far layer of trees), and is lit there, by as
/// much of every light as reaches that far, shadows and all, then laid over
/// what is behind it; what draws above it is lit on the street line, by the
/// lighting. A lamp on the pavement does not light a tree twenty metres back
/// as it lights the wall behind it, nor lay a walker's shadow on it.
class LitCut extends Component with OnStage {
  LitCut({required this.ahead, super.priority});

  /// How far in front of the street line what is below it stands, in the
  /// world's units (behind it, negative).
  final double Function() ahead;

  Image? _image;
  bool _owned = false;
  double _gain = 1;
  bool _alphaIsWhite = true;

  void _set(Image? image, {bool owned = false}) {
    if (_owned) {
      _image?.dispose();
    }
    _image = image;
    _owned = owned;
    final lighting = Lighting.of(this);
    _gain = owned ? Lighting.canvasGain : 1;
    _alphaIsWhite = !owned;
    if (lighting == null) {
      _image = null;
    }
  }

  @override
  void render(Canvas canvas) {
    final lighting = Lighting.of(this);
    final layer = lighting?._litLayer;
    final image = _image;
    final frame = stage?.frame;
    if (lighting == null || layer == null || image == null || frame == null) {
      return;
    }
    final view = frame.view.inflate(frame.view.width * 0.01);
    lighting._drawBuffer(
      canvas,
      view,
      lighting._illumination,
      frame.light,
      mode: 0,
      image: image,
      gain: _gain,
      alphaIsWhite: _alphaIsWhite,
    );
    layer._turn(canvas);
  }

  @override
  void onRemove() {
    _set(null);
    super.onRemove();
  }
}
