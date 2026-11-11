import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

Json object(Object? value) => value is Json ? value : <String, dynamic>{};
List<Json> objects(Object? value) =>
    value is List ? value.whereType<Json>().toList() : [];
String label(Object? value, [String fallback = '—']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
String endpoint(Object? id) => Uri.encodeComponent(label(id, ''));
String isoDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String isoMonth(DateTime date) => DateFormat('yyyy-MM').format(date);
String humanDate(Object? value) {
  final date = DateTime.tryParse(label(value, ''));
  return date == null ? '—' : DateFormat.MMMd().format(date.toLocal());
}

BigInt? minor(Object? value) =>
    BigInt.tryParse(label(object(value)['amount'], ''));

String money(Object? value) {
  final amount = minor(value);
  if (amount == null) return '—';
  final digits = amount.abs().toString().padLeft(3, '0');
  final whole = digits.substring(0, digits.length - 2);
  final formatted = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount.isNegative ? '-' : ''}\$$formatted.${digits.substring(digits.length - 2)}';
}

String words(Object? value) => label(value).replaceAll(RegExp('[-_]'), ' ');

class Metric extends StatelessWidget {
  const Metric(this.title, this.value, {super.key});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 5),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class FinanceList extends StatelessWidget {
  const FinanceList({required this.children, this.onRefresh, super.key});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: children,
    );
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 670),
          child: onRefresh == null
              ? list
              : RefreshIndicator(onRefresh: onRefresh!, child: list),
        ),
      ),
    );
  }
}

class LoadScreen<T> extends StatefulWidget {
  const LoadScreen({required this.load, required this.content, super.key});
  final Future<T> Function() load;
  final List<Widget> Function(T data, Future<void> Function() reload) content;

  @override
  State<LoadScreen<T>> createState() => _LoadScreenState<T>();
}

class _LoadScreenState<T> extends State<LoadScreen<T>> {
  late Future<T> future = widget.load();

  Future<void> reload() async {
    final request = widget.load();
    setState(() {
      future = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder presents the request error.
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return FinanceList(
          onRefresh: reload,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMessage(snapshot.error!)),
                  TextButton(onPressed: reload, child: const Text('Try again')),
                ],
              ),
            ),
          ],
        );
      }
      if (snapshot.hasData) {
        return Stack(
          children: [
            FinanceList(
              onRefresh: reload,
              children: widget.content(snapshot.data as T, reload),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    },
  );
}

class BalanceChart extends StatelessWidget {
  const BalanceChart(this.points, {super.key});
  final List<double> points;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Net worth history, ${points.length} recorded periods',
    child: SizedBox(
      height: 82,
      width: double.infinity,
      child: CustomPaint(
        painter: _BalancePainter(points, Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class _BalancePainter extends CustomPainter {
  const _BalancePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final low = points.reduce(math.min);
    final high = points.reduce(math.max);
    final spread = high - low;
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final x = 3 + i * (size.width - 6) / (points.length - 1);
      final y = spread == 0
          ? size.height / 2
          : size.height - 7 - (points[i] - low) / spread * (size.height - 14);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final shade = Path.from(line)
      ..lineTo(size.width - 3, size.height)
      ..lineTo(3, size.height)
      ..close();
    canvas.drawPath(
      shade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .24), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BalancePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
