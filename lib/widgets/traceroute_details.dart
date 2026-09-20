import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host_status.dart';
import '../services/monitor_service.dart';
import '../theme/app_theme.dart';
import 'hop_row.dart';
import 'tcp_status_indicator.dart';

class TracerouteDetails extends StatelessWidget {
  final HostStatus host;

  const TracerouteDetails({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderSubtle, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Проверка соединения',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TcpStatusIndicator(host: host),
          if (host.diagnosis != null && host.diagnosis!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppTheme.textTertiary,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      host.diagnosis!,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Маршрут до сервера',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      host.traceMessage ??
                          'ICMP: отсутствие ответа не доказывает блокировку',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: host.isTracing
                    ? () => context.read<MonitorService>().stopTrace(host)
                    : () => context.read<MonitorService>().traceHost(host),
                icon: host.isTracing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.route_outlined, size: 16),
                label: Text(host.isTracing ? 'Остановить' : 'Проверить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (host.isTracing && host.hops.isEmpty)
            const _RoutePlaceholder(text: 'Ищем сетевые узлы...')
          else if (host.hops.isEmpty)
            const _RoutePlaceholder(
              text:
                  'Маршрут ещё не проверялся. Запустите его при проблемах со связью.',
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.backgroundCardElevated,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: host.hops.map((hop) => HopRow(hop: hop)).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutePlaceholder extends StatelessWidget {
  final String text;

  const _RoutePlaceholder({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
