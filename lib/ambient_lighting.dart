import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Device-local appearance preference, shared with routes pushed above the home screen.
class AmbientLightingScope extends InheritedWidget {
  const AmbientLightingScope({
    required this.enabled,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  static AmbientLightingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientLightingScope>();

  @override
  bool updateShouldNotify(AmbientLightingScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// A single isolated gradient painting, with no frame ticker, blur or offscreen blend pass.
/// The local clock provides a decorative day/night cycle; no location permission is needed.
class AmbientLighting extends StatefulWidget {
  const AmbientLighting({super.key, this.now});
  final DateTime? now;

  @override
  State<AmbientLighting> createState() => _AmbientLightingState();
}

class _AmbientLightingState extends State<AmbientLighting>
    with WidgetsBindingObserver {
  Timer? timer;
  DateTime clock = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncClock();
  }

  void syncClock() {
    timer?.cancel();
    if (widget.now != null) return;
    clock = DateTime.now();
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => clock = DateTime.now());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(syncClock);
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: AmbientLightPainter(
            now: widget.now ?? clock,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class AmbientLightPainter extends CustomPainter {
  AmbientLightPainter({required DateTime now, required this.dark})
    : minute = now.hour * 60 + now.minute;

  final int minute;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // A local 6am–6pm daylight sweep, followed by a cool overnight sweep.
    final day = minute >= 360 && minute < 1080;
    final progress = ((minute - (day ? 360 : 1080)) % 720) / 720;
    final color = day ? const Color(0xffffd598) : const Color(0xffadcfff);
    final strength =
        (dark ? 0.13 : 0.09) *
        (math.min(1.0, math.min(progress, 1 - progress) / 0.09));
    final source = Offset(
      size.width * (-0.18 + progress * 1.36),
      -size.height * (0.1 + math.sin(progress * math.pi) * 0.3),
    );
    final angle = math.atan2(
      size.width / 2 - source.dx,
      size.height / 2 - source.dy,
    );
    canvas.save();
    canvas.translate(source.dx, source.dy);
    canvas.rotate(-angle);
    final extent = size.longestSide * 2;
    final bounds = Rect.fromLTRB(-extent, 0, extent, extent);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: strength * 0.2),
            color.withValues(alpha: strength * 0.65),
            color.withValues(alpha: strength * 0.3),
            color.withValues(alpha: strength),
            color.withValues(alpha: strength * 0.25),
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.17, 0.20, 0.23, 0.245, 0.26, 0.29, 0.33, 1],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AmbientLightPainter oldDelegate) =>
      minute != oldDelegate.minute || dark != oldDelegate.dark;
}
