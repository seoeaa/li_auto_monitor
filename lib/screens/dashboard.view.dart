import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MonitorService>(context, listen: false).startMonitoring();
    });
  }

  @override
  void dispose() {
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
              backgroundColor: AppTheme.backgroundCard,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildAppBar(),
                  _buildDiagnosisSection(),
                  _buildStatsSection(),
                  _buildHostsList(),
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
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppTheme.primaryGradient.createShader(bounds),
                      child: const Text(
                        'Li Auto Monitor',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Диагностика сервисов Li Auto',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              _buildHistoryButton(),
              const SizedBox(width: 12),
              _buildInfoButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    return GestureDetector(
      onTap: () => _showHistoryBottomSheet(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.backgroundCardGlass,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: const Icon(Icons.history, color: Colors.white70, size: 22),
      ),
    );
  }

  void _showHistoryBottomSheet() {
    final monitor = Provider.of<MonitorService>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXLarge),
            ),
            gradient: AppTheme.backgroundGradient,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'История доступности',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: monitor.hosts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return HistoryChartWidget(host: monitor.hosts[index]);
                  },
                  padding: const EdgeInsets.only(bottom: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const InfoView(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.backgroundCardGlass,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: const Icon(Icons.info_outline, color: Colors.white70, size: 22),
      ),
    );
  }

  Widget _buildDiagnosisSection() {
    return SliverToBoxAdapter(
      child: Consumer<MonitorService>(
        builder: (context, monitor, child) {
          final state = monitor.overallState;
          final color = state == HostState.online
              ? AppTheme.statusOnline
              : state == HostState.down
              ? AppTheme.statusDown
              : state == HostState.checking
              ? AppTheme.accentBlue
              : AppTheme.statusUnknown;

          final icon = state == HostState.online
              ? Icons.check_circle_outline
              : state == HostState.down
              ? Icons.error_outline
              : state == HostState.checking
              ? Icons.radar
              : Icons.warning_amber_rounded;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.cardGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                border: Border.all(color: color.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMedium,
                          ),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              monitor.diagnosisTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              monitor.diagnosisDetails,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildNetworkChip(
                        'Интернет',
                        monitor.internetAvailable,
                      ),
                      _buildNetworkChip('DNS', monitor.dnsAvailable),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: monitor.generateReport()),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Диагностический отчёт скопирован',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('Копировать диагностический отчёт'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNetworkChip(String label, bool? value) {
    final color = value == null
        ? AppTheme.statusUnknown
        : value
        ? AppTheme.statusOnline
        : AppTheme.statusDown;
    final icon = value == null
        ? Icons.more_horiz
        : value
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final stateText = value == null
        ? 'проверка'
        : value
        ? 'OK'
        : 'ошибка';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            '$label · $stateText',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return SliverToBoxAdapter(
      child:
          Selector<
            MonitorService,
            ({int online, int down, int total, bool isMonitoring})
          >(
            selector: (_, monitor) {
              final onlineCount = monitor.hosts
                  .where((h) => h.state == HostState.online)
                  .length;
              final downCount = monitor.hosts
                  .where(
                    (h) =>
                        h.state == HostState.down ||
                        h.state == HostState.degraded,
                  )
                  .length;
              return (
                online: onlineCount,
                down: downCount,
                total: monitor.hosts.length,
                isMonitoring: monitor.isMonitoring,
              );
            },
            builder: (context, data, child) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.check_circle_outline,
                            label: 'Онлайн',
                            value: '${data.online}/${data.total}',
                            color: AppTheme.statusOnline,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00FFC2), Color(0xFF00D4AA)],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.error_outline,
                            label: 'Проблемы',
                            value: '${data.down}',
                            color: AppTheme.statusDown,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStatusBadge(data.isMonitoring),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required LinearGradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isMonitoring) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isMonitoring
            ? AppTheme.statusOnline.withOpacity(0.12)
            : AppTheme.statusDown.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: isMonitoring
              ? AppTheme.statusOnline.withOpacity(0.3)
              : AppTheme.statusDown.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Vertical bar indicator
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: isMonitoring ? AppTheme.statusOnline : AppTheme.statusDown,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color:
                      (isMonitoring
                              ? AppTheme.statusOnline
                              : AppTheme.statusDown)
                          .withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isMonitoring ? 'ЖИВОЙ' : 'ПАУЗА',
            style: TextStyle(
              color: isMonitoring ? AppTheme.statusOnline : AppTheme.statusDown,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostsList() {
    return Selector<MonitorService, List<HostStatus>>(
      selector: (_, monitor) => monitor.hosts,
      shouldRebuild: (prev, next) => prev.length != next.length,
      builder: (context, hosts, child) {
        if (hosts.isEmpty) {
          return const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryCyan,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final useGrid = MediaQuery.sizeOf(context).width >= 900;

        Widget buildCard(BuildContext context, int index) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 50)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: HostCard(
              key: ValueKey(hosts[index].host),
              host: hosts[index],
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: useGrid
              ? SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.7,
                      ),
                  delegate: SliverChildBuilderDelegate(
                    buildCard,
                    childCount: hosts.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: buildCard(context, index),
                    ),
                    childCount: hosts.length,
                  ),
                ),
        );
      },
    );
  }
}
