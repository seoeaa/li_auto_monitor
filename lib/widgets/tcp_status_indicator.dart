import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';

class TcpStatusIndicator extends StatelessWidget {
  final HostStatus host;

  const TcpStatusIndicator({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final isAvailable = host.isTcpAvailable;
    final color = isAvailable ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            isAvailable ? Icons.verified : Icons.block,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            isAvailable ? 'TCP ПОРТ 443 ДОСТУПЕН' : 'TCP ПОРТ 443 ЗАБЛОКИРОВАН',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
