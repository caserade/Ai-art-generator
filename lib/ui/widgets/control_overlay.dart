import 'package:flutter/material.dart';

import '../../controllers/dual_control_engine.dart';
import '../../models/game_models.dart';

/// Dual joysticks, D-Pad, and A/B/X/Y face buttons with haptics.
class ControlOverlay extends StatelessWidget {
  const ControlOverlay({super.key, required this.engine});

  final DualControlEngine engine;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 12,
              bottom: 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  VirtualJoystick(
                    onChanged: engine.setLeftStick,
                    label: 'Move',
                  ),
                  const SizedBox(width: 16),
                  DPadWidget(engine: engine),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 24,
              child: ActionButtons(engine: engine),
            ),
          ],
        ),
      ),
    );
  }
}

class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onChanged,
    this.label,
    this.radius = 56,
  });

  final void Function(double x, double y) onChanged;
  final String? label;
  final double radius;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knob = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Text(
            widget.label!,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        SizedBox(
          width: diameter,
          height: diameter,
          child: GestureDetector(
            onPanStart: (d) => _update(d.localPosition, diameter),
            onPanUpdate: (d) => _update(d.localPosition, diameter),
            onPanEnd: (_) {
              setState(() => _knob = Offset.zero);
              widget.onChanged(0, 0);
            },
            child: CustomPaint(
              painter: _JoystickPainter(knob: _knob, radius: widget.radius),
            ),
          ),
        ),
      ],
    );
  }

  void _update(Offset local, double diameter) {
    final center = Offset(diameter / 2, diameter / 2);
    var delta = local - center;
    if (delta.distance > widget.radius) {
      delta = Offset.fromDirection(delta.direction, widget.radius);
    }
    setState(() => _knob = delta);
    widget.onChanged(delta.dx / widget.radius, delta.dy / widget.radius);
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({required this.knob, required this.radius});

  final Offset knob;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = Paint()..color = const Color(0x66212B36);
    final ring = Paint()
      ..color = const Color(0x99FF8A50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final knobPaint = Paint()..color = const Color(0xE0FF8A50);
    canvas.drawCircle(center, radius, base);
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(center + knob, radius * 0.38, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      oldDelegate.knob != knob;
}

class DPadWidget extends StatelessWidget {
  const DPadWidget({super.key, required this.engine});

  final DualControlEngine engine;

  @override
  Widget build(BuildContext context) {
    Widget cell(GamepadButton button, IconData icon) {
      return GestureDetector(
        onTapDown: (_) => engine.pressButton(button, pressed: true),
        onTapUp: (_) => engine.pressButton(button, pressed: false),
        onTapCancel: () => engine.pressButton(button, pressed: false),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0x99212B36),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x66FF8A50)),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(GamepadButton.up, Icons.keyboard_arrow_up),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            cell(GamepadButton.left, Icons.keyboard_arrow_left),
            const SizedBox(width: 40, height: 40),
            cell(GamepadButton.right, Icons.keyboard_arrow_right),
          ],
        ),
        cell(GamepadButton.down, Icons.keyboard_arrow_down),
      ],
    );
  }
}

class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key, required this.engine});

  final DualControlEngine engine;

  @override
  Widget build(BuildContext context) {
    Widget btn(GamepadButton button, String label, Color color) {
      return GestureDetector(
        onTapDown: (_) => engine.pressButton(button, pressed: true),
        onTapUp: (_) => engine.pressButton(button, pressed: false),
        onTapCancel: () => engine.pressButton(button, pressed: false),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 44,
            child: btn(GamepadButton.y, 'Y', const Color(0xFFF9A825)),
          ),
          Positioned(
            left: 0,
            top: 44,
            child: btn(GamepadButton.x, 'X', const Color(0xFF1E88E5)),
          ),
          Positioned(
            right: 0,
            top: 44,
            child: btn(GamepadButton.b, 'B', const Color(0xFFE53935)),
          ),
          Positioned(
            bottom: 0,
            left: 44,
            child: btn(GamepadButton.a, 'A', const Color(0xFF43A047)),
          ),
        ],
      ),
    );
  }
}
