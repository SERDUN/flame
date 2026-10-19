import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/light_shader.dart';
import 'package:flame_lighting/src/lighting.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The air between the eye and what stands at a depth: over everything at
/// that depth and behind it it lays as much of the air's own light as the
/// air from there to the next veil toward the eye takes of what is behind -
/// the eye's way through the stage's air field ([AirField]) summed pixel by
/// pixel (`shaders/air.frag`). With a veil at every depth things stand at,
/// each thing is seen through all the air between it and the eye: a far
/// forest pale in a light haze, gone in a fog; the feet in a ground fog and
/// the tree tops clear of it; one side of a fog bank's edge sharp, the other
/// lost.
///
/// It is light, not a surface: drawn out of the lighting's multiply
/// ([Lighting.unlit]) in the sky's light at the horizon as the eye sees it
/// (`StageFrame.sky`) - what the air's light becomes through more and more
/// of it. The lamps' light in it the lighting adds as their glow.
class AirVeil extends Component with OnStage, AtDepth, _LaysAir {
  AirVeil({
    required this.depth,
    this.nearer,
    this.resolution,
    this.pixelRatio,
  });

  /// The depth it stands at.
  final double Function() depth;

  /// The depth of the next veil toward the eye; `null`: the eye.
  final double? Function()? nearer;

  @override
  final double Function()? resolution;

  @override
  final double Function()? pixelRatio;

  @override
  double depthIn(StreetProjection? projection) => depth();

  @override
  DepthOrder get depthOrder => DepthOrder.air;

  @override
  Rect? _setUp(FragmentShader shader) =>
      _setUpAir(this, shader, depth: depth(), nearer: nearer?.call());
}

/// The air over the ground band: each row of it the air between the ground
/// there and the next veil nearer than it ([veils]), or the eye - water and
/// the road farther off paler than near. It lies over the ground and what
/// lies flat on it, under what stands on it ([DepthOrder.air] at the street
/// line, after the flat things there), and water does not mirror it.
class GroundAir extends Component with OnStage, AtDepth, LiesFlat, _LaysAir {
  GroundAir({required this.veils, this.resolution, this.pixelRatio});

  /// The depths of the veils in front of the street line, where each takes
  /// over the air nearer than it.
  final List<double> Function() veils;

  @override
  final double Function()? resolution;

  @override
  final double Function()? pixelRatio;

  @override
  double depthIn(StreetProjection? projection) => 0;

  @override
  DepthOrder get depthOrder => DepthOrder.air;

  @override
  Rect? _setUp(FragmentShader shader) =>
      _setUpAir(this, shader, veils: veils());
}

/// What lays air: where it lays it, and how fine.
mixin _LaysAir on OnStage {
  /// How finely the air is worked out against the pixels it lands on, each
  /// way, `0..1`; `null` or 1: at every pixel. Below 1 it is worked out on a
  /// grid that much coarser and stretched over its place (`_AirGrid`): the
  /// air changes slowly across the view - a haze, a bank's soft edge - and
  /// its shader, a sum along the eye's whole way for every pixel, is the
  /// dearest thing it draws. At a half, a quarter of the pixels.
  double Function()? get resolution;

  /// The pixels one unit of the canvas the game draws its world into holds
  /// at the root, before the camera: a game drawing straight onto the
  /// screen draws in logical pixels, and has the view's device pixel ratio
  /// of them; one drawing its world into a picture of the pixels it wants
  /// has 1. `null`: 1. [resolution] is a share of real pixels, so a grid
  /// worked out against logical ones would be that ratio coarser again.
  double Function()? get pixelRatio;

  /// The cells across and down of this air's grid in the last drawing;
  /// `null`: none ([resolution] 1, or it laid no air).
  @visibleForTesting
  Size? get gridCells {
    final stage = this.stage;
    final region = stage == null
        ? null
        : _AirGrid._grids[stage]?.regionOf(this);
    return region == null
        ? null
        : Size(region.src.width + 1, region.src.height + 1);
  }

  /// Sets [shader] up for this frame's air and says where it lays it, world
  /// coordinates; `null`: nowhere this frame.
  Rect? _setUp(FragmentShader shader);

  double get _share => (resolution?.call() ?? 1).clamp(0.05, 1).toDouble();

  @override
  void render(Canvas canvas) {
    final shader = LightShader.air;
    if (shader == null) {
      return;
    }
    final share = _share;
    if (share >= 1) {
      final area = _setUp(shader);
      if (area != null) {
        _layAir(this, canvas, () {
          canvas.drawRect(area, _paint..shader = shader);
        });
      }
      return;
    }
    final stage = this.stage;
    if (stage == null) {
      return;
    }
    final grid = _AirGrid.of(stage, canvas);
    final region = grid.regionOf(this);
    final image = grid.image;
    if (region == null || image == null) {
      return;
    }
    _layAir(this, canvas, () {
      canvas.drawImageRect(image, region.src, region.area, _stretch);
    });
  }
}

final Paint _paint = Paint();

/// Bilinear: the grid's cells blend into each other as the air does.
final Paint _stretch = Paint()..filterQuality = FilterQuality.low;

/// Lays [draw] - the air - over what is drawn, out of the lighting's
/// multiply.
void _layAir(OnStage owner, Canvas canvas, void Function() draw) {
  final lighting = Lighting.of(owner);
  if (lighting == null) {
    draw();
  } else {
    lighting.unlit(canvas, draw, by: owner);
  }
}

/// The air of every veil of a stage that is worked out coarser than its
/// pixels ([_LaysAir.resolution]), each on a grid of its own, all packed in
/// one picture made once a drawing of the world ([Stage.drawing]): one pass
/// off the screen for all of them rather than one each. The veils' places
/// are in the world, so a mirror's picture of the world, drawn in the same
/// drawing, reads the same grid.
class _AirGrid {
  _AirGrid._();

  static final Expando<_AirGrid> _grids = Expando();

  /// The stage's grid for this drawing, made if it is not yet: at the
  /// pixels a world unit [canvas] draws the world at, unless that is a
  /// picture of the world drawn apart (a mirror's, at its own pixels), when
  /// the world's own last known.
  factory _AirGrid.of(Stage stage, Canvas canvas) {
    final grid = _grids[stage] ??= _AirGrid._();
    if (grid._drawing != stage.drawing) {
      if (!LitPicture.drawingApart || grid._pixels == null) {
        final m = canvas.getTransform();
        final ratio = _ratioOf(stage);
        grid._pixels = (
          math.sqrt(m[0] * m[0] + m[1] * m[1]) * ratio,
          math.sqrt(m[4] * m[4] + m[5] * m[5]) * ratio,
        );
      }
      grid._make(stage);
    }
    return grid;
  }

  /// The root's pixels a canvas unit ([_LaysAir.pixelRatio]): the first
  /// veil's that says - a game gives all its veils the same.
  static double _ratioOf(Stage stage) {
    for (final air in <_LaysAir>[
      ...stage.members<AirVeil>(),
      ...stage.members<GroundAir>(),
    ]) {
      final ratio = air.pixelRatio?.call();
      if (ratio != null && ratio > 0) {
        return ratio;
      }
    }
    return 1;
  }

  int _drawing = -1;

  /// Pixels a world unit across and down where the world is drawn.
  (double, double)? _pixels;

  /// The picture of every veil's grid; `null` when none lays any air.
  Image? image;

  final Map<_LaysAir, ({Rect src, Rect area})> _regions = {};

  /// Where [air]'s grid is in [image], and the world rect it is laid over;
  /// `null`: it lays none this drawing.
  ({Rect src, Rect area})? regionOf(_LaysAir air) => _regions[air];

  /// The tallest a column of grids grows before the next starts beside it:
  /// what every GPU takes for an image's side.
  static const int _maxSide = 4096;

  void _make(Stage stage) {
    _drawing = stage.drawing;
    _regions.clear();
    image?.dispose();
    image = null;
    final shader = LightShader.air;
    final (px, py) = _pixels ?? (1.0, 1.0);
    if (shader == null || px <= 0 || py <= 0) {
      return;
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    var x = 0;
    var y = 0;
    var column = 0;
    var width = 0;
    var height = 0;
    for (final air in <_LaysAir>[
      ...stage.members<AirVeil>(),
      ...stage.members<GroundAir>(),
    ]) {
      final share = air._share;
      if (share >= 1) {
        continue;
      }
      final area = air._setUp(shader);
      if (area == null) {
        continue;
      }
      // Cells whose middles lie on the area's edges, the first and the last
      // of a row or a column on them: the stretch reads the air there as it
      // is, and nothing past it - a veil lays none under its line, and the
      // air just over the line would blend with that.
      final w = math.max(2, (area.width * px * share).ceil() + 1);
      final h = math.max(2, (area.height * py * share).ceil() + 1);
      if (y > 0 && y + h + 1 > _maxSide) {
        x += column;
        y = 0;
        column = 0;
      }
      final cellX = area.width / (w - 1);
      final cellY = area.height / (h - 1);
      canvas
        ..save()
        ..translate(x + 0.5, y + 0.5)
        ..scale(1 / cellX, 1 / cellY)
        ..translate(-area.left, -area.top)
        ..drawRect(
          Rect.fromLTRB(
            area.left - cellX / 2,
            area.top - cellY / 2,
            area.right + cellX / 2,
            area.bottom + cellY / 2,
          ),
          _paint..shader = shader,
        )
        ..restore();
      _regions[air] = (
        src: Rect.fromLTWH(
          x + 0.5,
          y + 0.5,
          w - 1.0,
          h - 1.0,
        ),
        area: area,
      );
      // A pixel apart, so no stretch reads a neighbour's.
      column = math.max(column, w + 1);
      y += h + 1;
      width = math.max(width, x + column);
      height = math.max(height, y);
    }
    final picture = recorder.endRecording();
    if (_regions.isNotEmpty) {
      image = picture.toImageSync(width, height);
    }
    picture.dispose();
  }
}

final Float32List _floats = Float32List((14 + _liftSamples ~/ 4 + 1) * 4);

/// Samples of the ground's height across the band, where they start in
/// floats, and the band's span after them.
const int _liftSamples = 32;
const int _liftAt = 14 * 4;
const int _liftSpanAt = _liftAt + _liftSamples;

/// Sets [shader] up for the air of [owner] as a veil at [depth] (up to the
/// veil at [nearer]) or, with [veils], as the ground's air, and says where
/// it lays it; `null`: nowhere this frame.
Rect? _setUpAir(
  OnStage owner,
  FragmentShader shader, {
  double depth = 0,
  double? nearer,
  List<double>? veils,
}) {
  final stage = owner.stage;
  final projection = stage?.projection;
  if (stage == null || projection == null) {
    return null;
  }
  final frame = stage.frame;
  final sky = frame.sky;
  if (!frame.weather.present || !sky.present) {
    return null;
  }
  final lighting = Lighting.of(owner);
  final metre = lighting?.metre ?? 1;
  final air = frame.weather.air;
  final f = _floats..fillRange(0, _floats.length, 0);
  f
    ..[0] = projection.band.top
    ..[1] = projection.band.height
    ..[2] = projection.nearDistance
    ..[3] = projection.farDistance
    ..[4] = projection.eyeHeight
    ..[5] = metre
    ..[6] = frame.view.center.dx
    ..[7] = veils == null ? 0 : 1
    ..[8] = depth
    ..[9] = nearer ?? -1e9
    ..[10] = air.base
    ..[11] = math.min(veils?.length ?? 0, 6).toDouble();
  final color = sky.horizon;
  f
    ..[12] = color.r * color.a
    ..[13] = color.g * color.a
    ..[14] = color.b * color.a
    ..[15] = color.a;
  for (final (i, bank) in air.banks.take(AirField.maxBanks).indexed) {
    final o = 16 + i * 8;
    f
      ..[o] = bank.extinction
      ..[o + 1] = bank.at == double.negativeInfinity ? -1e9 : bank.at
      ..[o + 2] = math.cos(bank.angle)
      ..[o + 3] = math.sin(bank.angle)
      ..[o + 4] = bank.widthM
      ..[o + 5] = bank.slant
      ..[o + 6] = bank.topM
      ..[o + 7] = bank.topWidthM;
  }
  if (veils != null) {
    for (final (i, v) in veils.take(6).indexed) {
      f[40 + i] = v;
    }
  }
  // The hills across the band; none on level ground.
  if (!projection.lift.isLevel) {
    final band = projection.band;
    projection.writeLift(f, _liftAt, band.left, band.right, _liftSamples);
    f
      ..[_liftSpanAt] = band.left
      ..[_liftSpanAt + 1] = band.right
      ..[_liftSpanAt + 2] = _liftSamples.toDouble();
  }
  for (var i = 0; i < f.length; i++) {
    shader.setFloat(i, f[i]);
  }
  // Only where it lays anything: a veil over what is drawn above where its
  // depth meets the ground, the ground's air over the ground band.
  final whole = frame.view.inflate(frame.view.width * 0.02);
  final line = projection.yAt(veils == null ? depth : 0);
  // Over hills the line rises and falls across the view: the veil reaches
  // down to its lowest, the ground's air up to its highest; the shader
  // keeps each to its side.
  final (low, high) = projection.lift.rangeIn(whole.left, whole.right);
  final area = veils == null
      ? Rect.fromLTRB(whole.left, whole.top, whole.right, line - low)
      : Rect.fromLTRB(whole.left, line - high, whole.right, whole.bottom);
  if (area.isEmpty) {
    return null;
  }
  // With no bank over the scene, as thick as its base over the whole way to
  // the street: nothing to lay if that is next to nothing.
  if (air.banks.isEmpty) {
    final m = math.max(metre, 1e-6);
    final farthest = veils == null
        ? projection.distanceAt(depth)
        : projection.farDistance;
    if (air.base * farthest / m < 2e-3) {
      return null;
    }
  }
  return area;
}
