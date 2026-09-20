import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/host_status.dart';
import '../services/monitor_service.dart';
import '../widgets/host_card.dart';
import '../widgets/history_chart_widget.dart';
import 'info.view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _resumeMonitoring = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  static final _timeFormat = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<MonitorService>(context, listen: false).startMonitoring();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: RefreshIndicator(
              onRefresh: () async {
                final monitor = Provider.of<MonitorService>(
                  context,
                  listen: false,
                );
                await monitor.refreshAllHosts();
              },
              color: AppTheme.primaryCyan,
              backgroundColor: AppTheme.backgroundCardElevated,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  _buildAppBar(),
                  _buildDiagnosisSection(),
                  _buildServiceGroups(),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      titleSpacing: 20,
      backgroundColor: AppTheme.backgroundDark.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: AppTheme.primaryCyan.withValues(alpha: 0.16),
              ),
            ),
            child: const Icon(
              Icons.monitor_heart_outlined,
              color: AppTheme.primaryCyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Li Auto Monitor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: -0.25,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Диагностика сети и сервисов',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _buildHeaderButton(
          icon: Icons.history_rounded,
          tooltip: 'История',
          onPressed: _showHistoryBottomSheet,
        ),
        const SizedBox(width: 6),
        _buildHeaderButton(
          icon: Icons.info_outline_rounded,
          tooltip: 'О приложении',
          onPressed: _openInfo,
        ),
        const SizedBox(width: 14),
      ],
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        backgroundColor: AppTheme.backgroundCardElevated,
        foregroundColor: AppTheme.textSecondary,
        side: const BorderSide(color: AppTheme.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
      icon: Icon(icon, size: 19),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final monitor = context.read<MonitorService>();
    if (state == AppLifecycleState.resumed) {
      if (_resumeMonitoring) monitor.startMonitoring();
      _resumeMonitoring = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _resumeMonitoring = _resumeMonitoring || monitor.isMonitoring;
      monitor.stopMonitoring();
    }
  }

  void _openInfo() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const InfoView(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  void _showHistoryBottomSheet() {
    final monitor = Provider.of<MonitorService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 860
                ? 860.0
                : constraints.maxWidth;

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight * 0.88,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundDark,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusXLarge),
                    ),
                    border: Border(
                      top: BorderSide(color: AppTheme.borderSubtle),
                      left: BorderSide(color: AppTheme.borderSubtle),
                      right: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'История доступности',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Доступность сервисов за выбранный период',
                                    style: TextStyle(
                                      color: AppTheme.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                          itemCount: monitor.hosts.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return HistoryChartWidget(
                              host: monitor.hosts[index],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiagnosisSection() {
    return SliverToBoxAdapter(
      child: Consumer<MonitorService>(
        builder: (context, monitor, child) {
          final state = monitor.overallState;
          final color = _statusColor(state);
          final onlineCount = monitor.primaryHosts
              .where((host) => host.state == HostState.online)
              .length;
          final problemCount = monitor.primaryHosts
              .where(
                (host) =>
                    host.state == HostState.down ||
                    host.state == HostState.degraded,
              )
              .length;
          final total = monitor.primaryHosts.length;
          final lastChecked = monitor.lastCycleCompleted != null
              ? _timeFormat.format(monitor.lastCycleCompleted!)
              : 'ещё не завершена';

          return _content(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                  border: Border.all(
                    color: state == HostState.online
                        ? AppTheme.borderSubtle
                        : color.withValues(alpha: 0.28),
                  ),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            _statusIcon(state),
                            color: color,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                monitor.diagnosisTitle,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.25,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                monitor.diagnosisDetails,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (monitor.isCheckInProgress) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: AppTheme.backgroundCardElevated,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetricChip(
                          icon: Icons.dns_outlined,
                          label: 'Сервисы',
                          value: '$onlineCount/$total',
                          color: onlineCount == total && total > 0
                              ? AppTheme.statusOnline
                              : AppTheme.textSecondary,
                        ),
                        _buildMetricChip(
                          icon: Icons.warning_amber_rounded,
                          label: 'Проблемы',
                          value: '$problemCount',
                          color: problemCount > 0
                              ? AppTheme.statusDown
                              : AppTheme.textTertiary,
                        ),
                        _buildNetworkChip(
                          'Интернет',
                          monitor.internetAvailable,
                        ),
                        _buildNetworkChip('DNS', monitor.dnsAvailable),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: monitor.isCheckInProgress
                              ? null
                              : monitor.refreshAllHosts,
                          icon: monitor.isCheckInProgress
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            monitor.isCheckInProgress
                                ? 'Проверяем'
                                : 'Проверить снова',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _copyReport(monitor),
                          icon: const Icon(Icons.copy_all_outlined, size: 17),
                          label: const Text('Скопировать отчёт'),
                        ),
                        TextButton.icon(
                          onPressed: monitor.isMonitoring
                              ? monitor.stopMonitoring
                              : () => monitor.startMonitoring(),
                          icon: Icon(
                            monitor.isMonitoring
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(
                            monitor.isMonitoring ? 'Пауза' : 'Продолжить',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Последняя проверка: $lastChecked',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          monitor.isMonitoring
                              ? 'Автопроверка через 30 с после завершения'
                              : 'Автопроверка остановлена',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyReport(MonitorService monitor) async {
    await Clipboard.setData(ClipboardData(text: monitor.generateReport()));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Диагностический отчёт скопирован')),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkChip(String label, bool? value) {
    final color = value == null
        ? AppTheme.textTertiary
        : value
        ? AppTheme.statusOnline
        : AppTheme.statusDown;
    final icon = value == null
        ? Icons.more_horiz_rounded
        : value
        ? Icons.check_rounded
        : Icons.close_rounded;
    final stateText = value == null
        ? 'не подтверждено'
        : value
        ? 'OK'
        : 'ошибка';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            '$label · $stateText',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceGroups() {
    return SliverToBoxAdapter(
      child: Consumer<MonitorService>(
        builder: (context, monitor, child) {
          if (monitor.hosts.isEmpty) {
            return _content(
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryCyan,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }

          final categories = <String>[];
          for (final host in monitor.hosts) {
            if (!categories.contains(host.category)) {
              categories.add(host.category);
            }
          }

          final width = MediaQuery.sizeOf(context).width;
          final useColumns = width >= 900 && categories.length == 2;

          final sections = categories.map((category) {
            final hosts = monitor.hosts
                .where((host) => host.category == category)
                .toList();
            return _buildCategorySection(category, hosts);
          }).toList();

          return _content(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: useColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: sections[0]),
                        const SizedBox(width: 16),
                        Expanded(child: sections[1]),
                      ],
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < sections.length; i++) ...[
                          sections[i],
                          if (i != sections.length - 1)
                            const SizedBox(height: 24),
                        ],
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategorySection(String category, List<HostStatus> hosts) {
    final mainHosts = hosts.where((host) => !host.isOptional).toList();
    final problemCount = mainHosts
        .where(
          (host) =>
              host.state == HostState.down || host.state == HostState.degraded,
        )
        .length;
    final checkingCount = mainHosts.where((host) => host.isChecking).length;
    final unknownCount = mainHosts
        .where(
          (host) =>
              host.state == HostState.unknown ||
              host.state == HostState.checking,
        )
        .length;

    final title = category == 'OTA'
        ? 'Обновления автомобиля'
        : category == 'APP'
        ? 'Приложение Li Auto'
        : category;
    final subtitle = category == 'OTA'
        ? 'OTA и сервисы прошивки'
        : category == 'APP'
        ? 'Авторизация и основные API'
        : 'Сетевые сервисы';
    final icon = category == 'OTA'
        ? Icons.system_update_alt_rounded
        : category == 'APP'
        ? Icons.phone_android_rounded
        : Icons.cloud_outlined;

    String summary;
    Color summaryColor;
    if (checkingCount > 0) {
      summary = 'Проверка';
      summaryColor = AppTheme.accentBlue;
    } else if (problemCount > 0) {
      summary = '$problemCount замечаний';
      summaryColor = AppTheme.statusDown;
    } else if (unknownCount > 0 || mainHosts.isEmpty) {
      summary = 'Нет данных';
      summaryColor = AppTheme.textSecondary;
    } else {
      summary = 'Доступны по сети';
      summaryColor = AppTheme.statusOnline;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCardElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Icon(icon, color: AppTheme.textSecondary, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: summaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  summary,
                  style: TextStyle(
                    color: summaryColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < hosts.length; i++) ...[
          HostCard(key: ValueKey(hosts[i].host), host: hosts[i]),
          if (i != hosts.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _content(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: child,
      ),
    );
  }

  Color _statusColor(HostState state) {
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

  IconData _statusIcon(HostState state) {
    switch (state) {
      case HostState.online:
        return Icons.check_circle_outline_rounded;
      case HostState.down:
        return Icons.error_outline_rounded;
      case HostState.degraded:
        return Icons.warning_amber_rounded;
      case HostState.checking:
        return Icons.sync_rounded;
      case HostState.unknown:
        return Icons.more_horiz_rounded;
    }
  }
}
