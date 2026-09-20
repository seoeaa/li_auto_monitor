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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Column(
        children: [
          _buildStep('DNS', host.isDnsAvailable, host.resolvedIp),
          const SizedBox(height: 10),
          _buildStep(
            'TCP 443',
            tcpValue,
            host.isTcpAvailable ? 'соединение установлено' : null,
          ),
          const SizedBox(height: 10),
          _buildStep(
            'TLS',
            host.isTlsAvailable,
            host.isTlsAvailable == true ? 'рукопожатие успешно' : null,
          ),
          const SizedBox(height: 10),
          _buildStep(
            'HTTPS',
            host.isHttpAvailable,
            host.httpStatusCode != null ? 'HTTP ${host.httpStatusCode}' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String label, bool? value, String? detail) {
    final color = value == null
        ? AppTheme.textTertiary
        : value
        ? AppTheme.statusOnline
        : AppTheme.statusDown;
    final icon = value == null
        ? Icons.more_horiz
        : value
        ? Icons.check_circle_outline
        : Icons.cancel_outlined;
    final state = value == null
        ? 'ожидание'
        : value
        ? 'OK'
        : 'ошибка';

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          state,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (detail != null && detail.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
