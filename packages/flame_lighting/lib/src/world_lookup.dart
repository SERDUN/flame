import 'package:flame/components.dart';

/// Finds the one [T] in a component's world and remembers it, so asking
/// every frame (every drop, every light) costs a walk up to the world, not
/// a walk over all of it. The remembered one is asked for again once it is
/// no longer mounted.
final class WorldLookup<T extends Component> {
  final Expando<T> _found = Expando();

  /// The [T] in the world [component] is in, if there is one.
  T? of(Component component) {
    final world = worldOf(component);
    final hit = _found[world];
    if (hit != null && hit.isMounted && !hit.isRemoving) {
      return hit;
    }
    final fresh = world.descendants().whereType<T>().firstOrNull;
    if (fresh != null) {
      _found[world] = fresh;
    }
    return fresh;
  }

  /// The world [component] is in: its nearest [World], or its root.
  static Component worldOf(Component component) {
    var top = component;
    for (final a in component.ancestors()) {
      top = a;
      if (a is World) {
        break;
      }
    }
    return top;
  }
}
