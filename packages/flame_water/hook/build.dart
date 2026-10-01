import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

/// Builds the flutter_gpu shaders of the water (the wave simulation) into
/// build/shaderbundles/flame_water.shaderbundle, which the package lists as an
/// asset. A bundle is tied to the engine that compiles it, so it is built with
/// the app rather than kept in git.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'flame_water.shaderbundle.json',
    );
  });
}
