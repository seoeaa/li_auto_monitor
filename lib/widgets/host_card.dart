import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/host_status.dart';

class HostCard extends StatelessWidget {
  final HostStatus host;

  const HostCard({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(host.state);
    final statusText = _getStatusText(host.state);
    final lastChecked = host.lastChecked != null
        ? DateFormat('HH:mm:ss').format(host.lastChecked!)
        : '--:--:--';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host.host,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric(
                'RTT',
                host.rtt != null
                    ? '${host.rtt!.toStringAsFixed(1)} ms'
                    : '-- ms',
                statusColor,
              ),
              _buildMetric(
                'Category',
                host.category,
                Colors.white.withOpacity(0.7),
              ),
              _buildMetric(
                'Last Check',
                lastChecked,
                Colors.white.withOpacity(0.7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(HostState state) {
    switch (state) {
      case HostState.online:
        return const Color(0xFF00FFC2);
      case HostState.down:
        return const Color(0xFFFF4B2B);
      case HostState.unknown:
        return Colors.amber;
    }
  }

  String _getStatusText(HostState state) {
    switch (state) {
      case HostState.online:
        return 'ONLINE';
      case HostState.down:
        return 'DOWN';
      case HostState.unknown:
        return 'WAITING';
    }
  }
}
