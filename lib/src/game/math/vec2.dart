import 'dart:math' as math;
import 'dart:ui';

class Vec2 {
  Vec2(this.x, this.y);

  double x;
  double y;

  factory Vec2.zero() => Vec2(0, 0);

  Vec2 copy() => Vec2(x, y);

  Offset toOffset() => Offset(x, y);

  double get length => math.sqrt(x * x + y * y);

  double get lengthSquared => x * x + y * y;

  bool get isZero => lengthSquared < 0.000001;

  Vec2 normalized([Vec2? fallback]) {
    final currentLength = length;
    if (currentLength <= 0.000001) {
      return fallback?.copy() ?? Vec2(1, 0);
    }
    return Vec2(x / currentLength, y / currentLength);
  }

  double distanceTo(Vec2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double dot(Vec2 other) => x * other.x + y * other.y;

  void setFrom(Vec2 other) {
    x = other.x;
    y = other.y;
  }

  void clampTo(double minX, double minY, double maxX, double maxY) {
    x = x.clamp(minX, maxX).toDouble();
    y = y.clamp(minY, maxY).toDouble();
  }

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);

  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);

  Vec2 operator -() => Vec2(-x, -y);

  Vec2 operator *(double scale) => Vec2(x * scale, y * scale);

  Vec2 operator /(double scale) => Vec2(x / scale, y / scale);
}

double clampDoubleValue(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}
