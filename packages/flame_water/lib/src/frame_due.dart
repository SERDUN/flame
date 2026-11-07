/// What something stepped in fixed steps but seen once a frame owes since it
/// was last brought up to date: the time its steps added and nothing moved
/// over yet, and whether what is drawn of it is stale. A slow frame steps
/// several times and is drawn once; the rain moves and works out its look
/// once over all of them (`Rain.movesWhereDrawn`).
class FrameDue {
  double _time = 0;
  bool _look = false;

  /// Time the steps added and nothing moved over yet, s.
  double get time => _time;

  /// A step of [dt] went by.
  void stepped(double dt) => _time += dt;

  /// The time owed, which is now taken: the caller moves over it.
  double takeTime() {
    final time = _time;
    _time = 0;
    return time;
  }

  /// What is drawn of it is stale: it moved.
  void moved() => _look = true;

  /// Whether what is drawn of it is stale, which is now taken: the caller
  /// works it out again.
  bool takeLook() {
    final look = _look;
    _look = false;
    return look;
  }
}
