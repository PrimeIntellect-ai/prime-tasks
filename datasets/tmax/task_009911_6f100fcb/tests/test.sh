#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/process_logs.sh')
RAW = Path('/home/user/raw_app.log')
ANOMALIES = Path('/home/user/anomalies.csv')
SAMPLES = Path('/home/user/anomalous_samples.log')

ORIGINAL_LOG = '''[2023-10-24 10:00:05] IP=192.168.1.50 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:00:25] IP=192.168.1.51 STATUS=200 TIME=150 MSG=OK
[2023-10-24 10:00:55] IP=192.168.1.52 STATUS=200 TIME=120 MSG=Slow DB connection
[2023-10-24 10:01:15] IP=10.0.0.5 STATUS=500 TIME=800 MSG=Exception occurred:
java.lang.NullPointerException
  at com.app.Main(Main.java:25)
  at com.app.Runner(Runner.java:10)
[2023-10-24 10:01:45] IP=10.0.0.6 STATUS=500 TIME=600 MSG=Database timeout
[2023-10-24 10:02:10] IP=192.168.2.10 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:02:30] IP=192.168.2.11 STATUS=200 TIME=200 MSG=OK
[2023-10-24 10:02:45] IP=192.168.2.12 STATUS=200 TIME=150 MSG=OK
[2023-10-24 10:02:59] IP=192.168.2.13 STATUS=200 TIME=100 MSG=OK
[2023-10-24 10:03:05] IP=172.16.0.2 STATUS=503 TIME=400 MSG=Service Unavailable
[2023-10-24 10:03:35] IP=172.16.0.3 STATUS=503 TIME=600 MSG=Service Unavailable
[2023-10-24 10:03:50] IP=172.16.0.4 STATUS=500 TIME=550 MSG=Connection reset
by peer
[2023-10-24 10:04:10] IP=8.8.8.8 STATUS=200 TIME=50 MSG=OK
'''


def run_script():
    for output in (ANOMALIES, SAMPLES):
        try:
            output.unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f'Script execution failed with return code {result.returncode}. '
        f'stderr: {result.stderr}'
    )
    assert ANOMALIES.is_file(), f'Output file {ANOMALIES} was not created.'
    assert SAMPLES.is_file(), f'Output file {SAMPLES} was not created.'


@pytest.fixture(scope='session', autouse=True)
def run_original_fixture():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'

    source = SCRIPT.read_text(errors='strict')
    first_line = source.splitlines()[0] if source.splitlines() else ''
    assert re.fullmatch(r'#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s+.*)?', first_line), \
        'process_logs.sh must be a Bash script with a Bash shebang.'
    forbidden = re.compile(
        r'(?m)(?:^|[;&|]\s*)(?:sudo\s+)?(?:/usr/bin/|/bin/)?(?:python\d*|perl|ruby)(?:\s|$)'
    )
    assert not forbidden.search(source), 'Python, Perl, and Ruby may not be used by the pipeline.'

    RAW.write_text(ORIGINAL_LOG)
    run_script()


def test_anomalies_csv():
    with ANOMALIES.open('r') as f:
        rows = list(csv.reader(f))

    expected_rows = [
        ['Minute', 'AvgTime'],
        ['2023-10-24 10:01', '700'],
        ['2023-10-24 10:03', '516']
    ]
    assert rows == expected_rows, f'Content of {ANOMALIES} is incorrect. Expected {expected_rows}, got {rows}.'


def test_anomalous_samples_log():
    lines = [line.strip() for line in SAMPLES.read_text().splitlines() if line.strip()]
    expected_lines = [
        '2023-10-24 10:01:15,10.0.0.xxx,500,800',
        '2023-10-24 10:01:45,10.0.0.xxx,500,600',
        '2023-10-24 10:03:05,172.16.0.xxx,503,400',
        '2023-10-24 10:03:35,172.16.0.xxx,503,600',
        '2023-10-24 10:03:50,172.16.0.xxx,500,550'
    ]
    assert lines == expected_lines, f'Content of {SAMPLES} is incorrect. Expected {expected_lines}, got {lines}.'


def write_generated_case(specs, rng):
    year = rng.randrange(2025, 2038)
    month = rng.randrange(1, 13)
    day = rng.randrange(1, 25)
    hour = rng.randrange(0, 22)
    start_minute = rng.randrange(0, 45)
    base = datetime(year, month, day, hour, start_minute)

    raw_lines = []
    events = []
    for minute_offset, times in specs:
        for index, response_time in enumerate(times):
            stamp = base + timedelta(minutes=minute_offset, seconds=5 + index * 11)
            ip = '.'.join(str(x) for x in (
                rng.randrange(1, 224), rng.randrange(0, 256),
                rng.randrange(0, 256), rng.randrange(1, 255)
            ))
            status = rng.choice([200, 201, 400, 404, 500, 503])
            raw_lines.append(
                f'[{stamp:%Y-%m-%d %H:%M:%S}] IP={ip} STATUS={status} '
                f'TIME={response_time} MSG=generated message {rng.randrange(100000, 999999)}'
            )
            if (minute_offset + index) % 2 == 0:
                raw_lines.extend([
                    'continuation with IP=255.255.255.255 STATUS=999 TIME=99999',
                    '  at generated.Stack(trace.java:42)'
                ])
            events.append((stamp, ip, status, response_time))

    RAW.write_text('\n'.join(raw_lines) + '\n')
    return events


def verify_generated_outputs(events):
    grouped = {}
    for stamp, ip, status, response_time in events:
        minute = stamp.strftime('%Y-%m-%d %H:%M')
        grouped.setdefault(minute, []).append(response_time)
    expected_anomalies = {
        minute: sum(times) // len(times)
        for minute, times in grouped.items()
        if sum(times) // len(times) > 500
    }

    with ANOMALIES.open(newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['Minute', 'AvgTime']
    assert len(rows) == len(expected_anomalies) + 1, f'Unexpected anomaly rows: {rows}'
    actual_anomalies = {}
    for row in rows[1:]:
        assert len(row) == 2, f'Malformed anomaly row: {row}'
        assert row[0] not in actual_anomalies, f'Duplicate anomaly minute: {row[0]}'
        actual_anomalies[row[0]] = int(row[1])
    assert actual_anomalies == expected_anomalies

    expected_samples = []
    for stamp, ip, status, response_time in events:
        minute = stamp.strftime('%Y-%m-%d %H:%M')
        if minute in expected_anomalies:
            masked = ip.rsplit('.', 1)[0] + '.xxx'
            expected_samples.append(f'{stamp:%Y-%m-%d %H:%M:%S},{masked},{status},{response_time}')
    actual_samples = [line.strip() for line in SAMPLES.read_text().splitlines() if line.strip()]
    assert Counter(actual_samples) == Counter(expected_samples)
    assert len(actual_samples) == len(expected_samples)


def test_generated_unpredictable_fixtures():
    rng = secrets.SystemRandom()

    # Includes floor rounding, an average exactly at the threshold, several
    # anomalous minutes, randomized PII, and misleading multiline continuations.
    case_one = [
        (0, [499, 501]),
        (1, [rng.randrange(120, 300), rng.randrange(300, 480)]),
        (2, [rng.randrange(700, 900), rng.randrange(550, 700)]),
        (3, [501, 502]),
        (5, [rng.randrange(50, 250)])
    ]
    events = write_generated_case(case_one, rng)
    run_script()
    verify_generated_outputs(events)

    # Also require stale anomaly data to be cleared when no minute is anomalous.
    case_two = [
        (0, [500]),
        (1, [rng.randrange(1, 400), rng.randrange(1, 500)]),
        (4, [100, 200, 300])
    ]
    events = write_generated_case(case_two, rng)
    run_script()
    verify_generated_outputs(events)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
