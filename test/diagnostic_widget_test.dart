import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:li_auto_monitor/models/host_status.dart';
import 'package:li_auto_monitor/services/monitor_service.dart';
import 'package:li_auto_monitor/screens/dashboard.view.dart';
import 'package:li_auto_monitor/widgets/tcp_status_indicator.dart';
import 'package:li_auto_monitor/theme/app_theme.dart';

class IdleMonitor extends MonitorService {
  IdleMonitor(List<HostStatus> hosts)
    : super(initialHosts: hosts, controlHosts: []);
  @override
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {}
}

void main() {
  testWidgets('skipped TLS and HTTPS remain explicit at narrow width', (
    tester,
  ) async {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    host.applyResult(
      DiagnosticResult(
        steps: const [
          CheckStep(CheckState.failure, 'DNS failed'),
          CheckStep(CheckState.skipped, 'DNS failed'),
          CheckStep(CheckState.skipped, 'DNS failed'),
          CheckStep(CheckState.skipped, 'DNS failed'),
        ],
        checkedAt: DateTime.now(),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: TcpStatusIndicator(host: host)),
      ),
    );
    expect(find.text('TLS · Не выполнялось'), findsOneWidget);
    expect(find.text('HTTPS · Не выполнялось'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    host.dispose();
  });

  testWidgets('initial dashboard does not report unknown groups as working', (
    tester,
  ) async {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    final monitor = IdleMonitor([host]);
    await tester.pumpWidget(
      ChangeNotifierProvider<MonitorService>.value(
        value: monitor,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const DashboardView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Доступны по сети'), findsNothing);
    expect(find.text('Нет данных'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    await tester.pump();
    host.dispose();
  });
}
