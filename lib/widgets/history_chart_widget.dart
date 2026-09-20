import 'dart:async';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      HistoryService.init().catchError((Object error) {
        if (mounted) setState(() => _error = 'История недоступна: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryService.changes,
      builder: (context, value, child) {
        final now = DateTime.now();
        final startTime = now.subtract(Duration(days: _selectedDays));
        final history = HistoryService.segmentsFor(
          widget.host.host,
          startTime,
          now,
        );
        final statistics = HistoryService.statistics(
          widget.host.host,
          startTime,
          now,
        );
        final uptime = statistics.uptimePercent;
        final formatter = _selectedDays == 1
            ? DateFormat('HH:mm')
            : DateFormat('dd.MM');
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.host.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.host.host,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in [1, 7, 30])
                    ChoiceChip(
                      label: Text(days == 1 ? '24 часа' : '$days дней'),
                      selected: _selectedDays == days,
                      onSelected: (_) => setState(() => _selectedDays = days),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.statusUnknown),
                )
              else ...[
                Text(
                  uptime == null
                      ? 'Недостаточно измерений'
                      : 'Сетевой доступ: ${uptime.toStringAsFixed(1)}% времени наблюдения',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Покрытие периода: ${statistics.coveragePercent.toStringAsFixed(1)}% · '
                  'Наблюдалось ${statistics.observed.inMinutes} мин',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Жёлтый — соединение есть, ответ требует внимания. Серый — измерений нет.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label:
                      'История доступности. Покрытие ${statistics.coveragePercent.toStringAsFixed(1)} процентов.',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: UptimePainter(
                          history: history,
                          startTime: startTime,
                          endTime: now,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatter.format(startTime),
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      formatter.format(now),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
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
    canvas.drawRect(Offset.zero & size, Paint()..color = AppTheme.borderSubtle);
    final totalMs = endTime.difference(startTime).inMilliseconds;
    if (totalMs <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final entry in history) {
      final left =
          (entry.timestamp.difference(startTime).inMilliseconds / totalMs)
              .clamp(0.0, 1.0)
              .toDouble() *
          size.width;
      final right =
          (entry.observedUntil.difference(startTime).inMilliseconds / totalMs)
              .clamp(0.0, 1.0)
              .toDouble() *
          size.width;
      if (right <= left) continue;
      final color = switch (entry.state) {
        HostState.online => AppTheme.statusOnline,
        HostState.degraded => AppTheme.statusUnknown,
        HostState.down => AppTheme.statusDown,
        _ => AppTheme.borderSubtle,
      };
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant UptimePainter oldDelegate) =>
      oldDelegate.history != history ||
      oldDelegate.startTime != startTime ||
      oldDelegate.endTime != endTime;
}
