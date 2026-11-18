#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt
set -e

write_original_inputs() {
  mkdir -p /home/user/data /home/user/output
  cat > /home/user/data/system_a.json <<'EOF'
[
  {"timestamp": "2023-10-01T10:00:00Z", "msg": "DB connection timeout!", "severity": "HIGH"},
  {"timestamp": "2023-10-01T10:05:00Z", "msg": "Disk space low on /var", "severity": "MEDIUM"},
  {"timestamp": "2023-10-01T10:15:00Z", "msg": "CPU usage at 99%", "severity": "HIGH"},
  {"timestamp": "2023-10-01T10:18:00Z", "msg": "Network partition detected", "severity": "CRITICAL"}
]
EOF
  cat > /home/user/data/system_b.csv <<'EOF'
timestamp,message,severity
2023-10-01T10:01:00Z,"Db connection TIMEOUT!!",
2023-10-01T10:02:00Z,"Db connection timeout",
2023-10-01T10:08:00Z,"Db connection timeout",
2023-10-01T10:09:00Z,"Db connection timeout",
2023-10-01T10:12:00Z,"Memory leak detected in caching layer",CRITICAL
2023-10-01T10:16:00Z,"Cpu usage at 99 percent",
2023-10-01T10:20:00Z,"Completely unrelated error",
EOF
}

# Locate an actual Go main package, preferring code that references the required ETL paths.
python3 <<'PY'
import os, re
candidates = []
for root, dirs, files in os.walk('/home/user'):
    dirs[:] = [d for d in dirs if d not in {'.cache', '.git', 'go', 'output', 'data'}]
    gofiles = [os.path.join(root, f) for f in files if f.endswith('.go') and not f.endswith('_test.go')]
    if not gofiles:
        continue
    texts = []
    for path in gofiles:
        try:
            texts.append(open(path, encoding='utf-8').read())
        except OSError:
            texts.append('')
    joined = '\n'.join(texts)
    if re.search(r'(?m)^\s*package\s+main\b', joined) and re.search(r'\bfunc\s+main\s*\(', joined):
        score = sum(term in joined for term in ('system_a.json', 'system_b.csv', 'unified.jsonl', 'anomalies.txt'))
        candidates.append((-score, root, gofiles))
assert candidates, 'No Go main program was found under /home/user'
candidates.sort(key=lambda x: (x[0], x[1]))
_, root, files = candidates[0]
with open('/tmp/etl_source_dir', 'w') as f:
    f.write(root)
with open('/tmp/etl_go_files', 'w') as f:
    for path in files:
        f.write(path + '\n')
PY

SOURCE_DIR=$(cat /tmp/etl_source_dir)
mapfile -t GO_FILES < /tmp/etl_go_files
(cd "$SOURCE_DIR" && timeout 60s go build -o /tmp/submitted_etl "${GO_FILES[@]}")
test -x /tmp/submitted_etl

run_submission() {
  rm -f /home/user/output/unified.jsonl /home/user/output/anomalies.txt
  (cd "$SOURCE_DIR" && timeout 30s /tmp/submitted_etl)
  test -f /home/user/output/unified.jsonl
  test -f /home/user/output/anomalies.txt
}

cat > /tmp/check_original.py <<'PY'
import json
import os

file_path = '/home/user/output/unified.jsonl'
assert os.path.isfile(file_path), f'Expected output file {file_path} does not exist.'
expected_records = [
    {'timestamp': '2023-10-01T10:00:00Z', 'normalized_msg': 'db connection timeout', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:01:00Z', 'normalized_msg': 'db connection timeout', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:02:00Z', 'normalized_msg': 'db connection timeout', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:05:00Z', 'normalized_msg': 'disk space low on var', 'severity': 'MEDIUM'},
    {'timestamp': '2023-10-01T10:08:00Z', 'normalized_msg': 'db connection timeout', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:09:00Z', 'normalized_msg': 'db connection timeout', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:12:00Z', 'normalized_msg': 'memory leak detected in caching layer', 'severity': 'CRITICAL'},
    {'timestamp': '2023-10-01T10:15:00Z', 'normalized_msg': 'cpu usage at 99', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:16:00Z', 'normalized_msg': 'cpu usage at 99 percent', 'severity': 'HIGH'},
    {'timestamp': '2023-10-01T10:18:00Z', 'normalized_msg': 'network partition detected', 'severity': 'CRITICAL'},
    {'timestamp': '2023-10-01T10:20:00Z', 'normalized_msg': 'completely unrelated error', 'severity': 'UNKNOWN'},
]
actual_records = []
with open(file_path) as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        if line:
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise AssertionError(f'Line {line_num} is not valid JSON: {line}') from e
assert len(actual_records) == len(expected_records), (len(actual_records), len(expected_records))
for i, (actual, expected) in enumerate(zip(actual_records, expected_records), 1):
    assert actual == expected, f'Record at line {i}: expected {expected!r}, got {actual!r}'

file_path = '/home/user/output/anomalies.txt'
assert os.path.isfile(file_path), f'Expected output file {file_path} does not exist.'
with open(file_path) as f:
    lines = [line.strip() for line in f if line.strip()]
expected_anomalies = ['db connection timeout']
assert len(lines) == len(expected_anomalies), (lines, expected_anomalies)
for i, (actual, expected) in enumerate(zip(lines, expected_anomalies), 1):
    assert actual == expected, f'Anomaly at line {i}: expected {expected!r}, got {actual!r}'
PY

# Preserve and exercise all checks from the original fixed fixture.
write_original_inputs
run_submission
python3 /tmp/check_original.py

# Generate a fresh, unpredictable fixture and independently derive its answers.
python3 <<'PY'
import csv, json, re, secrets, string
from datetime import datetime
from collections import defaultdict

randword = lambda: ''.join(secrets.choice(string.ascii_lowercase) for _ in range(12))
prefix = randword()
orphan = randword()
while orphan == prefix:
    orphan = randword()

json_rows = [
    {'timestamp':'2024-02-03T00:00:00Z','msg':f'{prefix} Alpha, Beta!','severity':'FIRST'},
    {'timestamp':'2024-02-03T00:01:00Z','msg':f'{prefix} Alpha Gamma','severity':'SECOND'},
    {'timestamp':'2024-02-03T00:05:00Z','msg':'Same_Time JSON','severity':'JSON_SEV'},
    {'timestamp':'2024-02-03T01:00:00Z','msg':f'{prefix} Surge-Key!!','severity':'SURGE'},
    {'timestamp':'2024-02-03T02:00:00Z','msg':f'{prefix} Slow Event','severity':'LOW'},
    {'timestamp':'2024-02-03T03:00:00Z','msg':'Digits_42/OK','severity':'NUMBER'},
]
csv_rows = [
    ['2024-02-03T00:00:30Z', f'{prefix} alpha', ''],
    ['2024-02-03T00:02:00Z', f'{orphan} orphan', ''],
    ['2024-02-03T00:05:00Z', 'Same Time CSV', 'CSV_SEV'],
    ['2024-02-03T01:03:00Z', f'{prefix} SURGE key', ''],
    ['2024-02-03T01:09:00Z', f'{prefix} surge-key', ''],
    ['2024-02-03T01:10:00Z', f'{prefix} surge key', ''],
    ['2024-02-03T02:01:00Z', f'{prefix} slow event', ''],
    ['2024-02-03T02:05:00Z', f'{prefix} slow event', ''],
    ['2024-02-03T02:10:01Z', f'{prefix} slow event', ''],
]
with open('/home/user/data/system_a.json', 'w') as f:
    json.dump(json_rows, f)
with open('/home/user/data/system_b.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['timestamp','message','severity'])
    w.writerows(csv_rows)

def norm(s):
    return ' '.join(re.sub(r'[^A-Za-z0-9]', ' ', s.lower()).split())

def words(s):
    return set(s.split())

json_norm = [(norm(r['msg']), r['severity']) for r in json_rows]
records = []
for i, r in enumerate(json_rows):
    records.append({'timestamp':r['timestamp'], 'normalized_msg':norm(r['msg']),
                    'severity':r['severity'], '_source':0, '_index':i})
for i, (timestamp, message, severity) in enumerate(csv_rows):
    msg = norm(message)
    if severity == '':
        a = words(msg)
        best_score = 0.0
        best_severity = 'UNKNOWN'
        for candidate, candidate_severity in json_norm:
            b = words(candidate)
            score = len(a & b) / len(a | b) if a | b else 0.0
            if score > best_score:
                best_score = score
                best_severity = candidate_severity
        severity = best_severity
    records.append({'timestamp':timestamp, 'normalized_msg':msg,
                    'severity':severity, '_source':1, '_index':i})
records.sort(key=lambda r: (r['timestamp'], r['_source'], r['_index']))
expected_records = [{k:r[k] for k in ('timestamp','normalized_msg','severity')} for r in records]

groups = defaultdict(list)
for r in records:
    groups[r['normalized_msg']].append(datetime.strptime(r['timestamp'], '%Y-%m-%dT%H:%M:%SZ'))
anomalies = []
for msg, times in groups.items():
    times.sort()
    if any((times[i+3] - times[i]).total_seconds() <= 600 for i in range(len(times)-3)):
        anomalies.append(msg)
anomalies.sort()
with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump({'records':expected_records, 'anomalies':anomalies}, f)
PY

run_submission
python3 <<'PY'
import json, os
with open('/tmp/dynamic_expected.json') as f:
    expected = json.load(f)
path = '/home/user/output/unified.jsonl'
assert os.path.isfile(path)
actual = []
with open(path) as f:
    for number, line in enumerate(f, 1):
        line = line.strip()
        if line:
            value = json.loads(line)
            assert set(value) == {'timestamp','normalized_msg','severity'}, (number, value)
            actual.append(value)
assert actual == expected['records'], f'Dynamic unified output mismatch:\nexpected={expected["records"]!r}\nactual={actual!r}'
path = '/home/user/output/anomalies.txt'
assert os.path.isfile(path)
with open(path) as f:
    anomalies = [line.strip() for line in f if line.strip()]
assert anomalies == expected['anomalies'], f'Dynamic anomalies mismatch: expected={expected["anomalies"]!r}, actual={anomalies!r}'
PY

# Restore the instructed fixture and leave outputs corresponding to it.
write_original_inputs
run_submission
python3 /tmp/check_original.py

printf '1\n' > /logs/verifier/reward.txt
