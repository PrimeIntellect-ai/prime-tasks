#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/process_logs.py')
LOG = Path('/home/user/pipeline.log')
REPORTS = Path('/home/user/reports')
DATA = Path('/home/user/data/logs')
SOURCES = [
    DATA / 'srv01_metrics.csv',
    DATA / 'srv02_metrics.json',
    DATA / 'srv03_metrics.jsonl',
]

ORIGINAL_EXPECTED = {
    'SRV-01': ['Server: SRV-01', 'Total Records: 6', 'Max Temp: 50.00', 'Average Temp: 45.00'],
    'SRV-02': ['Server: SRV-02', 'Total Records: 4', 'Max Temp: 66.00', 'Average Temp: 63.00'],
    'SRV-03': ['Server: SRV-03', 'Total Records: 3', 'Max Temp: 40.00', 'Average Temp: 35.00'],
}


def clean_outputs():
    REPORTS.mkdir(parents=True, exist_ok=True)
    for child in REPORTS.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()
    if LOG.exists() or LOG.is_symlink():
        LOG.unlink()


def run_pipeline():
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'process_logs.py exited with {result.returncode}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )


def assert_original_current_checks():
    log_path = '/home/user/pipeline.log'
    assert os.path.isfile(log_path), f'Log file {log_path} is missing.'
    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        '[INFO] Successfully processed SRV-01 with 6 records.',
        '[INFO] Successfully processed SRV-02 with 4 records.',
        '[INFO] Successfully processed SRV-03 with 3 records.'
    ]
    for expected in expected_lines:
        assert expected in lines, f"Expected log line '{expected}' not found in {log_path}."
    indices = [lines.index(expected) for expected in expected_lines]
    assert indices == sorted(indices), 'Log lines are not in alphabetical order of server_id.'

    checks = {
        'SRV-01': ('6', '50.00', '45.00'),
        'SRV-02': ('4', '66.00', '63.00'),
        'SRV-03': ('3', '40.00', '35.00'),
    }
    for server, (count, maximum, average) in checks.items():
        report_path = f'/home/user/reports/{server}_report.txt'
        assert os.path.isfile(report_path), f'Report file {report_path} is missing.'
        with open(report_path, 'r') as f:
            content = f.read()
        assert f'Server: {server}' in content, f'Missing or incorrect Server line in {server} report.'
        assert f'Total Records: {count}' in content, f'Missing or incorrect Total Records line in {server} report.'
        assert f'Max Temp: {maximum}' in content, f'Missing or incorrect Max Temp line in {server} report.'
        assert f'Average Temp: {average}' in content, f'Missing or incorrect Average Temp line in {server} report.'


def assert_exact_outputs(expected):
    expected_servers = sorted(expected)
    expected_logs = [
        f'[INFO] Successfully processed {server} with {len(expected[server])} records.'
        for server in expected_servers
    ]
    assert LOG.is_file(), f'Log file {LOG} is missing.'
    assert LOG.read_text().splitlines() == expected_logs, 'Pipeline log must contain exactly one correctly ordered line per server.'

    actual_reports = sorted(p.name for p in REPORTS.glob('*_report.txt'))
    wanted_reports = sorted(f'{server}_report.txt' for server in expected_servers)
    assert actual_reports == wanted_reports, 'The reports directory does not contain exactly the expected report files.'

    for server in expected_servers:
        values = expected[server]
        wanted = [
            f'Server: {server}',
            f'Total Records: {len(values)}',
            f'Max Temp: {max(values):.2f}',
            f'Average Temp: {sum(values) / len(values):.2f}',
        ]
        path = REPORTS / f'{server}_report.txt'
        assert path.is_file(), f'Report file {path} is missing.'
        assert path.read_text().splitlines() == wanted, f'{path} does not exactly match the required template.'


def interpolate(records):
    ordered = sorted(records, key=lambda r: int(r['timestamp']))
    values = [None if r['cpu_temp'] is None else float(r['cpu_temp']) for r in ordered]
    for i, value in enumerate(values):
        if value is not None:
            continue
        left = i - 1
        while values[left] is None:
            left -= 1
        right = i + 1
        while values[right] is None:
            right += 1
        values[i] = values[left] + (values[right] - values[left]) * (i - left) / (right - left)
    return values


def write_dynamic_sources():
    token = secrets.token_hex(4).upper()
    servers = [f'ALPHA-{token}', f'MIDDLE-{token}', f'ZULU-{token}']
    start = 1700000000 + secrets.randbelow(100000)
    temperatures = [20 + secrets.randbelow(11), 45 + secrets.randbelow(11), 70 + secrets.randbelow(11)]
    patterns = [
        [0, None, None, 6],
        [0, None, 10],
        [0, None, 4, None, None, 10],
    ]

    all_records = []
    per_server = {}
    buckets = [[], [], []]
    for server_index, (server, base_temp, pattern) in enumerate(zip(servers, temperatures, patterns)):
        records = []
        for i, offset in enumerate(pattern):
            records.append({
                'timestamp': start + server_index * 1000 + i * 10,
                'server_id': server,
                'cpu_temp': None if offset is None else float(base_temp + offset),
            })
        per_server[server] = records
        all_records.extend(records)
        for i, record in enumerate(records):
            buckets[(i + server_index) % 3].append(record)

    rng = random.SystemRandom()
    for bucket in buckets:
        rng.shuffle(bucket)

    with SOURCES[0].open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'server_id', 'cpu_temp'])
        for record in buckets[0]:
            writer.writerow([
                record['timestamp'], record['server_id'],
                '' if record['cpu_temp'] is None else record['cpu_temp'],
            ])
    SOURCES[1].write_text(json.dumps(buckets[1]))
    with SOURCES[2].open('w') as f:
        for record in buckets[2]:
            f.write(json.dumps(record) + '\n')

    return {server: interpolate(records) for server, records in per_server.items()}


def test_pipeline_artifact_and_outputs():
    assert SCRIPT.exists(), f'{SCRIPT} is missing.'
    mode = SCRIPT.lstat().st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} must be a regular Python source file, not a symlink or other file type.'

    backups = {path: path.read_bytes() for path in SOURCES}
    try:
        clean_outputs()
        run_pipeline()
        assert_original_current_checks()
        assert_exact_outputs({
            server: {
                'SRV-01': [40, 42, 44, 46, 48, 50],
                'SRV-02': [60, 62, 64, 66],
                'SRV-03': [30, 35, 40],
            }[server]
            for server in ORIGINAL_EXPECTED
        })

        expected_dynamic = write_dynamic_sources()
        clean_outputs()
        run_pipeline()
        assert_exact_outputs(expected_dynamic)
    finally:
        for path, content in backups.items():
            path.write_bytes(content)
        clean_outputs()
        run_pipeline()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
