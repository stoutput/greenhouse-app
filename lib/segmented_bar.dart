import 'package:flutter/material.dart';

class BalanceSegment {
  const BalanceSegment({
    required this.id,
    required this.label,
    required this.value,
    required this.amount,
  });
  final String id;
  final String label;
  final BigInt? value;
  final String amount;
}

class SegmentedBar extends StatelessWidget {
  const SegmentedBar({
    required this.segments,
    required this.onSelect,
    this.selectedId,
    super.key,
  });
  final List<BalanceSegment> segments;
  final ValueChanged<String> onSelect;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seed = HSLColor.fromColor(theme.colorScheme.primary);
    final values = [
      for (final segment in segments)
        (segment.value ?? BigInt.zero).abs().toDouble(),
    ];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    Color color(int i) =>
        seed.withHue((seed.hue + i * 137.508) % 360).toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (segments.isNotEmpty)
          ExcludeSemantics(
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  for (var i = 0; i < segments.length; i++)
                    if (total == 0 || values[i] > 0)
                      Expanded(
                        flex: total == 0
                            ? 1
                            : (values[i] / total * 10000).round().clamp(
                                1,
                                10000,
                              ),
                        child: InkWell(
                          onTap: () => onSelect(segments[i].id),
                          child: Center(
                            child: Container(height: 12, color: color(i)),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < segments.length; i++)
              Semantics(
                button: true,
                selected: selectedId == segments[i].id,
                child: InkWell(
                  onTap: () => onSelect(segments[i].id),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selectedId == segments[i].id
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: color(i),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(child: Text(segments[i].label)),
                            ],
                          ),
                          Text(
                            segments[i].amount,
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
