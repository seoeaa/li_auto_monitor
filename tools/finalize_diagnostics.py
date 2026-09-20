from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = root / 'lib/services/network_probe.dart'
s = p.read_text()
old = '      steps[3] = classifyHttpStatus(\n        statusCode,\n'
new = '      steps[3] = classifyHttpStatus(\n        statusCode!,\n'
if old in s:
    s = s.replace(old, new)
elif new not in s:
    raise RuntimeError('Expected HTTP status classification not found')
p.write_text(s)
