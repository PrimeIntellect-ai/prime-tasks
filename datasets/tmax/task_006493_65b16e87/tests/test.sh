#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import json
import os
import random
import secrets
import stat
import statistics
import subprocess
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from jinja2 import Template

HOME = Path('/home/user')
LOG_DIR = HOME / 'sensor_logs'
TEMPLATE_PATH = HOME / 'report_template.j2'
REPORT_PATH = HOME / 'anomaly_report.html'


def check_original_assertions():
    """Retain the original report existence, content, and ordering checks."""
    assert REPORT_PATH.is_file(), f"Expected output file {REPORT_PATH} does not exist."
    content = REPORT_PATH.read_text(encoding='utf-8')

    expected_s2 = '2023-10-01T10:10:00Z - S2: -10.0'
    expected_s1 = '2023-10-01T10:20:00Z - S1: 45.0'
    assert expected_s2 in content, f"Anomaly for S2 ({expected_s2}) is missing from the report."
    assert expected_s1 in content, f"Anomaly for S1 ({expected_s1}) is missing from the report."

    idx_s2 = content.find(expected_s2)
    idx_s1 = content.find(expected_s1)
    assert idx_s2 < idx_s1, (
        'Anomalies are not sorted chronologically '
        '(S2 at 10:10 should appear before S1 at 10:20).'
    )


def submitted_scripts():
    scripts = []
    for path in HOME.rglob('*.py'):
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISREG(mode):
            scripts.append(path)
    assert scripts, 'No Python script was written under /home/user.'
    return sorted(scripts)


def make_case(case_number):
    nonce = secrets.token_hex(12)
    base_a = float(secrets.randbelow(40) + 20) + 0.25
    base_b = float(secrets.randbelow(30) + 60) + 0.25
    base_p = float(secrets.randbelow(20) + 100) + 0.25

    a_values = [base_a + x for x in (0.1, -0.1, 0.2, -0.2, 0.0, 0.15, 30.0)]
    b_values = [base_b + x for x in (0.0, 0.1, -0.1, 0.2, -0.2, 0.05, -28.0)]
    # With sample standard deviation, neither endpoint is an anomaly. A
    # population-standard-deviation implementation incorrectly flags the 10.
    p_values = [base_p + x for x in (0.0, 0.0, 0.0, 0.0, 3.0, 10.0)]

    start = datetime(2040 + case_number, 2 + case_number, 3, 8, 0, tzinfo=timezone.utc)
    records = []
    tick = 0

    def add(sensor, value):
        nonlocal tick
        timestamp = (start + timedelta(minutes=tick)).strftime('%Y-%m-%dT%H:%M:%SZ')
        tick += 1
        records.append({
            'timestamp': timestamp,
            'sensor_id': sensor,
            'temperature': float(value),
        })

    first, second = (('A_' + nonce, a_values), ('B_' + nonce, b_values))
    if case_number % 2 == 0:
        first, second = second, first

    for i in range(7):
        add(first[0], first[1][i])
        add(second[0], second[1][i])
        if i < len(p_values):
            add('P_' + nonce, p_values[i])
    add('SINGLE_' + nonce, base_a + 500.0)

    random.Random(nonce).shuffle(records)
    template_text = (
        'REPORT-' + nonce + '\n'
        '{% for row in anomalies %}'
        '[{{ row.timestamp }}|{{ row.sensor_id }}|{{ row.temperature }}]\n'
        '{% endfor %}'
        'END-' + nonce
    )
    return records, template_text


def expected_report(records, template_text):
    groups = defaultdict(list)
    for row in records:
        groups[row['sensor_id']].append(float(row['temperature']))

    stats = {}
    for sensor, values in groups.items():
        if len(values) >= 2:
            stats[sensor] = (statistics.mean(values), statistics.stdev(values))

    anomalies = []
    for row in records:
        sensor = row['sensor_id']
        if sensor not in stats:
            continue
        mean, std_dev = stats[sensor]
        if abs(float(row['temperature']) - mean) > 2 * std_dev:
            anomalies.append({
                'timestamp': row['timestamp'],
                'sensor_id': sensor,
                'temperature': float(row['temperature']),
            })
    anomalies.sort(key=lambda row: row['timestamp'])
    return Template(template_text).render(anomalies=anomalies)


def install_case(records, template_text):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    for child in LOG_DIR.iterdir():
        if child.is_file() or child.is_symlink():
            child.unlink()

    chunks = [records[i::4] for i in range(4)]
    for index in (0, 1):
        with (LOG_DIR / f'part_{index}.csv').open('w', newline='', encoding='utf-8') as handle:
            writer = csv.DictWriter(handle, fieldnames=['timestamp', 'sensor_id', 'temperature'])
            writer.writeheader()
            writer.writerows(chunks[index])
    for index in (2, 3):
        with (LOG_DIR / f'part_{index}.json').open('w', encoding='utf-8') as handle:
            json.dump(chunks[index], handle)

    TEMPLATE_PATH.write_text(template_text, encoding='utf-8')
    if REPORT_PATH.exists() or REPORT_PATH.is_symlink():
        REPORT_PATH.unlink()


def script_passes(script):
    for case_number in (1, 2):
        records, template_text = make_case(case_number)
        expected = expected_report(records, template_text)
        install_case(records, template_text)
        try:
            result = subprocess.run(
                ['python3', str(script)],
                cwd=str(HOME),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=25,
            )
        except (subprocess.TimeoutExpired, OSError):
            return False
        if result.returncode != 0 or not REPORT_PATH.is_file():
            return False
        try:
            actual = REPORT_PATH.read_text(encoding='utf-8')
        except (OSError, UnicodeError):
            return False
        if actual != expected:
            return False
    return True


check_original_assertions()
scripts = submitted_scripts()
assert any(script_passes(script) for script in scripts), (
    'No submitted Python script correctly read all CSV/JSON files, used sample '
    'standard deviation and the supplied Jinja2 template, emitted exactly the '
    'derived anomalies, and sorted them chronologically.'
)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
