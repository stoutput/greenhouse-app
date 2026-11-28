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
    final palette = theme.brightness == Brightness.dark
        ? const [
            Color(0xff73c5ff),
            Color(0xffffb86b),
            Color(0xff65d3c1),
            Color(0xffb3adff),
            Color(0xfff3da7c),
            Color(0xfff398c7),
          ]
        : const [
            Color(0xff006aab),
            Color(0xff994b00),
            Color(0xff00796b),
            Color(0xff5754a6),
            Color(0xff817300),
            Color(0xffa23369),
          ];
    final values = [
      for (final segment in segments)
        (segment.value ?? BigInt.zero).abs().toDouble(),
    ];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    Color color(int i) => palette[i % palette.length];
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
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
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
        ),
      ],
    );
  }
}
