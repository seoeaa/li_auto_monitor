import 'package:flutter/material.dart';
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
                      'Мониторинг сервисов',
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
                  .where((h) => h.state == HostState.down)
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

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
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
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HostCard(
                    key: ValueKey(hosts[index].host),
                    host: hosts[index],
                  ),
                ),
              );
            }, childCount: hosts.length),
          ),
        );
      },
    );
  }
}
