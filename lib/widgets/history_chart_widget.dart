import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/host_status.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';

class HistoryChartWidget extends StatefulWidget {
  final HostStatus host;

  const HistoryChartWidget({super.key, required this.host});

  @override
  State<HistoryChartWidget> createState() => _HistoryChartWidgetState();
}

class _HistoryChartWidgetState extends State<HistoryChartWidget> {
  int _selectedDays = 1;

  @override
  Widget build(BuildContext context) {
    final history = HistoryService.getHistory(widget.host.host);
    history.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final now = DateTime.now();
    final startTime = now.subtract(Duration(days: _selectedDays));
    final chartHistory = _buildChartHistory(history, startTime, now);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;

              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.host.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.host.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 12),
                    _buildRangeSelector(),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  _buildRangeSelector(),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _buildUptimeStatus(),
          const SizedBox(height: 12),
          Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.backgroundCardElevated,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: chartHistory.isEmpty
                ? const Center(
                    child: Text(
                      'Нет данных за период',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: CustomPaint(
                      painter: UptimePainter(
                        history: chartHistory,
                        startTime: startTime,
                        endTime: now,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _buildTimelineLabels(),
        ],
      ),
    );
  }

  List<HistoryEntry> _buildChartHistory(
    List<HistoryEntry> history,
    DateTime startTime,
    DateTime endTime,
  ) {
    HistoryEntry? previous;
    final visible = <HistoryEntry>[];

    for (final entry in history) {
      if (!entry.timestamp.isAfter(startTime)) {
        previous = entry;
        continue;
      }
      if (entry.timestamp.isBefore(endTime)) {
        visible.add(entry);
      }
    }

    if (previous != null) {
      visible.insert(
        0,
        HistoryEntry(
          host: previous.host,
          timestamp: startTime,
          isOnline: previous.isOnline,
        ),
      );
    }

    return visible;
  }

  Widget _buildRangeSelector() {
    final options = <(int, String)>[
      (1, '24ч'),
      (7, '7д'),
      (30, '30д'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final isSelected = _selectedDays == option.$1;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _selectedDays = option.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryCyan.withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                option.$2,
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryCyan
                      : AppTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUptimeStatus() {
    final now = DateTime.now();
    final startTime = now.subtract(Duration(days: _selectedDays));
    final uptimeValue = HistoryService.calculateUptime(
      widget.host.host,
      startTime,
      now,
    );

    if (uptimeValue == null) {
      return const Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            color: AppTheme.textTertiary,
            size: 16,
          ),
          SizedBox(width: 7),
          Text(
            'Недостаточно данных для расчёта',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    final color = uptimeValue >= 99
        ? AppTheme.statusOnline
        : uptimeValue >= 95
        ? AppTheme.statusUnknown
        : AppTheme.statusDown;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'Доступность',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${uptimeValue.toStringAsFixed(1)}%',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLabels() {
    final formatter = _selectedDays == 1
        ? DateFormat('HH:mm')
        : DateFormat('dd.MM');
    final now = DateTime.now();
    final start = now.subtract(Duration(days: _selectedDays));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          formatter.format(start),
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 9,
          ),
        ),
        Text(
          formatter.format(now),
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class UptimePainter extends CustomPainter {
  final List<HistoryEntry> history;
  final DateTime startTime;
  final DateTime endTime;

  UptimePainter({
    required this.history,
    required this.startTime,
    required this.endTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty || !endTime.isAfter(startTime)) return;

    final totalMs = endTime.difference(startTime).inMilliseconds.toDouble();
    if (totalMs <= 0) return;

    final backgroundPaint = Paint()
      ..color = AppTheme.borderSubtle.withOpacity(0.45);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final paint = Paint();
    const gap = 1.0;

    for (int i = 0; i < history.length; i++) {
      final entry = history[i];
      final segmentStart = entry.timestamp.isBefore(startTime)
          ? startTime
          : entry.timestamp;
      final segmentEnd = i + 1 < history.length
          ? history[i + 1].timestamp
          : endTime;

      if (!segmentEnd.isAfter(segmentStart)) continue;

      final startRatio =
          segmentStart.difference(startTime).inMilliseconds / totalMs;
      final endRatio =
          segmentEnd.difference(startTime).inMilliseconds / totalMs;

      final left = (startRatio.clamp(0.0, 1.0) * size.width) + gap / 2;
      final right = (endRatio.clamp(0.0, 1.0) * size.width) - gap / 2;
      if (right <= left) continue;

      paint.color = entry.isOnline
          ? AppTheme.statusOnline.withOpacity(0.82)
          : AppTheme.statusDown.withOpacity(0.82);

      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant UptimePainter oldDelegate) {
    return oldDelegate.history != history ||
        oldDelegate.startTime != startTime ||
        oldDelegate.endTime != endTime;
  }
}
