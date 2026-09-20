import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';

class TcpStatusIndicator extends StatelessWidget {
  final HostStatus host;
  const TcpStatusIndicator({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    const labels = ['DNS', 'TCP 443', 'TLS', 'HTTPS'];
    final steps = host.checkSteps;
    return Column(children: [
      for (var index = 0; index < steps.length; index++) ...[
        _buildStep(labels[index], steps[index]),
        if (index < steps.length - 1) const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _buildStep(String label, CheckStep value) {
    final color = switch (value.state) {
      CheckState.success => AppTheme.statusOnline,
      CheckState.warning => AppTheme.statusUnknown,
      CheckState.failure => AppTheme.statusDown,
      CheckState.checking => AppTheme.accentBlue,
      _ => AppTheme.textSecondary,
    };
    final icon = switch (value.state) {
      CheckState.success => Icons.check_circle_outline,
      CheckState.warning => Icons.info_outline,
      CheckState.failure => Icons.cancel_outlined,
      CheckState.checking => Icons.sync,
      _ => Icons.remove_circle_outline,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · ${value.label}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(value.detail, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          if (value.milliseconds != null)
            Text('${value.milliseconds} мс', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ])),
      ]),
    );
  }
}
