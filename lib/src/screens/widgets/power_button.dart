import 'package:flutter/material.dart';

class PowerButton extends StatefulWidget {
  const PowerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onReleased,
  });

  final IconData icon;
  final String label;
  final Color color;
  final ValueChanged<double> onReleased;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> {
  DateTime? _startedAt;
  bool _pressed = false;

  void _start() {
    setState(() {
      _pressed = true;
      _startedAt = DateTime.now();
    });
  }

  void _end() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    final ms = DateTime.now().difference(startedAt).inMilliseconds;
    final power = (0.55 + ms / 900).clamp(0.55, 1.65).toDouble();
    setState(() {
      _pressed = false;
      _startedAt = null;
    });
    widget.onReleased(power);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        width: 104,
        height: 58,
        decoration: BoxDecoration(
          color: _pressed ? widget.color : widget.color.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, size: 23, color: Colors.white),
            const SizedBox(height: 3),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
