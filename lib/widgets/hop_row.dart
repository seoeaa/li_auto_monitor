import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';

class HopRow extends StatelessWidget {
  final HopInfo hop;

  const HopRow({super.key, required this.hop});

  @override
  Widget build(BuildContext context) {
    final isSuccessful = hop.isSuccessful;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isSuccessful
                  ? AppTheme.primaryCyan.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '${hop.number}',
                style: TextStyle(
                  color: isSuccessful
                      ? AppTheme.primaryCyan
                      : Colors.red.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hop.ip ?? '*',
                  style: TextStyle(
                    color: isSuccessful
                        ? Colors.white70
                        : Colors.red.withOpacity(0.5),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hop.isp != null)
                  Text(
                    hop.isp!,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (hop.country != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hop.country!,
                style: const TextStyle(
                  color: AppTheme.primaryCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              hop.time != null ? '${hop.time!.toStringAsFixed(1)}ms' : '*',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
