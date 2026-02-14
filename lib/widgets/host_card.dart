import 'package:flutter/material.dart';
import '../models/host_status.dart';
import '../services/monitor_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HostCard extends StatefulWidget {
  final HostStatus host;

  const HostCard({super.key, required this.host});

  @override
  State<HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<HostCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(widget.host.state);
    final timeStr = widget.host.lastChecked != null
        ? DateFormat('HH:mm:ss').format(widget.host.lastChecked!)
        : '--:--:--';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
              if (_isExpanded && !widget.host.isTracing) {
                Provider.of<MonitorService>(
                  context,
                  listen: false,
                ).traceHost(widget.host);
              }
            },
            contentPadding: const EdgeInsets.all(16),
            leading: _buildStatusIndicator(widget.host.state),
            title: Row(
              children: [
                Text(
                  widget.host.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.host.category,
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.host.host,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                if (widget.host.resolvedIp != null)
                  Text(
                    'IP: ${widget.host.resolvedIp} ${widget.host.resolvedCountry != null ? "(${widget.host.resolvedCountry})" : ""}',
                    style: const TextStyle(
                      color: Color(0xFF00FFC2),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (widget.host.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.host.errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.host.rtt != null
                      ? '${widget.host.rtt!.toStringAsFixed(1)} ms'
                      : '-- ms',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          if (_isExpanded) _buildTracerouteDetails(),
        ],
      ),
    );
  }

  Widget _buildTracerouteDetails() {
    if (widget.host.hops.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Нет данных трассировки',
          style: TextStyle(color: Colors.white24),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'АНАЛИЗ МАРШРУТА (TCP TRACE)',
                  style: TextStyle(
                    color: Color(0xFF00FFC2),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (widget.host.isTracing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00FFC2),
                  ),
                ),
            ],
          ),
          if (widget.host.hops.isEmpty && widget.host.isTracing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Запуск трассировки...',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
            ),
          ...widget.host.hops.map((hop) => _buildHopRow(hop)),
          const SizedBox(height: 8),
          _buildTcpStatus(),
        ],
      ),
    );
  }

  Widget _buildHopRow(HopInfo hop) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${hop.number}',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hop.ip ?? '*',
                  style: TextStyle(
                    color: hop.isSuccessful
                        ? Colors.white70
                        : Colors.red.withOpacity(0.5),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                if (hop.isp != null)
                  Text(
                    hop.isp!,
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (hop.country != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                hop.country!,
                style: const TextStyle(color: Color(0xFF00FFC2), fontSize: 10),
              ),
            ),
          Text(
            hop.time != null ? '${hop.time!.toStringAsFixed(1)}ms' : '*',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTcpStatus() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.host.isTcpAvailable
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            widget.host.isTcpAvailable ? Icons.check_circle : Icons.error,
            size: 14,
            color: widget.host.isTcpAvailable ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            widget.host.isTcpAvailable
                ? 'TCP ПОРТ 443 ДОСТУПЕН'
                : 'TCP ПОРТ 443 ЗАБЛОКИРОВАН',
            style: TextStyle(
              color: widget.host.isTcpAvailable ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(HostState state) {
    final color = _getStatusColor(state);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(HostState state) {
    switch (state) {
      case HostState.online:
        return const Color(0xFF00FFC2);
      case HostState.down:
        return Colors.redAccent;
      case HostState.unknown:
        return Colors.orangeAccent;
    }
  }
}
