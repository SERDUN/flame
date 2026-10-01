import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame_water/src/wave_field.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Built by the package's hook/build.dart.
const String _bundle =
    'packages/flame_water/build/shaderbundles/flame_water.shaderbundle';

/// The shaders and the full-view triangle every field draws with, made once.
class _Shared {
  _Shared(this.pipeline, this.quad);

  final gpu.RenderPipeline pipeline;
  final gpu.BufferView quad;
}

Future<_Shared?>? _shared;
bool? _available;

bool? get waveFieldAvailable => _available;

Future<_Shared?> _share() => _shared ??= _load();

Future<_Shared?> _load() async {
  try {
    final context = gpu.gpuContext;
    final library = await gpu.ShaderLibrary.fromAsset(_bundle);
    final vertex = library?['WaveVertex'];
    final fragment = library?['WaveFragment'];
    if (vertex == null || fragment == null) {
      throw StateError('$_bundle has no wave shaders');
    }
    final triangle = Float32List.fromList([-1, -1, 3, -1, -1, 3]);
    final buffer = context.createDeviceBufferWithCopy(
      ByteData.sublistView(triangle),
    );
    _available = true;
    return _Shared(
      context.createRenderPipeline(vertex, fragment),
      gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: triangle.lengthInBytes,
      ),
    );
  } on Object catch (error) {
    // Flutter GPU off, no Impeller, or the bundle missing: the water keeps
    // to its rings.
    debugPrint('flame_water: no GPU waves ($error)');
    _available = false;
    return null;
  }
}

Future<WaveField?> createWaveField(int columns, int rows) async {
  final shared = await _share();
  if (shared == null) {
    return null;
  }
  return _GpuWaveField(shared, columns, rows);
}

class _GpuWaveField implements WaveField {
  _GpuWaveField(this._shared, this.columns, this.rows)
    : _textures = [
        for (var i = 0; i < 3; i++)
          gpu.gpuContext.createTexture(
            gpu.StorageMode.devicePrivate,
            columns,
            rows,
            format: gpu.PixelFormat.r32Float,
          ),
      ] {
    // A still surface to start from: the textures a step reads, cleared. A
    // command buffer holds one pass at a time.
    for (final texture in _textures) {
      gpu.gpuContext.createCommandBuffer()
        ..createRenderPass(
          gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: texture)),
        )
        ..submit();
    }
  }

  static const int maxDrops = 16;

  final _Shared _shared;

  /// Where a step's parameters go: a buffer that cycles through a few
  /// frames' worth, so it must be told when a frame starts ([step] is once
  /// a frame).
  final gpu.HostBuffer _host = gpu.gpuContext.createHostBuffer();
  final List<gpu.Texture> _textures;
  final List<double> _drops = [];
  final Float32List _params = Float32List(8 + maxDrops * 4);
  int _turn = 0;
  ui.Image? _heights;

  @override
  final int columns;
  @override
  final int rows;

  @override
  void drop(
    double u,
    double v, {
    required double radius,
    required double depth,
  }) {
    if (u < 0 || u > 1 || v < 0 || v > 1) {
      return;
    }
    _drops.addAll([u, v, radius, depth]);
  }

  @override
  void step(int steps, {required double damping, required double courant}) {
    if (steps <= 0 || _disposed) {
      return;
    }
    _host.reset();
    final pipeline = _shared.pipeline;
    final shader = pipeline.fragmentShader;
    for (var s = 0; s < steps; s++) {
      // One pass a command buffer: a buffer holds one encoder at a time.
      final commands = gpu.gpuContext.createCommandBuffer();
      final previous = _textures[_turn % 3];
      final current = _textures[(_turn + 1) % 3];
      final next = _textures[(_turn + 2) % 3];
      // Drops land on the first step they can, sixteen a step.
      final count = (_drops.length ~/ 4).clamp(0, maxDrops);
      _params
        ..[0] = 1 / columns
        ..[1] = 1 / rows
        ..[2] = damping
        ..[3] = count.toDouble()
        ..[4] = courant * courant;
      for (var i = 0; i < count * 4; i++) {
        _params[8 + i] = _drops[i];
      }
      _drops.removeRange(0, count * 4);
      final pass = commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: next)),
      );
      pass
        ..bindPipeline(pipeline)
        ..bindVertexBuffer(_shared.quad)
        ..bindTexture(shader.getUniformSlot('prev_tex'), previous)
        ..bindTexture(shader.getUniformSlot('curr_tex'), current)
        ..bindUniform(
          shader.getUniformSlot('Params'),
          _host.emplace(ByteData.sublistView(_params)),
        )
        ..draw(3);
      commands.submit();
      _turn++;
    }
    _heights?.dispose();
    _heights = _textures[(_turn + 1) % 3].asImage();
  }

  @override
  ui.Image? get heights => _heights;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _drops.clear();
    _heights?.dispose();
    _heights = null;
  }
}
