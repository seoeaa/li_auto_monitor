from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]

p = root / 'lib/services/network_probe.dart'
s = p.read_text()
s = s.replace('      await subscription.cancel();', '      unawaited(subscription.cancel().catchError((Object _) {}));')
s = s.replace("    unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));", "    try {\n      unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));\n    } catch (_) {\n      // The other layer may already have closed the shared transport.\n    }")
p.write_text(s)

p = root / 'lib/services/history_service.dart'
s = p.read_text().replace("'timestamp': timestamp.toIso8601String()", "'timestamp': timestamp.toUtc().toIso8601String()")
s = s.replace("'observedUntil': observedUntil.toIso8601String()", "'observedUntil': observedUntil.toUtc().toIso8601String()")
p.write_text(s)

p = root / 'test/diagnostic_logic_test.dart'
s = p.read_text()
start = s.find('  testWidgets(')
if start >= 0:
    s = s[:start] + '}\n'
p.write_text(s)

p = root / 'test/diagnostic_widget_test.dart'
if not p.exists():
    p.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:li_auto_monitor/models/host_status.dart';
import 'package:li_auto_monitor/services/monitor_service.dart';
import 'package:li_auto_monitor/screens/dashboard.view.dart';
import 'package:li_auto_monitor/widgets/tcp_status_indicator.dart';
import 'package:li_auto_monitor/theme/app_theme.dart';

// These assertions exercise the initial presentation; live scheduling and
// cancellation have separate service tests using controlled probes.
class IdleMonitor extends MonitorService {
  IdleMonitor(List<HostStatus> hosts) : super(initialHosts: hosts, controlHosts: []);
  @override
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {}
}

void main() {
  testWidgets('skipped TLS and HTTPS remain explicit at narrow width', (tester) async {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    host.applyResult(DiagnosticResult(steps: const [
      CheckStep(CheckState.failure, 'DNS failed'),
      CheckStep(CheckState.skipped, 'DNS failed'),
      CheckStep(CheckState.skipped, 'DNS failed'),
      CheckStep(CheckState.skipped, 'DNS failed'),
    ], checkedAt: DateTime.now()));
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme,
      home: Scaffold(body: TcpStatusIndicator(host: host))));
    expect(find.text('TLS · Не выполнялось'), findsOneWidget);
    expect(find.text('HTTPS · Не выполнялось'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    host.dispose();
  });

  testWidgets('initial dashboard does not report unknown groups as working', (tester) async {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    final monitor = IdleMonitor([host]);
    await tester.pumpWidget(ChangeNotifierProvider<MonitorService>.value(value: monitor,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DashboardView())));
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
''')

p = root / 'README.md'
s = p.read_text().replace('На этом же соединении HttpClient выполняет TLS', 'На этом же соединении RawSecureSocket выполняет TLS')
p.write_text(s)
subprocess.run(['dart', 'format', 'lib', 'test'], cwd=root, check=True)
