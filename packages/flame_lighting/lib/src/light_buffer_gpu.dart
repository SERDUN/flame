import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame_lighting/src/light_buffer.dart';
import 'package:flame_stage/flame_stage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Built by the package's hook/build.dart.
const String _bundle =
    'packages/flame_lighting/build/shaderbundles/flame_lighting.shaderbundle';

/// The shaders and the full-view triangle every buffer draws with, made
/// once.
class _Shared {
  _Shared(this.pipeline, this.quad);

  final gpu.RenderPipeline pipeline;
  final gpu.BufferView quad;
}

Future<_Shared?>? _shared;
bool? _available;

bool? get lightBufferAvailable => _available;

Future<_Shared?> _share() => _shared ??= _load();

Future<_Shared?> _load() async {
  try {
    final context = gpu.gpuContext;
    if (!context.supportsTextureFormat(
      gpu.PixelFormat.r16g16b16a16Float,
      renderTarget: true,
    )) {
      throw StateError('no half-float render targets');
    }
    final library = await gpu.ShaderLibrary.fromAsset(_bundle);
    final vertex = library?['LightVertex'];
    final fragment = library?['LightFragment'];
    if (vertex == null || fragment == null) {
      throw StateError('$_bundle has no light shaders');
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
    // Flutter GPU off, no Impeller, or the bundle missing: the lighting
    // draws on the canvas.
    debugPrint('flame_lighting: no light buffer ($error)');
    _available = false;
    return null;
  }
}

Future<LightBuffer?> createLightBuffer() async {
  final shared = await _share();
  return shared == null ? null : _GpuLightBuffer(shared);
}

class _GpuLightBuffer implements LightBuffer {
  _GpuLightBuffer(this._shared);

  final _Shared _shared;
  final Float32List _params = Float32List(LightBuffer.floats);

  /// Each slot its own targets, parameters and image: a frame renders the
  /// street's plane and each cut's, and none may overwrite another's.
  final Map<int, _Slot> _slots = {};
  bool _disposed = false;

  @override
  ui.Image? render(
    StageFrame frame,
    ui.Rect area,
    int width,
    int height, {
    double wallAhead = 0,
    double air = 0,
    double visibility = 1e9,
    int slot = 0,
  }) {
    if (_disposed || width <= 0 || height <= 0) {
      return null;
    }
    final at = _slots[slot] ??= _Slot();
    if (width != at.width || height != at.height) {
      at.targets
        ..clear()
        ..addAll([
          for (var i = 0; i < 3; i++)
            gpu.gpuContext.createTexture(
              gpu.StorageMode.devicePrivate,
              width,
              height,
              format: gpu.PixelFormat.r16g16b16a16Float,
            ),
        ]);
      at
        ..width = width
        ..height = height;
    }
    LightBuffer.write(
      _params,
      frame,
      area,
      wallAhead: wallAhead,
      air: air,
      visibility: visibility,
    );
    at.host.reset();
    final target = at.targets[at.turn % 3];
    at.turn++;
    final pipeline = _shared.pipeline;
    final commands = gpu.gpuContext.createCommandBuffer();
    commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      )
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(_shared.quad)
      ..bindUniform(
        pipeline.fragmentShader.getUniformSlot('Params'),
        at.host.emplace(ByteData.sublistView(_params)),
      )
      ..draw(3);
    commands.submit();
    at.image?.dispose();
    return at.image = target.asImage();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final at in _slots.values) {
      at.image?.dispose();
      at.image = null;
      at.targets.clear();
    }
    _slots.clear();
  }
}

/// One plane's rendering: three targets in turn (a frame's image is read
/// while it is drawn, after this one has moved on to the next), and the
/// parameters' buffer, which cycles through a few frames' worth and is told
/// when a frame starts.
class _Slot {
  final gpu.HostBuffer host = gpu.gpuContext.createHostBuffer();
  final List<gpu.Texture> targets = [];
  int width = 0;
  int height = 0;
  int turn = 0;
  ui.Image? image;
}
