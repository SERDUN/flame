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

  /// Where a frame's parameters go: a buffer that cycles through a few
  /// frames' worth, told when a frame starts.
  final gpu.HostBuffer _host = gpu.gpuContext.createHostBuffer();
  final Float32List _params = Float32List(LightBuffer.floats);

  /// Three targets in turn: a frame's image is read while it is drawn,
  /// after this one has moved on to the next.
  final List<gpu.Texture> _targets = [];
  int _width = 0;
  int _height = 0;
  int _turn = 0;
  ui.Image? _image;
  bool _disposed = false;

  @override
  ui.Image? render(StageFrame frame, ui.Rect area, int width, int height) {
    if (_disposed || width <= 0 || height <= 0) {
      return null;
    }
    if (width != _width || height != _height) {
      _targets
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
      _width = width;
      _height = height;
    }
    LightBuffer.write(_params, frame, area);
    _host.reset();
    final target = _targets[_turn % 3];
    _turn++;
    final pipeline = _shared.pipeline;
    final commands = gpu.gpuContext.createCommandBuffer();
    commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      )
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(_shared.quad)
      ..bindUniform(
        pipeline.fragmentShader.getUniformSlot('Params'),
        _host.emplace(ByteData.sublistView(_params)),
      )
      ..draw(3);
    commands.submit();
    _image?.dispose();
    return _image = target.asImage();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    _targets.clear();
  }
}
