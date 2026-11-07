import 'package:flame_water/src/wave_field.dart';

/// No flutter_gpu here (the web): no field, the water keeps to its rings.
Future<WaveField?> createWaveField(int columns, int rows) async => null;

bool? get waveFieldAvailable => false;
