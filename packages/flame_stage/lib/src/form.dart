import 'package:flame/components.dart';

/// Something with no height over the ground it lies on: the ground itself,
/// a film of water, a puddle, a fallen leaf, a mark on the road.
///
/// What a mirror lying on the ground shows of it is a line - its image is
/// as tall as it is - so water does not mirror it. Everything else on the
/// stage stands, and is mirrored.
mixin LiesFlat on Component {}

/// Drawn in the world but no thing in it: a debug overlay, a guide, a
/// marker for the player.
///
/// No light reaches it from the scene and no mirror shows it: it is not
/// there to be seen in the world, only on the screen.
mixin OffStage on Component {}
