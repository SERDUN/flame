import 'package:flame_lighting/src/light_buffer.dart';

/// No flutter_gpu here (the web): no buffer, the lighting keeps to the
/// canvas.
Future<LightBuffer?> createLightBuffer() async => null;

bool? get lightBufferAvailable => false;
