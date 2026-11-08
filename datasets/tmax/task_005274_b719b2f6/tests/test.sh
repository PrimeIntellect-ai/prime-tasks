#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import unicodedata

ORIGINAL_RAW_LOGS = r'''{"timestamp": 1600000000, "service": "auth", "message": "User logged in \u0065\u0301", "metrics": {"response_time_ms": 120.0, "cpu_load": 0.45}}
{"timestamp": 1600000010, "service": "auth", "message": "Token check", "metrics": {"response_time_ms": null, "cpu_load": 0.50}}
{"timestamp": 1600000020, "service": "auth", "message": "Password mismatch \u00e9", "metrics": {"response_time_ms": 200.0, "cpu_load": 0.60}}
{"timestamp": 1600000005, "service": "db", "message": "Query OK \u006f\u0308", "metrics": {"response_time_ms": 45.0, "cpu_load": 0.80}}
{"timestamp": 1600000015, "service": "db", "message": "[FATAL] Deadlock detected \u00f6", "metrics": {"response_time_ms": 5000.0, "cpu_load": null}}
{"timestamp": 1600000035, "service": "db", "message": "Restarting \u00f6", "metrics": {"response_time_ms": 20.0, "cpu_load": 0.95}}
{"timestamp": 1600000045, "service": "auth", "message": "[FATAL] DB connection lost \u00e9", "metrics": {"response_time_ms": 3000.0, "cpu_load": 0.99}}
{invalid_json_here]
{"timestamp": 1600000050, "message": "Missing service field", "metrics": {"response_time_ms": 10.0, "cpu_load": 0.1}}
'''

def compute_expected_report():
    raw_path = "/home/user/raw_logs.jsonl"
    if not os.path.exists(raw_path):
        return []

    valid_logs = []
    with open(raw_path, 'r', encoding='utf-8') as f:
        for line in f:
            try:
                data = json.loads(line)
                if 'timestamp' not in data or 'service' not in data:
                    continue
                data['message'] = unicodedata.normalize('NFC', data.get('message', ''))
                valid_logs.append(data)
            except json.JSONDecodeError:
                continue

    services = {}
    for log in valid_logs:
        services.setdefault(log['service'], []).append(log)

    for srv, logs in services.items():
        logs.sort(key=lambda x: x['timestamp'])

        for metric in ['response_time_ms', 'cpu_load']:
            valid_pts = [(i, l['timestamp'], l['metrics'].get(metric))
                         for i, l in enumerate(logs)
                         if l.get('metrics', {}).get(metric) is not None]

            for i, l in enumerate(logs):
                if l.get('metrics', {}).get(metric) is None:
                    prior = [p for p in valid_pts if p[0] < i]
                    subseq = [p for p in valid_pts if p[0] > i]

                    if not prior and not subseq:
                        val = 0.0
                    elif not prior:
                        val = subseq[0][2]
                    elif not subseq:
                        val = prior[-1][2]
                    else:
                        t1, v1 = prior[-1][1], prior[-1][2]
                        t2, v2 = subseq[0][1], subseq[0][2]
                        t = l['timestamp']
                        val = v1 + (v2 - v1) * (t - t1) / (t2 - t1)

                    if 'metrics' not in l:
                        l['metrics'] = {}
                    l['metrics'][metric] = val

    all_logs = []
    for srv, logs in services.items():
        for l in logs:
            rt = l['metrics']['response_time_ms']
            cpu = l['metrics']['cpu_load']
            score = (rt * 0.5) + (cpu * 100)
            if '[FATAL]' in l['message']:
                score += 1000
            l['score'] = score
            all_logs.append(l)

    all_logs.sort(key=lambda x: x['score'], reverse=True)
    top_3 = all_logs[:3]

    expected_lines = []
    for l in top_3:
        expected_lines.append(f"[{l['timestamp']}] Service {l['service']} score: {l['score']:.2f} | Msg: {l['message']}")

    return expected_lines

def test_anomaly_report_exists_and_correct():
    raw_path = "/home/user/raw_logs.jsonl"
    assert os.path.exists(raw_path), f"The input file {raw_path} is missing."
    with open(raw_path, 'r', encoding='utf-8') as f:
        actual_raw_logs = f.read()
    assert actual_raw_logs == ORIGINAL_RAW_LOGS, "The original raw_logs.jsonl fixture was modified."

    report_path = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_path), f"The report file {report_path} was not created."

    expected_lines = compute_expected_report()
    assert len(expected_lines) > 0, "Could not compute expected lines, check if raw_logs.jsonl exists and is valid."
    assert len(expected_lines) == 3, f"Expected the fixture to produce 3 top anomalies, but computed {len(expected_lines)}."

    with open(report_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
