"""Apply the reviewed model/UI changes in the isolated verification checkout.
This temporary script is removed before the final merge.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
changes = {}

def read(path):
    return (root / path).read_text()

def replace(text, old, new):
    if old in text:
        return text.replace(old, new)
    if new in text:
        return text
    raise RuntimeError('Expected source block is missing: ' + old[:100])

# Preserve existing public names and persisted HostState indices.
p = 'lib/models/host_status.dart'
s = read(p)
if 'DiagnosticResult? diagnosticResult;' not in s:
    s = replace(s, "import 'package:flutter/foundation.dart';", "import 'package:flutter/foundation.dart';\nimport 'diagnostic_result.dart';\nexport 'diagnostic_result.dart';")
    s = replace(s, 'enum HostState { online, down, unknown, degraded, checking }\n', '')
    s = replace(s, '  final String host;\n', '  final String host;\n  final bool isOptional;\n')
    s = replace(s, '    required this.host,\n', '    required this.host,\n    this.isOptional = false,\n')
    block = r'''
  DiagnosticResult? diagnosticResult;
  String? traceMessage;
  bool _isChecking = false;
  HostState? _stateBeforeCheck;
  bool get isChecking => _isChecking;

  List<CheckStep> get checkSteps {
    if (diagnosticResult != null) return diagnosticResult!.steps;
    return List.generate(4, (index) => CheckStep(
      _isChecking && index == 0 ? CheckState.checking : CheckState.unknown,
      'Нет завершённого измерения.',
    ));
  }

  void beginCheck() {
    if (_isChecking) return;
    _isChecking = true;
    _stateBeforeCheck = _state;
    if (_lastChecked == null) _state = HostState.checking;
    notifyListeners();
  }

  void cancelCheck() {
    if (!_isChecking) return;
    _isChecking = false;
    _state = _stateBeforeCheck ?? HostState.unknown;
    notifyListeners();
  }

  void applyResult(DiagnosticResult result) {
    if (result.cancelled) {
      cancelCheck();
      return;
    }
    diagnosticResult = result;
    _isChecking = false;
    _state = result.state;
    _isDnsAvailable = result.steps[0].available;
    _isTcpAvailable = result.steps[1].available == true;
    _isTlsAvailable = result.steps[2].available;
    _isHttpAvailable = result.steps[3].available;
    _httpStatusCode = result.httpStatusCode;
    if (_resolvedIp != result.resolvedIp) _resolvedCountry = null;
    _resolvedIp = result.resolvedIp;
    // Kept for compatibility; the UI/report explicitly label this as TCP time.
    _rtt = result.steps[1].milliseconds?.toDouble();
    _diagnosis = result.summary;
    _errorMessage = result.state == HostState.online ? null : result.summary;
    _lastChecked = result.checkedAt;
    notifyListeners();
  }

'''
    s = replace(s, '  HostState get state => _state;', block + '  HostState get state => _state;')
    s = replace(s, "    'host': host,", "    'host': host,\n    'isOptional': isOptional,")
    s = replace(s, "      host: json['host'],", "      host: json['host'],\n      isOptional: json['isOptional'] == true,")
changes[p] = s

p = 'lib/config/hosts_config.dart'
s = read(p)
for name in ['OTA Test', 'OTA OnTest']:
    s = replace(s, "'name': '" + name + "',\n      'host'", "'name': '" + name + "',\n      'optional': 'true',\n      'host'")
changes[p] = s

p = 'lib/widgets/host_card.dart'
s = read(p)
if 'final steps = widget.host.checkSteps;' not in s:
    start = s.index('  Widget _buildHealthStrip()')
    end = s.index('  Widget _buildStatusBadge(', start)
    s = s[:start] + r'''  Widget _buildHealthStrip() {
    final steps = widget.host.checkSteps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        _buildHealthStep('DNS', steps[0]),
        _buildHealthStep('TCP', steps[1]),
        _buildHealthStep('TLS', steps[2]),
        _buildHealthStep('HTTPS', steps[3]),
      ]),
    );
  }

  Widget _buildHealthStep(String label, CheckStep value) {
    final color = switch (value.state) {
      CheckState.success => AppTheme.statusOnline,
      CheckState.warning => AppTheme.statusUnknown,
      CheckState.failure => AppTheme.statusDown,
      CheckState.checking => AppTheme.accentBlue,
      _ => AppTheme.textSecondary,
    };
    final icon = switch (value.state) {
      CheckState.success => Icons.check_rounded,
      CheckState.warning => Icons.info_outline,
      CheckState.failure => Icons.close_rounded,
      _ => Icons.remove_rounded,
    };
    return Tooltip(
      message: '${value.label}: ${value.detail}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

''' + s[end:]
    s = replace(s, "'${widget.host.rtt!.toStringAsFixed(0)} ms'", "'${widget.host.rtt!.toStringAsFixed(0)} мс · TCP'")
    s = replace(s, "return 'РАБОТАЕТ';", "return 'ДОСТУПЕН';")
    s = replace(s, "return 'НЕСТАБИЛЬНО';", "return 'ВНИМАНИЕ';")
    s = replace(s, '_getStatusLabel(widget.host.state),', "widget.host.isChecking ? 'ПРОВЕРКА' : _getStatusLabel(widget.host.state),")
    s = replace(s, '                        widget.host.name,', "                        widget.host.isOptional ? '${widget.host.name} · доп.' : widget.host.name,")
changes[p] = s

p = 'lib/screens/dashboard.view.dart'
s = read(p)
if 'WidgetsBindingObserver' not in s:
    s = replace(s, 'with SingleTickerProviderStateMixin {', 'with SingleTickerProviderStateMixin, WidgetsBindingObserver {\n  bool _resumeMonitoring = false;')
    s = replace(s, '    super.initState();', '    super.initState();\n    WidgetsBinding.instance.addObserver(this);')
    s = replace(s, '    _animationController.dispose();', '    WidgetsBinding.instance.removeObserver(this);\n    _animationController.dispose();')
    s = replace(s, '      Provider.of<MonitorService>(context, listen: false).startMonitoring();', '      if (mounted) Provider.of<MonitorService>(context, listen: false).startMonitoring();')
    s = replace(s, '  void _openInfo() {', r'''  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final monitor = context.read<MonitorService>();
    if (state == AppLifecycleState.resumed) {
      if (_resumeMonitoring) monitor.startMonitoring();
      _resumeMonitoring = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _resumeMonitoring = _resumeMonitoring || monitor.isMonitoring;
      monitor.stopMonitoring();
    }
  }

  void _openInfo() {''')
    start = s.index('  Widget _buildDiagnosisSection()')
    end = s.index('  Future<void> _copyReport(', start)
    block = s[start:end].replace('monitor.hosts', 'monitor.primaryHosts')
    block = replace(block, "label: const Text('Скопировать отчёт'),\n                        ),", "label: const Text('Скопировать отчёт'),\n                        ),\n                        TextButton.icon(\n                          onPressed: monitor.isMonitoring ? monitor.stopMonitoring : () => monitor.startMonitoring(),\n                          icon: Icon(monitor.isMonitoring ? Icons.pause_rounded : Icons.play_arrow_rounded),\n                          label: Text(monitor.isMonitoring ? 'Пауза' : 'Продолжить'),\n                        ),")
    block = replace(block, "                        const Text(\n                          'Автопроверка каждые 30 секунд',\n                          style: TextStyle(", "                        Text(\n                          monitor.isMonitoring ? 'Автопроверка через 30 с после завершения' : 'Автопроверка остановлена',\n                          style: const TextStyle(")
    s = s[:start] + block + s[end:]
    s = replace(s, "? 'проверка'\n        : value", "? 'не подтверждено'\n        : value")
    start = s.index('  Widget _buildCategorySection(')
    end = s.index('    final title =', start)
    s = s[:start] + r'''  Widget _buildCategorySection(String category, List<HostStatus> hosts) {
    final mainHosts = hosts.where((host) => !host.isOptional).toList();
    final problemCount = mainHosts.where((host) =>
        host.state == HostState.down || host.state == HostState.degraded).length;
    final checkingCount = mainHosts.where((host) => host.isChecking).length;
    final unknownCount = mainHosts.where((host) =>
        host.state == HostState.unknown || host.state == HostState.checking).length;

''' + s[end:]
    s = replace(s, "    } else {\n      summary = 'Все работают';", "    } else if (unknownCount > 0 || mainHosts.isEmpty) {\n      summary = 'Нет данных';\n      summaryColor = AppTheme.textSecondary;\n    } else {\n      summary = 'Доступны по сети';")
    s = replace(s, "summary = '$problemCount проблем';", "summary = '$problemCount замечаний';")
changes[p] = s

p = 'lib/widgets/traceroute_details.dart'
s = read(p)
s = replace(s, "'Дополнительная техническая проверка'", "host.traceMessage ?? 'ICMP: отсутствие ответа не доказывает блокировку'")
# The column now uses a host-specific description and cannot be const.
s = replace(s, '              const Expanded(\n                child: Column(', '              Expanded(\n                child: Column(')
s = replace(s, '                onPressed: host.isTracing\n                    ? null', '                onPressed: host.isTracing\n                    ? () => context.read<MonitorService>().stopTrace(host)')
s = replace(s, "label: Text(host.isTracing ? 'Проверяем' : 'Проверить')", "label: Text(host.isTracing ? 'Остановить' : 'Проверить')")
changes[p] = s

p = 'lib/widgets/hop_row.dart'
s = read(p).replace('AppTheme.statusDown', 'AppTheme.textTertiary')
changes[p] = s

p = 'lib/screens/info.view.dart'
s = read(p)
s = replace(s, "'отдельно запустить анализ маршрута и посмотреть, на каком сетевом '\n            'участке начинаются проблемы.'", "'отдельно запустить ICMP-трассировку. Отсутствие ответа промежуточного '\n            'узла не доказывает блокировку. Проверка выполняется с текущего '\n            'устройства; авторизация и функции автомобиля не проверяются.'")
changes[p] = s

for path, content in changes.items():
    if read(path) != content:
        (root / path).write_text(content)
        print('UPDATED', path)
