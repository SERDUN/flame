import 'package:flame_stage/src/stage.dart';
import 'package:flame_stage/src/street_projection.dart';

/// What a thing at a depth is, as far as drawing goes: of things at the same
/// depth, which comes first.
///
/// The ground is under everything; what lies on it flat (water, a film) is
/// under what stands on it; rain at a depth is behind what stands there (a
/// rain slice holds the drops up to, not including, its depth); what stands
/// is the things themselves; the air at a depth (a veil, a curtain of rain)
/// lies over what stands there; and a cut of the lighting at a depth lights
/// everything at it and behind it, so it comes last.
enum DepthOrder { ground, flat, rain, standing, air, light }

/// A thing on the stage at a depth of the street: the stage draws them far to
/// near ([Stage]), so whatever stands nearer the eye is drawn over what stands
/// farther - whoever added what first. Of two at the same depth the
/// [depthOrder] says which first, then the order they joined the stage.
///
/// Its depth is the projection's (`StreetProjection`): below 0 behind the
/// street line, 0 on it, up to 1 at the nearest ground in view - the nearest
/// it reaches, for something spread over depths (a slice of rain up to its
/// edge, water from its far edge on).
mixin AtDepth on OnStage {
  /// Its depth under [projection] (`null` before there is a ground).
  double depthIn(StreetProjection? projection);

  /// What it is at its depth: which of things at the same depth comes first.
  DepthOrder get depthOrder => DepthOrder.standing;

  /// Whether the stage places it by its depth; `false` for one placed by
  /// hand (a priority given outright: rain drawn over all the lighting).
  bool get placedByDepth => true;
}
