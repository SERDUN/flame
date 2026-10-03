import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
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
    this.glow,
    this.metre = 1,
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
  double? glow;

  @override
  double metre;

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
    final air = _airLights;
    final image = air ?? _castLights ?? _lightImage;
    if (image == null) {
      return null;
    }
    if (identical(_softOf, image)) {
      return _soft;
    }
    // The light in the air is made at an eighth of a metre a pixel: twice
    // halved, half a metre.
    final current = _halved(image, air != null ? 2 : 5);
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
      _airLights?.dispose();
    }
    _castLights = null;
    _airLights = null;
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
      _airLights?.dispose();
    }
    _castLights = null;
    _airLights = null;
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
    // The light in the air: it fills the air between the eye and the
    // street line, where a thing's shadow is as deep as the thing is thick
    // against that air - next to none of a post or a walker. An eighth of a
    // metre a pixel, whatever the screen: it is blurred to half a metre
    // ([lightImageSoft]), and a pixel of a screen's fraction was as wide as
    // a lamp on a small one - its glow a square peaking wherever the pixel
    // fell, not at the lamp.
    final air = frame.projection?.farDistance ?? 0;
    // How far one sees through it, in the world's units: how much a lamp's
    // glow near it counts against the whole air's.
    final visibility = frame.weather.visibilityM * metre;
    final airPixels = _airPixelsPerMetre / math.max(metre, 1e-9);
    final airW = math.max(1, (view.width * airPixels).ceil());
    final airH = math.max(1, (view.height * airPixels).ceil());
    if (buffer != null && useBuffer) {
      _lightImage = buffer.render(frame, view, w, h);
      if (air > 0) {
        _airLights = buffer.render(
          frame,
          view,
          airW,
          airH,
          air: air,
          visibility: visibility,
          slot: _airSlot,
        );
      }
      _lightGain = 1;
      _alphaIsWhite = true;
    } else if (LightShader.shader != null) {
      final (:lights, :all) = _castImages(frame, view, w, h);
      _castLights = lights;
      _lightImage = all;
      if (air > 0) {
        final (lights: airLights, :all) = _castImages(
          frame,
          view,
          airW,
          airH,
          air: air,
          visibility: visibility,
        );
        all.dispose();
        _airLights = airLights;
      }
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
    // A cut gone since leaves its slot: let go of it.
    if (buffer != null && useBuffer) {
      buffer.releaseSlotsFrom(cuts.length + 1);
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
    double air = 0,
    double visibility = 1e9,
  }) {
    final field = frame.light;
    final lights = PictureRecorder();
    final into = Canvas(lights)
      ..scale(w / view.width, h / view.height)
      ..translate(-view.left, -view.top);
    for (var i = 0; i < field.count; i++) {
      _cast(
        into,
        frame,
        i,
        _add,
        1 / canvasGain,
        wallAhead: wall,
        air: air,
        visibility: visibility,
      );
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
      _glowItself(over, field, i, scale: 1 / (e * canvasGain));
    }
    return (lights: cast, all: all.endRecording().toImageSync(w, h));
  }

  /// The canvas path's lights alone ([_castImages]).
  Image? _castLights;

  /// The light filling the air between the eye and the street line, at
  /// [_airPixelsPerMetre]: what [lightImageSoft] is made from.
  Image? _airLights;

  /// How fine [_airLights] is: eight pixels a metre.
  static const double _airPixelsPerMetre = 8;

  /// The buffer slot the light in the air is rendered into: none of the
  /// cuts' (1 up).
  static const int _airSlot = -1;

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

  /// Draws [draw] onto [canvas] as it is, out of the lighting's multiply:
  /// for what does not show the light falling where it lies - water, which
  /// shows what it mirrors as lit where that stands, and the sky where
  /// nothing stands.
  ///
  /// What the world drew so far is lit first, as the lighting lights it,
  /// and laid down; [draw] goes over it; what draws after goes into a new
  /// layer, lit by the lighting in its turn. A call inside [draw] draws
  /// straight.
  ///
  /// Only a world lit in a layer of its own ([lightsBackdrop] off) can
  /// leave something out of the multiply; otherwise, and in a frame with no
  /// light to multiply by, [draw] is drawn with the world.
  void unlit(Canvas canvas, void Function() draw) {
    // A picture of the world drawn apart from it (a mirror's) has layers of
    // its own: out of its multiply, not the world's.
    if (LitPicture._drawing) {
      final picture = LitPicture._current;
      if (picture == null) {
        draw();
      } else {
        picture._unlit(canvas, draw);
      }
      return;
    }
    final layer = _litLayer;
    final frame = stage?.frame;
    if (_unlitDepth > 0 ||
        layer == null ||
        layer._openAt == null ||
        frame == null ||
        !frame.light.isLit) {
      draw();
      return;
    }
    final view = frame.view.inflate(frame.view.width * 0.01);
    _unlitDepth++;
    try {
      layer._turnWith(
        canvas,
        light: () {
          // What the layer holds stands where the cut that would light it
          // says: the next one still to come, or the street line.
          final cut = _cutAhead();
          if (cut != null && cut._image != null) {
            cut._light(canvas, view);
          } else if (_lightImage != null) {
            _drawBuffer(canvas, view, _illumination, frame.light, mode: 0);
          } else {
            _illuminateAll(canvas, frame, view);
          }
        },
        draw: draw,
      );
    } finally {
      _unlitDepth--;
    }
  }

  int _unlitDepth = 0;

  /// The first of the stage's cuts not drawn yet in this drawing of the
  /// world: the one that lights what the world drew since the last; `null`
  /// past the last cut. Asked by the frame's index instead, a frame drawn
  /// a second time found every cut drawn already, and lit what stands
  /// behind the street line - a tree far back - as on the street line,
  /// near the lamps: every other drawing of the frame, it blinked.
  LitCut? _cutAhead() {
    LitCut? ahead;
    for (final cut in stage?.members<LitCut>() ?? const <LitCut>[]) {
      if (cut._turnedAt == stage?.drawing) {
        continue;
      }
      if (ahead == null || cut.priority < ahead.priority) {
        ahead = cut;
      }
    }
    return ahead;
  }

  /// Multiplies what [canvas] holds over [area] by the light falling on
  /// the street line: the sky's and every light's as it is cast, with no
  /// glow of a source itself and no halo - what lights a picture of the
  /// world drawn apart from it ([LitPicture]).
  void _illuminateSurfaces(Canvas canvas, Rect area) {
    final frame = stage?.frame;
    if (frame == null) {
      return;
    }
    final field = frame.light;
    final cast = _castLights ?? _lightImage;
    if (cast != null) {
      // The GPU buffer's alpha is the white of what glows itself, the
      // canvas path's cast image has none: both read without it.
      _drawBuffer(
        canvas,
        area,
        _illumination,
        field,
        mode: 0,
        image: cast,
        alphaIsWhite: false,
      );
      return;
    }
    final e = field.exposure;
    canvas
      ..saveLayer(area, _illumination)
      ..drawRect(
        area,
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
    }
    canvas.restore();
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
      _glowItself(canvas, field, i);
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
    double air = 0,
    double visibility = 1e9,
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
    // Over hills the street line rises and falls across the light's reach:
    // the wall reaches down to its lowest, the ground up to its highest, and
    // the shader keeps each to its own side.
    final (low, high) =
        projection?.lift.rangeIn(reach.left, reach.right) ?? (0.0, 0.0);
    final wall = line == null
        ? reach
        : reach.intersect(
            Rect.fromLTRB(reach.left, reach.top, reach.right, line - low),
          );
    final planes = [
      if (!wall.isEmpty) (LightPlane.wall, wall),
      if (projection != null && line != null)
        (
          LightPlane.ground,
          reach.intersect(
            Rect.fromLTRB(
              reach.left,
              line - high,
              reach.right,
              projection.band.bottom - low,
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
        air: air,
        visibility: visibility,
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
  /// halo the haze makes round it, a share of it as it is drawn.
  void _glowItself(
    Canvas canvas,
    LightField field,
    int i, {
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
    // Its halo: a share of the source as it is drawn (as much as [scale]),
    // never brighter than it, whatever the eye's exposure.
    final a = (field.haze * math.min(field.strengthOf(i), 1.0) * 0.6 * scale)
        .clamp(
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
  void render(Canvas canvas) => _open(canvas);

  void _close(Canvas canvas) {
    final at = _openAt;
    if (at == null) {
      return;
    }
    _openAt = null;
    canvas.restoreToCount(at);
  }

  /// Lights what is in the layer with [light], lays it over what is below
  /// it, draws [draw] over that as it is, and opens the next.
  ///
  /// Whoever asks is drawing inside its own saves (a placed component's
  /// transform): [light] runs in the world's transform, as the layer was
  /// opened in; those saves are closed with the layer, so [draw] runs in
  /// the asker's transform put back, and the canvas is left as deep as it
  /// was, in that transform, the new layer under it.
  void _turnWith(
    Canvas canvas, {
    required void Function() light,
    required void Function() draw,
  }) {
    final at = _openAt;
    if (at == null) {
      draw();
      return;
    }
    final depth = canvas.getSaveCount();
    final inner = Matrix4.fromList(canvas.getTransform());
    final world = Matrix4.fromList(_openTransform);
    // From the asker's transform back to the world's, and on to the
    // asker's again.
    final toWorld = Float64List.fromList(
      (Matrix4.inverted(inner)..multiply(world)).storage,
    );
    final toInner = Float64List.fromList(
      (Matrix4.inverted(world)..multiply(inner)).storage,
    );
    canvas
      ..save()
      ..transform(toWorld);
    light();
    canvas
      ..restore()
      ..restoreToCount(at)
      ..save()
      ..transform(toInner);
    draw();
    canvas.restore();
    _open(canvas);
    for (var i = canvas.getSaveCount(); i < depth; i++) {
      canvas.save();
    }
    canvas.transform(toInner);
  }

  /// The world's transform when the layer was opened.
  Float64List _openTransform = Float64List(16);

  void _open(Canvas canvas) {
    _openAt = canvas.getSaveCount();
    _openTransform = canvas.getTransform();
    canvas.saveLayer(null, _paint);
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
class LitCut extends Component with OnStage, AtDepth {
  /// A cut placed by hand at [priority], lighting what is below it as it
  /// stands [ahead] of the street line. One placed by depth stands at the
  /// depth of what it lights ([LitCut.at]): a depth worked back from how far
  /// ahead it stands is a rounding off it.
  LitCut({
    required double Function() this._ahead,
    required int super.priority,
  }) : _depth = null,
       placedByDepth = false;

  /// A cut at the very [depth] what it lights stands at (a parallax layer's,
  /// `StreetProjection.depthOfScale`): drawn after it, as [depthOrder] says,
  /// every frame. A depth worked back from [ahead] comes out a rounding off
  /// it, now before it, now after - and what it lights blinks between lit
  /// where it stands and lit on the street line.
  LitCut.at(double Function() depth)
    : _depth = depth,
      _ahead = null,
      placedByDepth = true;

  final double Function()? _ahead;
  final double Function()? _depth;

  /// Placed at its depth unless given a priority outright.
  @override
  final bool placedByDepth;

  /// How far in front of the street line what is below it stands, in the
  /// world's units (behind it, negative).
  double ahead() {
    final ahead = _ahead;
    if (ahead != null) {
      return ahead();
    }
    return stage?.projection?.ahead(_depth!()) ?? 0;
  }

  Image? _image;
  bool _owned = false;
  double _gain = 1;
  bool _alphaIsWhite = true;

  /// The drawing of the world it last drew in ([Stage.drawing]).
  int _turnedAt = -1;

  /// It lights what is at its depth and behind it: drawn after all of that.
  /// A cut placed by hand is not ordered by depth; it says where it stands.
  @override
  double depthIn(StreetProjection? projection) {
    final depth = _depth;
    if (depth != null) {
      return depth();
    }
    return projection?.depthAhead(ahead()) ?? 0;
  }

  @override
  DepthOrder get depthOrder => DepthOrder.light;

  void _set(Image? image, {bool owned = false}) {
    if (_owned) {
      _image?.dispose();
    }
    // With no lighting to draw it, an image of its own is let go now: kept,
    // it would never be.
    if (Lighting.of(this) == null) {
      if (owned) {
        image?.dispose();
      }
      _image = null;
      _owned = false;
      return;
    }
    _image = image;
    _owned = owned;
    _gain = owned ? Lighting.canvasGain : 1;
    _alphaIsWhite = !owned;
  }

  @override
  void render(Canvas canvas) {
    final lighting = Lighting.of(this);
    final layer = lighting?._litLayer;
    final frame = stage?.frame;
    _turnedAt = stage?.drawing ?? -1;
    if (lighting == null || layer == null || _image == null || frame == null) {
      return;
    }
    _light(canvas, frame.view.inflate(frame.view.width * 0.01));
    layer._turn(canvas);
  }

  /// Multiplies what [canvas] holds over [view] by the light where what is
  /// below it stands.
  void _light(Canvas canvas, Rect view) {
    final lighting = Lighting.of(this);
    final image = _image;
    final frame = stage?.frame;
    if (lighting == null || image == null || frame == null) {
      return;
    }
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
  }

  /// Multiplies what [canvas] holds over [area] by the light falling where
  /// what is below it stands, as it is cast, with no glow of a source
  /// itself where the light's image keeps that apart ([LitPicture]).
  void _illuminateSurfaces(Canvas canvas, Rect area) {
    final lighting = Lighting.of(this);
    final image = _image;
    final frame = stage?.frame;
    if (lighting == null || image == null || frame == null) {
      return;
    }
    lighting._drawBuffer(
      canvas,
      area,
      lighting._illumination,
      frame.light,
      mode: 0,
      image: image,
      gain: _gain,
      alphaIsWhite: false,
    );
  }

  @override
  void onRemove() {
    _set(null);
    super.onRemove();
  }
}

/// Lights a picture of the world drawn apart from it - what a mirror shows
/// - as the world is lit: what stands behind the street line where it
/// stands ([LitCut]), the rest on the line ([Lighting]), by the light that
/// falls on it. The lights themselves, their glow and their halos are left
/// out: a mirror shows those from the lights ([LightReflector]), with the
/// streaks a rough surface draws them into.
///
/// The picture is drawn in the world's coordinates, through whatever
/// transform mirrors it: the light is read where each thing stands, and
/// lands where its image does. The world's components are handed to [step]
/// in the order they draw; the lighting's own (its layer, its cuts, itself)
/// are done there and not drawn.
class LitPicture {
  LitPicture._(this._lighting, this._area);

  final Lighting _lighting;
  final Rect _area;
  int? _openAt;
  Float64List _openTransform = Float64List(16);
  final Set<LitCut> _passed = {};

  static bool _drawing = false;
  static LitPicture? _current;

  /// Runs [draw], which draws a picture of the world apart from it, lit by
  /// [picture] (`null`: not lit). Inside it what draws out of the
  /// lighting's multiply ([Lighting.unlit]) does so in the picture's own
  /// layers, and leaves the world's alone.
  static void apart(LitPicture? picture, void Function() draw) {
    final drawing = _drawing;
    final current = _current;
    _drawing = true;
    _current = picture;
    try {
      draw();
    } finally {
      _drawing = drawing;
      _current = current;
    }
  }

  int _unlitDepth = 0;

  /// [Lighting.unlit] in the picture: what it holds so far lit and laid
  /// down, [draw] over it as it is, the next layer opened - in the asker's
  /// transform and as deep as it was, as the world's lit layer does it.
  void _unlit(Canvas canvas, void Function() draw) {
    final at = _openAt;
    if (at == null || _unlitDepth > 0) {
      draw();
      return;
    }
    final depth = canvas.getSaveCount();
    final inner = Matrix4.fromList(canvas.getTransform());
    final world = Matrix4.fromList(_openTransform);
    final toWorld = Float64List.fromList(
      (Matrix4.inverted(inner)..multiply(world)).storage,
    );
    final toInner = Float64List.fromList(
      (Matrix4.inverted(world)..multiply(inner)).storage,
    );
    canvas
      ..save()
      ..transform(toWorld);
    // Lit where it stands: by the next cut still to come, or on the line.
    LitCut? ahead;
    for (final cut in _lighting.stage?.members<LitCut>() ?? const <LitCut>[]) {
      if (_passed.contains(cut)) {
        continue;
      }
      if (ahead == null || cut.priority < ahead.priority) {
        ahead = cut;
      }
    }
    if (ahead != null) {
      ahead._illuminateSurfaces(canvas, _area);
    } else {
      _lighting._illuminateSurfaces(canvas, _area);
    }
    canvas
      ..restore()
      ..restoreToCount(at)
      ..save()
      ..transform(toInner);
    _unlitDepth++;
    try {
      draw();
    } finally {
      _unlitDepth--;
    }
    canvas.restore();
    _open(canvas);
    for (var i = canvas.getSaveCount(); i < depth; i++) {
      canvas.save();
    }
    canvas.transform(toInner);
  }

  static final Paint _paint = Paint();

  /// For a picture of the world [lighting] lights, over [area] of the world
  /// (before any mirroring); `null` when there is nothing to light it by -
  /// no lighting, no light this frame - or when the world is not lit in a
  /// layer of its own: then the picture is lit with whatever it lands in.
  static LitPicture? of(Lighting? lighting, Rect area) {
    final frame = lighting?.stage?.frame;
    if (lighting == null ||
        lighting._litLayer == null ||
        frame == null ||
        !frame.light.isLit) {
      return null;
    }
    return LitPicture._(lighting, area);
  }

  /// Whether [component] is a step of the lighting rather than a thing in
  /// the world: its layer, a cut, the lighting itself.
  static bool isPass(Component component) =>
      component is Lighting || component is LitLayer || component is LitCut;

  /// Does [component]'s part of the lighting on [canvas] if it is one of
  /// the lighting's steps ([isPass]), and says whether it was.
  bool step(Canvas canvas, Component component) {
    switch (component) {
      case LitLayer():
        _open(canvas);
      case LitCut():
        _passed.add(component);
        if (_openAt != null) {
          component._illuminateSurfaces(canvas, _area);
          _close(canvas);
          _open(canvas);
        }
      case Lighting():
        finish(canvas);
      default:
        return false;
    }
    return true;
  }

  /// Lights what is still unlit on the street line and lays it down: the
  /// lighting's own step, or the picture's end if the lighting was not
  /// reached.
  void finish(Canvas canvas) {
    if (_openAt == null) {
      return;
    }
    _lighting._illuminateSurfaces(canvas, _area);
    _close(canvas);
  }

  void _open(Canvas canvas) {
    _openAt = canvas.getSaveCount();
    _openTransform = canvas.getTransform();
    canvas.saveLayer(null, _paint);
  }

  void _close(Canvas canvas) {
    final at = _openAt;
    if (at != null) {
      canvas.restoreToCount(at);
    }
    _openAt = null;
  }
}
