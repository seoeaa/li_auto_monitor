// The original HostState order is retained for existing serialized data.
enum HostState { online, down, unknown, degraded, checking }

enum CheckState { unknown, checking, success, warning, failure, skipped }

class CheckStep {
  final CheckState state;
  final String detail;
  final int? milliseconds;

  const CheckStep(this.state, this.detail, {this.milliseconds});

  bool? get available => switch (state) {
    CheckState.success || CheckState.warning => true,
    CheckState.failure => false,
    _ => null,
  };

  String get label => switch (state) {
    CheckState.unknown => 'Нет данных',
    CheckState.checking => 'Проверка',
    CheckState.success => 'Успешно',
    CheckState.warning => 'Ответ получен',
    CheckState.failure => 'Ошибка',
    CheckState.skipped => 'Не выполнялось',
  };

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'detail': detail,
    'milliseconds': milliseconds,
  };
}

class DiagnosticResult {
  // Order: DNS, TCP, TLS, HTTPS. Every stage describes the same address attempt.
  final List<CheckStep> steps;
  final DateTime checkedAt;
  final String? resolvedIp;
  final String? addressFamily;
  final int? httpStatusCode;
  final List<String> attempts;
  final bool cancelled;

  DiagnosticResult({
    required List<CheckStep> steps,
    required this.checkedAt,
    this.resolvedIp,
    this.addressFamily,
    this.httpStatusCode,
    List<String> attempts = const [],
    this.cancelled = false,
  }) : assert(steps.length == 4),
       steps = List.unmodifiable(steps),
       attempts = List.unmodifiable(attempts);

  HostState get state {
    if (cancelled) return HostState.unknown;
    if (steps.take(3).any((step) => step.state == CheckState.failure)) {
      return HostState.down;
    }
    return switch (steps[3].state) {
      CheckState.success => HostState.online,
      CheckState.warning || CheckState.failure => HostState.degraded,
      _ => HostState.unknown,
    };
  }

  bool get hasSecureEvidence => steps[2].available == true;
  bool get hasNetworkEvidence => steps[1].available == true;

  // A generic unauthenticated HEAD request never validates vehicle functions.
  bool get vehicleFunctionsVerified => false;

  String get summary {
    for (final step in steps) {
      if (step.state == CheckState.failure) return step.detail;
    }
    return steps[3].detail;
  }

  DiagnosticResult withAttempts(List<String> value) => DiagnosticResult(
    steps: steps,
    checkedAt: checkedAt,
    resolvedIp: resolvedIp,
    addressFamily: addressFamily,
    httpStatusCode: httpStatusCode,
    attempts: value,
    cancelled: cancelled,
  );
}

CheckStep classifyHttpStatus(int statusCode, {int? milliseconds}) {
  final String detail;
  final CheckState state;
  if (statusCode >= 200 && statusCode < 300) {
    state = CheckState.success;
    detail =
        'HTTP $statusCode: адрес ответил. Функции автомобиля не проверялись.';
  } else {
    state = CheckState.warning;
    detail = switch (statusCode) {
      >= 300 && < 400 =>
        'HTTP $statusCode: перенаправление; конечный адрес не проверялся.',
      401 => 'HTTP 401: требуется авторизация. HTTPS доступен.',
      403 => 'HTTP 403: запрос отклонён сервером. HTTPS доступен.',
      404 => 'HTTP 404: адрес проверки не найден. HTTPS доступен.',
      405 => 'HTTP 405: метод HEAD не поддерживается. HTTPS доступен.',
      429 => 'HTTP 429: сервер ограничил частоту запросов.',
      >= 500 && < 600 => 'HTTP $statusCode: сервер ответил ошибкой.',
      _ =>
        'HTTP $statusCode: ответ требует проверки; это не ошибка соединения.',
    };
  }
  return CheckStep(state, detail, milliseconds: milliseconds);
}

HostState aggregateHostStates(Iterable<HostState> states) {
  final values = states.toList();
  if (values.isEmpty) return HostState.unknown;
  if (values.every((state) => state == HostState.down)) return HostState.down;
  if (values.any(
    (state) => state == HostState.down || state == HostState.degraded,
  )) {
    return HostState.degraded;
  }
  if (values.contains(HostState.checking)) return HostState.checking;
  if (values.contains(HostState.unknown)) return HostState.unknown;
  return HostState.online;
}
