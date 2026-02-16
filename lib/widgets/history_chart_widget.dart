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
  int _selectedDays = 1; // 1, 7, 30

  @override
  Widget build(BuildContext context) {
    final history = HistoryService.getHistory(widget.host.host);
    final now = DateTime.now();
    final startTime = now.subtract(Duration(days: _selectedDays));

    final filteredHistory = history
        .where((e) => e.timestamp.isAfter(startTime))
        .toList();
    filteredHistory.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.host.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.host.host,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              _buildRangeSelector(),
            ],
          ),
          const SizedBox(height: 24),
          _buildUptimeStatus(filteredHistory),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            width: double.infinity,
            child: CustomPaint(
              painter: UptimePainter(
                history: filteredHistory,
                startTime: startTime,
                endTime: now,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildTimelineLabels(),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [1, 7, 30].map((days) {
        final isSelected = _selectedDays == days;
        return GestureDetector(
          onTap: () => setState(() => _selectedDays = days),
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryCyan.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: isSelected ? AppTheme.primaryCyan : Colors.white10,
              ),
            ),
            child: Text(
              '$daysд',
              style: TextStyle(
                color: isSelected
                    ? AppTheme.primaryCyan
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUptimeStatus(List<HistoryEntry> history) {
    if (history.isEmpty) {
      return const Text(
        'Нет данных за период',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      );
    }

    final onlineCount = history.where((e) => e.isOnline).length;
    final uptime = (onlineCount / history.length * 100).toStringAsFixed(1);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppTheme.statusOnline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Доступность: $uptime%',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLabels() {
    DateFormat formatter = _selectedDays == 1
        ? DateFormat('HH:mm')
        : DateFormat('dd.MM');
    final now = DateTime.now();
    final start = now.subtract(Duration(days: _selectedDays));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          formatter.format(start),
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
        ),
        Text(
          formatter.format(now),
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
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
    if (history.isEmpty) return;

    final paint = Paint()..strokeWidth = 2.0;

    // We can draw bars for each sample, or just fill segments.
    // For large datasets, we should aggregate.

    const double barGap = 1.0;
    final double availableWidth = size.width - (history.length - 1) * barGap;
    final double barWidth = availableWidth / history.length;

    for (int i = 0; i < history.length; i++) {
      final entry = history[i];
      final x = i * (barWidth + barGap);

      paint.color = entry.isOnline
          ? AppTheme.statusOnline.withOpacity(0.8)
          : AppTheme.statusDown.withOpacity(0.8);

      final rect = Rect.fromLTWH(
        x,
        0,
        barWidth.clamp(1.0, 10.0), // Ensure at least 1px wide
        size.height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );

      // Add a subtle glow for online status
      if (entry.isOnline) {
        final glowPaint = Paint()
          ..color = AppTheme.statusOnline.withOpacity(0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRect(rect.inflate(2), glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant UptimePainter oldDelegate) {
    return oldDelegate.history != history ||
        oldDelegate.startTime != startTime ||
        oldDelegate.endTime != endTime;
  }
}
