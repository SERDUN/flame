import 'package:flame_water/src/frame_due.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('what a frame owes is the time of its steps, taken once', () {
    final due = FrameDue()
      ..stepped(1 / 60)
      ..stepped(1 / 60)
      ..stepped(1 / 60);
    expect(due.time, closeTo(0.05, 1e-12));
    expect(due.takeTime(), closeTo(0.05, 1e-12));
    expect(due.time, 0);
    expect(due.takeTime(), 0);
  });

  test('a stale look is taken once: worked out again, then not', () {
    final due = FrameDue();
    expect(due.takeLook(), isFalse);
    due
      ..moved()
      ..moved();
    expect(due.takeLook(), isTrue);
    expect(due.takeLook(), isFalse);
  });
}
