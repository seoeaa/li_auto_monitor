import 'dart:async';
import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'traceroute_details.dart';

class HostCard extends StatefulWidget {
  final HostStatus host;

  const HostCard({super.key, required this.host});

  @override
  State<HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<HostCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  bool _statusChanged = false;
  HostState? _lastState;
  Timer? _pulseTimer;

  static final _timeFormat = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );

    _lastState = widget.host.state;
    widget.host.addListener(_onHostStateChanged);
  }

  void _onHostStateChanged() {
    if (widget.host.state != _lastState) {
      setState(() {
        _statusChanged = true;
        _lastState = widget.host.state;
      });
      _pulseTimer?.cancel();
      _pulseTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() {
            _statusChanged = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(HostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host.removeListener(_onHostStateChanged);
      widget.host.addListener(_onHostStateChanged);
      _lastState = widget.host.state;
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    widget.host.removeListener(_onHostStateChanged);
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.host,
      builder: (context, _) {
        final statusColor = _getStatusColor(widget.host.state);
        final timeStr = widget.host.lastChecked != null
            ? _timeFormat.format(widget.host.lastChecked!)
            : '--:--:--';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(
              color: _statusChanged
                  ? statusColor.withValues(alpha: 0.55)
                  : AppTheme.borderSubtle,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _toggleExpand,
                    child: Column(
                      children: [
                        _buildMainContent(statusColor, timeStr),
                        _buildHealthStrip(),
                      ],
                    ),
                  ),
                ),
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  child: TracerouteDetails(host: widget.host),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent(Color statusColor, String timeStr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              _getStatusIcon(widget.host.state),
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.host.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.host.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
                if (widget.host.errorMessage != null &&
                    widget.host.state != HostState.checking) ...[
                  const SizedBox(height: 5),
                  Text(
                    widget.host.errorMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.host.rtt != null)
                Text(
                  '${widget.host.rtt!.toStringAsFixed(0)} ms',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                const Text(
                  '—',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textTertiary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStrip() {
    final tcpValue = widget.host.isDnsAvailable == true
        ? widget.host.isTcpAvailable
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _buildHealthStep('DNS', widget.host.isDnsAvailable),
          _buildHealthStep('TCP', tcpValue),
          _buildHealthStep('TLS', widget.host.isTlsAvailable),
          _buildHealthStep('HTTPS', widget.host.isHttpAvailable),
        ],
      ),
    );
  }

  Widget _buildHealthStep(String label, bool? value) {
    final color = value == null
        ? AppTheme.textTertiary
        : value
        ? AppTheme.statusOnline
        : AppTheme.statusDown;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: value == null ? 0.06 : 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: value == null ? AppTheme.textTertiary : color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _getStatusLabel(widget.host.state),
        style: TextStyle(
          color: statusColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _getStatusLabel(HostState state) {
    switch (state) {
      case HostState.online:
        return 'РАБОТАЕТ';
      case HostState.down:
        return 'ОШИБКА';
      case HostState.degraded:
        return 'НЕСТАБИЛЬНО';
      case HostState.checking:
        return 'ПРОВЕРКА';
      case HostState.unknown:
        return 'ОЖИДАНИЕ';
    }
  }

  IconData _getStatusIcon(HostState state) {
    switch (state) {
      case HostState.online:
        return Icons.check_rounded;
      case HostState.down:
        return Icons.close_rounded;
      case HostState.degraded:
        return Icons.warning_amber_rounded;
      case HostState.checking:
        return Icons.sync_rounded;
      case HostState.unknown:
        return Icons.more_horiz_rounded;
    }
  }

  Color _getStatusColor(HostState state) {
    switch (state) {
      case HostState.online:
        return AppTheme.statusOnline;
      case HostState.down:
        return AppTheme.statusDown;
      case HostState.degraded:
        return AppTheme.statusUnknown;
      case HostState.checking:
        return AppTheme.accentBlue;
      case HostState.unknown:
        return AppTheme.textTertiary;
    }
  }
}
