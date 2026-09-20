import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';

class HopRow extends StatelessWidget {
  final HopInfo hop;

  const HopRow({super.key, required this.hop});

  @override
  Widget build(BuildContext context) {
    final isSuccessful = hop.isSuccessful;
    final color = isSuccessful ? AppTheme.textSecondary : AppTheme.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isSuccessful
                  ? AppTheme.backgroundCard
                  : AppTheme.textTertiary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSuccessful
                    ? AppTheme.borderSubtle
                    : AppTheme.textTertiary.withValues(alpha: 0.2),
              ),
            ),
            child: Center(
              child: Text(
                '${hop.number}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hop.ip ?? 'Нет ответа',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSuccessful
                              ? AppTheme.textPrimary
                              : AppTheme.textTertiary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hop.time != null
                          ? '${hop.time!.toStringAsFixed(1)} ms'
                          : '—',
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                if (hop.isp != null || hop.country != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (hop.isp != null)
                        Expanded(
                          child: Text(
                            hop.isp!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (hop.country != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundCard,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Text(
                            hop.country!,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
