import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';
import 'hop_row.dart';
import 'tcp_status_indicator.dart';

class TracerouteDetails extends StatelessWidget {
  final HostStatus host;

  const TracerouteDetails({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppTheme.primaryGradient.createShader(bounds),
                  child: const Icon(Icons.route, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  'АНАЛИЗ МАРШРУТА',
                  style: TextStyle(
                    color: AppTheme.primaryCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                if (host.isTracing)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryCyan.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),

          if (host.hops.isEmpty && host.isTracing)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'Запуск трассировки...',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (host.hops.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'Нет данных трассировки',
                style: TextStyle(color: Colors.white24),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                children: host.hops.map((hop) => HopRow(hop: hop)).toList(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: TcpStatusIndicator(host: host),
          ),
        ],
      ),
    );
  }
}
