import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:li_auto_monitor/models/host_status.dart';
import 'package:li_auto_monitor/services/history_service.dart';
import 'package:li_auto_monitor/services/monitor_service.dart';
import 'package:li_auto_monitor/services/network_probe.dart';
import 'package:li_auto_monitor/screens/dashboard.view.dart';
import 'package:li_auto_monitor/widgets/tcp_status_indicator.dart';
import 'package:li_auto_monitor/theme/app_theme.dart';

DiagnosticResult resultFor(int code, {DateTime? at}) => DiagnosticResult(
  steps: [
    const CheckStep(CheckState.success, 'DNS'),
    const CheckStep(CheckState.success, 'TCP', milliseconds: 12),
    const CheckStep(CheckState.success, 'TLS'),
    classifyHttpStatus(code),
  ],
  checkedAt: at ?? DateTime.now(),
  resolvedIp: '127.0.0.1',
  addressFamily: 'IPv4',
  httpStatusCode: code,
);

DiagnosticResult dnsFailure() => DiagnosticResult(steps: const [
  CheckStep(CheckState.failure, 'DNS failed'),
  CheckStep(CheckState.skipped, 'DNS failed'),
  CheckStep(CheckState.skipped, 'DNS failed'),
  CheckStep(CheckState.skipped, 'DNS failed'),
], checkedAt: DateTime.now());

class FakeProbe extends NetworkProbe {
  final Future<DiagnosticResult> Function(String, CheckCancellation) run;
  FakeProbe(this.run);
  @override
  Future<DiagnosticResult> check(String host, CheckCancellation cancellation, {int port = 443, String path = '/'}) => run(host, cancellation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final base = DateTime.utc(2026, 9, 20);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('li-auto-history-');
    await HistoryService.resetForTesting(directory: directory, now: () => base.add(const Duration(days: 1)));
  });
  tearDown(() async {
    await HistoryService.flush();
    await HistoryService.resetForTesting();
    await directory.delete(recursive: true);
  });

  for (final code in [200, 204]) {
    test('HTTP $code confirms only network reachability', () {
      final result = resultFor(code);
      expect(result.state, HostState.online);
      expect(result.steps[3].state, CheckState.success);
      expect(result.vehicleFunctionsVerified, isFalse);
    });
  }
  for (final code in [301, 302, 401, 403, 404, 405, 429, 500, 502, 503, 504]) {
    test('HTTP $code is a visible remark, not a network outage or green health', () {
      final result = resultFor(code);
      expect(result.state, HostState.degraded);
      expect(result.steps[3].state, CheckState.warning);
      expect(result.steps[3].available, isTrue);
      expect(result.hasSecureEvidence, isTrue);
      expect(result.summary, contains('$code'));
    });
  }

  test('unknown and empty groups are never green', () {
    expect(aggregateHostStates([]), HostState.unknown);
    expect(aggregateHostStates([HostState.unknown, HostState.unknown]), HostState.unknown);
    expect(aggregateHostStates([HostState.online, HostState.unknown]), HostState.unknown);
    expect(aggregateHostStates([HostState.online, HostState.online]), HostState.online);
  });

  test('result replacement clears stale IP and downstream failure flags', () {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    host.applyResult(resultFor(200));
    host.resolvedCountry = 'old country';
    host.beginCheck();
    host.applyResult(dnsFailure());
    expect(host.resolvedIp, isNull);
    expect(host.resolvedCountry, isNull);
    expect(host.isTlsAvailable, isNull);
    expect(host.isHttpAvailable, isNull);
    expect(host.checkSteps.skip(1).every((step) => step.state == CheckState.skipped), isTrue);
    host.dispose();
  });

  test('cancel retains the last completed result', () {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    host.applyResult(resultFor(200));
    final checked = host.lastChecked;
    host.beginCheck();
    host.cancelCheck();
    expect(host.state, HostState.online);
    expect(host.isChecking, isFalse);
    expect(host.lastChecked, checked);
    host.dispose();
  });

  Future<void> sample(int seconds, HostState state, {String? session = 'session-a'}) =>
      HistoryService.saveObservations([HistoryEntry(
        host: 'api.invalid', timestamp: base.add(Duration(seconds: seconds)),
        state: state, sessionId: session,
      )]);

  test('one observation does not claim any uptime', () async {
    await sample(0, HostState.online);
    final stats = HistoryService.statistics('api.invalid', base, base.add(const Duration(days: 1)));
    expect(stats.uptimePercent, isNull);
    expect(stats.coveragePercent, 0);
  });

  test('history ends at last measurement instead of extending through the night', () async {
    await sample(0, HostState.online);
    await sample(30, HostState.online);
    final stats = HistoryService.statistics('api.invalid', base, base.add(const Duration(hours: 10)));
    expect(stats.observed, const Duration(seconds: 30));
    expect(stats.uptimePercent, 100);
    expect(stats.coveragePercent, closeTo(100 * 30 / 36000, 0.000001));
  });

  test('long gaps and new sessions never bridge missing observations', () async {
    await sample(0, HostState.online);
    await sample(30, HostState.online);
    await sample(7200, HostState.online);
    await sample(7230, HostState.online);
    await sample(7260, HostState.online, session: 'session-b');
    await sample(7290, HostState.online, session: 'session-b');
    final stats = HistoryService.statistics('api.invalid', base, base.add(const Duration(hours: 3)));
    expect(stats.observed, const Duration(seconds: 90));
    expect(HistoryService.segmentsFor('api.invalid', base, base.add(const Duration(hours: 3))), hasLength(3));
  });

  test('degraded and down durations remain distinct', () async {
    await sample(0, HostState.online);
    await sample(30, HostState.degraded);
    await sample(60, HostState.down);
    await sample(90, HostState.down);
    final stats = HistoryService.statistics('api.invalid', base, base.add(const Duration(seconds: 120)));
    expect(stats.online, const Duration(seconds: 30));
    expect(stats.degraded, const Duration(seconds: 30));
    expect(stats.down, const Duration(seconds: 30));
    expect(stats.uptimePercent, closeTo(200 / 3, 0.000001));
    expect(stats.coveragePercent, 75);
  });

  test('period boundaries clip confirmed intervals', () async {
    await sample(0, HostState.online);
    await sample(60, HostState.online);
    final stats = HistoryService.statistics('api.invalid', base.add(const Duration(seconds: 20)), base.add(const Duration(seconds: 40)));
    expect(stats.observed, const Duration(seconds: 20));
    expect(stats.coveragePercent, 100);
  });

  test('legacy samples migrate without invented continuity', () async {
    await File('${directory.path}/monitor_history.json').writeAsString(jsonEncode([
      {'host': 'api.invalid', 'timestamp': base.toIso8601String(), 'isOnline': true},
      {'host': 'api.invalid', 'timestamp': base.add(const Duration(hours: 8)).toIso8601String(), 'isOnline': true},
    ]));
    await HistoryService.init();
    expect(HistoryService.getHistory('api.invalid'), hasLength(2));
    expect(HistoryService.calculateUptime('api.invalid', base, base.add(const Duration(days: 1))), isNull);
  });

  test('persisted intervals survive reload with concurrent initialization', () async {
    await Future.wait([HistoryService.init(), HistoryService.init()]);
    await sample(0, HostState.degraded);
    await sample(30, HostState.degraded);
    await HistoryService.flush();
    await HistoryService.resetForTesting(directory: directory, now: () => base.add(const Duration(days: 1)));
    await HistoryService.init();
    expect(HistoryService.getHistory('api.invalid').single.state, HostState.degraded);
    expect(HistoryService.statistics('api.invalid', base, base.add(const Duration(hours: 1))).degraded, const Duration(seconds: 30));
  });

  test('corrupt primary history recovers the last valid backup', () async {
    final entry = HistoryEntry(host: 'api.invalid', timestamp: base, state: HostState.online, observedUntil: base.add(const Duration(seconds: 30)), sessionId: 's');
    await File('${directory.path}/monitor_history.v2.json').writeAsString('broken-json');
    await File('${directory.path}/monitor_history.v2.json.bak').writeAsString(jsonEncode({'version': 2, 'entries': [entry.toJson()]}));
    await HistoryService.init();
    expect(HistoryService.getHistory('api.invalid').single.observedUntil, entry.observedUntil);
    await sample(60, HostState.down);
    await HistoryService.resetForTesting(directory: directory, now: () => base.add(const Duration(days: 1)));
    await HistoryService.init();
    expect(HistoryService.getHistory('api.invalid').last.state, HostState.down);
  });

  test('refresh joins the same bounded worker pool', () async {
    var active = 0;
    var peak = 0;
    var calls = 0;
    final probe = FakeProbe((host, token) async {
      active++;
      calls++;
      peak = max(active, peak);
      try {
        await token.wait(Future<void>.delayed(const Duration(milliseconds: 15)));
        return resultFor(200);
      } finally {
        active--;
      }
    });
    final monitor = MonitorService(initialHosts: [for (var i = 0; i < 7; i++) HostStatus.unknown('APP', 'API $i', '$i.invalid')], probe: probe, controlHosts: []);
    final first = monitor.refreshAllHosts();
    final second = monitor.refreshAllHosts();
    expect(identical(first, second), isTrue);
    await first;
    expect(calls, 7);
    expect(peak, lessThanOrEqualTo(3));
    expect(monitor.overallState, HostState.online);
    monitor.dispose();
  });

  test('failed control hosts do not override successful Li Auto TLS evidence', () async {
    final probe = FakeProbe((host, token) async => host == 'api.invalid' ? resultFor(503) : dnsFailure());
    final monitor = MonitorService(initialHosts: [HostStatus.unknown('APP', 'API', 'api.invalid')], probe: probe, controlHosts: ['control.invalid']);
    await monitor.refreshAllHosts();
    expect(monitor.overallState, HostState.degraded);
    expect(monitor.internetAvailable, isTrue);
    expect(monitor.diagnosisTitle, isNot(contains('Нет')));
    monitor.dispose();
  });

  test('optional hosts do not define the main verdict', () async {
    final monitor = MonitorService(initialHosts: [
      HostStatus(category: 'APP', name: 'API', host: 'api.invalid'),
      HostStatus(category: 'OTA', name: 'Test', host: 'test.invalid', isOptional: true),
    ], probe: FakeProbe((host, token) async => host == 'api.invalid' ? resultFor(200) : dnsFailure()), controlHosts: []);
    await monitor.refreshAllHosts();
    expect(monitor.overallState, HostState.online);
    expect(monitor.hosts.last.state, HostState.down);
    monitor.dispose();
  });

  test('dispose cancels the cycle and ignores a late non-cooperative result', () async {
    final pending = Completer<DiagnosticResult>();
    final host = HostStatus.unknown('APP', 'API', 'api.invalid');
    final monitor = MonitorService(initialHosts: [host], probe: FakeProbe((_, token) => pending.future), controlHosts: []);
    final future = monitor.refreshAllHosts();
    var notifications = 0;
    monitor.addListener(() => notifications++);
    monitor.dispose();
    pending.complete(resultFor(200));
    await future;
    expect(notifications, 0);
    expect(host.lastChecked, isNull);
    expect(HistoryService.getHistory(host.host), isEmpty);
    host.dispose();
  });

  test('stop keeps prior results and finishes cancellation promptly', () async {
    final pending = Completer<DiagnosticResult>();
    final host = HostStatus.unknown('APP', 'API', 'api.invalid')..applyResult(resultFor(200));
    final monitor = MonitorService(initialHosts: [host], probe: FakeProbe((_, token) => pending.future), controlHosts: []);
    final future = monitor.refreshAllHosts();
    monitor.stopMonitoring();
    await future.timeout(const Duration(seconds: 1));
    expect(host.state, HostState.online);
    expect(host.isChecking, isFalse);
    pending.complete(dnsFailure());
    monitor.dispose();
  });

  testWidgets('skipped TLS and HTTPS are visible without red failure labels', (tester) async {
    final host = HostStatus.unknown('APP', 'API', 'api.invalid')..applyResult(dnsFailure());
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: TcpStatusIndicator(host: host))));
    expect(find.text('TLS · Не выполнялось'), findsOneWidget);
    expect(find.text('HTTPS · Не выполнялось'), findsOneWidget);
    expect(tester.takeException(), isNull);
    host.dispose();
  });

  testWidgets('initial dashboard does not label unknown groups as reachable', (tester) async {
    final pending = Completer<DiagnosticResult>();
    final monitor = MonitorService(initialHosts: [HostStatus.unknown('APP', 'API', 'api.invalid')], probe: FakeProbe((_, token) => pending.future), controlHosts: []);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: monitor, child: MaterialApp(theme: AppTheme.darkTheme, home: const DashboardView())));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Доступны по сети'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    pending.complete(resultFor(200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
