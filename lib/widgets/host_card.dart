import 'dart:async';
import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../services/monitor_service.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
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
      _pulseTimer = Timer(const Duration(milliseconds: 1500), () {
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
      if (!widget.host.isTracing) {
        Provider.of<MonitorService>(
          context,
          listen: false,
        ).traceHost(widget.host);
      }
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

        return GestureDetector(
          onTap: _toggleExpand,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
              border: Border.all(color: statusColor.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
              child: Row(
                children: [
                  // Vertical status bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOut,
                    width: 4,
                    height: 100,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        bottomLeft: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(
                            _statusChanged ? 0.8 : 0.5,
                          ),
                          blurRadius: _statusChanged ? 24 : 8,
                          spreadRadius: _statusChanged ? 4 : 1,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildMainContent(statusColor, timeStr),
                        SizeTransition(
                          sizeFactor: _expandAnimation,
                          child: TracerouteDetails(host: widget.host),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent(Color statusColor, String timeStr) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Host info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.host.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _buildCategoryBadge(),
                const SizedBox(height: 6),
                Text(
                  widget.host.host,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (widget.host.resolvedIp != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: AppTheme.primaryCyan.withOpacity(0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.host.resolvedIp}',
                        style: const TextStyle(
                          color: AppTheme.primaryCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.host.resolvedCountry != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryCyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.host.resolvedCountry!,
                            style: const TextStyle(
                              color: AppTheme.primaryCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (widget.host.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.host.errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // RTT & Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.host.rtt != null
                    ? widget.host.rtt!.toStringAsFixed(1)
                    : '--',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'ms',
                style: TextStyle(
                  color: statusColor.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                timeStr,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),
          // Expand indicator
          AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            child: const Icon(
              Icons.keyboard_arrow_down,
              color: AppTheme.textSecondary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Text(
        widget.host.category,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getStatusColor(HostState state) {
    switch (state) {
      case HostState.online:
        return AppTheme.statusOnline;
      case HostState.down:
        return AppTheme.statusDown;
      case HostState.unknown:
        return AppTheme.statusUnknown;
    }
  }
}
