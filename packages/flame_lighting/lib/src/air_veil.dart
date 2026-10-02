import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_lighting/src/light_shader.dart';
import 'package:flame_lighting/src/lighting.dart';
import 'package:flame_stage/flame_stage.dart';

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
class AirVeil extends Component with OnStage, AtDepth {
  AirVeil({required this.depth, this.nearer});

  /// The depth it stands at.
  final double Function() depth;

  /// The depth of the next veil toward the eye; `null`: the eye.
  final double? Function()? nearer;

  @override
  double depthIn(StreetProjection? projection) => depth();

  @override
  DepthOrder get depthOrder => DepthOrder.air;

  @override
  void render(Canvas canvas) =>
      _drawAir(this, canvas, depth: depth(), nearer: nearer?.call());
}

/// The air over the ground band: each row of it the air between the ground
/// there and the next veil nearer than it ([veils]), or the eye - water and
/// the road farther off paler than near. It lies over the ground and what
/// lies flat on it, under what stands on it ([DepthOrder.air] at the street
/// line, after the flat things there), and water does not mirror it.
class GroundAir extends Component with OnStage, AtDepth, LiesFlat {
  GroundAir({required this.veils});

  /// The depths of the veils in front of the street line, where each takes
  /// over the air nearer than it.
  final List<double> Function() veils;

  @override
  double depthIn(StreetProjection? projection) => 0;

  @override
  DepthOrder get depthOrder => DepthOrder.air;

  @override
  void render(Canvas canvas) => _drawAir(this, canvas, veils: veils());
}

final Float32List _floats = Float32List(14 * 4);
final Paint _paint = Paint();

/// Lays the air over [canvas] as a veil at [depth] (up to the veil at
/// [nearer]) or, with [veils], as the ground's air.
void _drawAir(
  OnStage owner,
  Canvas canvas, {
  double depth = 0,
  double? nearer,
  List<double>? veils,
}) {
  final stage = owner.stage;
  final shader = LightShader.air;
  final projection = stage?.projection;
  if (stage == null || shader == null || projection == null) {
    return;
  }
  final frame = stage.frame;
  final sky = frame.sky;
  if (!frame.weather.present || !sky.present) {
    return;
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
  for (var i = 0; i < f.length; i++) {
    shader.setFloat(i, f[i]);
  }
  final view = frame.view.inflate(frame.view.width * 0.02);
  void draw() => canvas.drawRect(view, _paint..shader = shader);
  if (lighting == null) {
    draw();
  } else {
    lighting.unlit(canvas, draw);
  }
}
