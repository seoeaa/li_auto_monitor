import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';

class TcpStatusIndicator extends StatelessWidget {
  final HostStatus host;

  const TcpStatusIndicator({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final tcpValue = host.isDnsAvailable == true
        ? host.isTcpAvailable
        : null;

    final steps = [
      ('DNS', host.isDnsAvailable, host.resolvedIp),
      ('TCP 443', tcpValue, host.isTcpAvailable ? 'Соединение установлено' : null),
      ('TLS', host.isTlsAvailable, host.isTlsAvailable == true ? 'Защищённое соединение' : null),
      (
        'HTTPS',
        host.isHttpAvailable,
        host.httpStatusCode != null ? 'HTTP ${host.httpStatusCode}' : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        const gap = 8.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: steps
              .map(
                (step) => SizedBox(
                  width: itemWidth,
                  child: _buildStep(step.$1, step.$2, step.$3),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildStep(String label, bool? value, String? detail) {
    final color = value == null
        ? AppTheme.textTertiary
        : value
        ? AppTheme.statusOnline
        : AppTheme.statusDown;
    final icon = value == null
        ? Icons.more_horiz_rounded
        : value
        ? Icons.check_rounded
        : Icons.close_rounded;
    final state = value == null
        ? 'Ожидание'
        : value
        ? 'Работает'
        : 'Ошибка';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail ?? state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: detail != null ? AppTheme.textTertiary : color,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
