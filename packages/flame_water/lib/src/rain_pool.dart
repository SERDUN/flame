import 'dart:typed_data';

/// Columns of flat numbers, one row a thing, that grow as needed and drop a
/// row by moving the last one into its place: the rain's drops and
/// droplets, with no object and no allocation for each.
abstract class _Pool {
  _Pool(this._columns) : _data = Float64List(_columns * 256);

  final int _columns;
  Float64List _data;

  /// Rows in use.
  int length = 0;

  /// A new row at the end, its values left as they were; its index.
  int grow() {
    if ((length + 1) * _columns > _data.length) {
      _data = Float64List(_data.length * 2)..setAll(0, _data);
      _grew(_data.length ~/ _columns);
    }
    return length++;
  }

  /// Drops row [i], moving the last row into its place.
  void removeAt(int i) {
    final last = length - 1;
    if (i != last) {
      _data.setRange(
        i * _columns,
        (i + 1) * _columns,
        _data,
        last * _columns,
      );
      _moved(last, i);
    }
    length = last;
  }

  /// Drops every row.
  void clear() => length = 0;

  double _get(int i, int c) => _data[i * _columns + c];
  void _set(int i, int c, double v) => _data[i * _columns + c] = v;

  /// The rows' room grew to [rows]; columns kept elsewhere follow.
  void _grew(int rows) {}

  /// Row [from] moved to [to]; columns kept elsewhere follow.
  void _moved(int from, int to) {}
}

/// The drops in the air.
class DropPool extends _Pool {
  DropPool() : super(15);

  // Columns.
  static const int _source = 0;
  static const int _x = 1;
  static const int _y = 2;
  static const int _vx = 3;
  static const int _vy = 4;
  static const int _land = 5;
  static const int _depth = 6;
  static const int _perspective = 7;
  static const int _response = 8;
  static const int _fall = 9;
  static const int _diameter = 10;
  static const int _strength = 11;
  static const int _width = 12;
  static const int _bounced = 13;
  static const int _sharp = 14;

  /// How it looks this frame, over the lighting and under it, ARGB.
  Int32List color = Int32List(256);
  Int32List colorUnder = Int32List(256);

  @override
  void _grew(int rows) {
    color = Int32List(rows)..setAll(0, color);
    colorUnder = Int32List(rows)..setAll(0, colorUnder);
  }

  @override
  void _moved(int from, int to) {
    color[to] = color[from];
    colorUnder[to] = colorUnder[from];
  }

  /// World x where it left the cloud.
  double source(int i) => _get(i, _source);
  double x(int i) => _get(i, _x);
  double y(int i) => _get(i, _y);
  double vx(int i) => _get(i, _vx);
  double vy(int i) => _get(i, _vy);

  /// World y where it meets the ground, at its depth.
  double land(int i) => _get(i, _land);

  /// Below 0 behind the street line; 0 on the line things stand on .. 1
  /// near.
  double depth(int i) => _get(i, _depth);

  /// How much faster than on the street line it crosses the view.
  double perspective(int i) => _get(i, _perspective);

  /// How quickly it takes up the wind, s.
  double response(int i) => _get(i, _response);

  /// Its fall speed on the screen, world units a second.
  double fall(int i) => _get(i, _fall);

  /// mm.
  double diameter(int i) => _get(i, _diameter);

  /// 0..1: a heavy drop against a fine one.
  double strength(int i) => _get(i, _strength);

  /// Its streak's width this frame, blurred as far as it is out of focus.
  double width(int i) => _get(i, _width);

  /// Its streak's width in focus.
  double sharpWidth(int i) => _get(i, _sharp);

  /// Whether it has bounced off a deflector already.
  bool bounced(int i) => _get(i, _bounced) > 0;

  void setSource(int i, double v) => _set(i, _source, v);
  void setX(int i, double v) => _set(i, _x, v);
  void setY(int i, double v) => _set(i, _y, v);
  void setVx(int i, double v) => _set(i, _vx, v);
  void setVy(int i, double v) => _set(i, _vy, v);
  void setLand(int i, double v) => _set(i, _land, v);
  void setDepth(int i, double v) => _set(i, _depth, v);
  void setPerspective(int i, double v) => _set(i, _perspective, v);
  void setResponse(int i, double v) => _set(i, _response, v);
  void setFall(int i, double v) => _set(i, _fall, v);
  void setDiameter(int i, double v) => _set(i, _diameter, v);
  void setStrength(int i, double v) => _set(i, _strength, v);
  void setWidth(int i, double v) => _set(i, _width, v);
  void setSharpWidth(int i, double v) => _set(i, _sharp, v);
  void setBounced(int i) => _set(i, _bounced, 1);

  /// A new drop, not bounced; the rest to be set.
  int add() {
    final i = grow();
    _set(i, _bounced, 0);
    return i;
  }
}

/// The droplets of drops that burst where they landed.
class DropletPool extends _Pool {
  DropletPool() : super(10);

  static const int _x = 0;
  static const int _y = 1;
  static const int _vx = 2;
  static const int _vy = 3;
  static const int _floor = 4;
  static const int _life = 5;
  static const int _width = 6;
  static const int _depth = 7;
  static const int _age = 8;
  static const int _drawn = 9;

  /// How it looks this frame, over the lighting and under it, ARGB.
  Int32List color = Int32List(256);
  Int32List colorUnder = Int32List(256);

  @override
  void _grew(int rows) {
    color = Int32List(rows)..setAll(0, color);
    colorUnder = Int32List(rows)..setAll(0, colorUnder);
  }

  @override
  void _moved(int from, int to) {
    color[to] = color[from];
    colorUnder[to] = colorUnder[from];
  }

  double x(int i) => _get(i, _x);
  double y(int i) => _get(i, _y);
  double vx(int i) => _get(i, _vx);
  double vy(int i) => _get(i, _vy);

  /// World y it falls back to and is gone.
  double floor(int i) => _get(i, _floor);
  double life(int i) => _get(i, _life);
  double width(int i) => _get(i, _width);
  double depth(int i) => _get(i, _depth);
  double age(int i) => _get(i, _age);

  /// Its width as drawn this frame, blurred as far as it is out of focus.
  double drawnWidth(int i) => _get(i, _drawn);

  void setDrawnWidth(int i, double v) => _set(i, _drawn, v);

  /// A droplet thrown from ([x], [y]) at ([vx], [vy]).
  void add({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double floor,
    required double life,
    required double width,
    required double depth,
  }) {
    final i = grow();
    _set(i, _x, x);
    _set(i, _y, y);
    _set(i, _vx, vx);
    _set(i, _vy, vy);
    _set(i, _floor, floor);
    _set(i, _life, life);
    _set(i, _width, width);
    _set(i, _depth, depth);
    _set(i, _age, 0);
    _set(i, _drawn, width);
  }

  /// Moves every droplet on by [dt] under [gravity] (world units / s²), and
  /// drops those whose life is over or that fell back down.
  void step(double dt, double gravity) {
    var i = 0;
    while (i < length) {
      final age = _get(i, _age) + dt;
      final vy = _get(i, _vy) + gravity * dt;
      final x = _get(i, _x) + _get(i, _vx) * dt;
      final y = _get(i, _y) + vy * dt;
      if (age >= _get(i, _life) || y > _get(i, _floor)) {
        removeAt(i);
        continue;
      }
      _set(i, _age, age);
      _set(i, _vy, vy);
      _set(i, _x, x);
      _set(i, _y, y);
      i++;
    }
  }
}
