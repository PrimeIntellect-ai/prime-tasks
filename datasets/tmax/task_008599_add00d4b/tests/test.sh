#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import pwd
import re
import secrets
import shutil
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def test_output_files_exist():
    """Verify that the required output files have been created."""
    assert os.path.isfile('/home/user/output/sampled_changes.csv'), "The output CSV file /home/user/output/sampled_changes.csv is missing."
    assert os.path.isfile('/home/user/output/pipeline.log'), "The output log file /home/user/output/pipeline.log is missing."


def test_csv_contents():
    """Verify the contents, formatting, and sorting of the sampled_changes.csv file."""
    csv_path = '/home/user/output/sampled_changes.csv'

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    expected_header = ['server', 'timestamp', 'config_val', 'cpu_load', 'high_load']
    assert rows[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, but got {rows[0]}."

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected exactly 4 data rows in the CSV, but found {len(data_rows)}."

    expected_data = [
        ['alpha', '2023-10-01T10:20:00Z', 'update1', '90.00', '1'],
        ['alpha', '2023-10-01T10:30:00Z', 'update2', '82.50', '1'],
        ['beta', '2023-10-01T10:05:00Z', 'start', '85.00', '1'],
        ['beta', '2023-10-01T10:15:00Z', 'error?', '85.00', '1']
    ]

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Data row {i+1} is incorrect.\nExpected: {expected}\nActual: {actual}"


def test_pipeline_log_contents():
    """Verify that the pipeline.log contains the exact expected metrics."""
    log_path = '/home/user/output/pipeline.log'

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in pipeline.log, but found {len(lines)}."

    expected_lines = [
        "Total lines read: 9",
        "Malformed lines fixed: 2",
        "Missing values imputed: 3"
    ]

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Log line {i+1} is incorrect.\nExpected: '{expected}'\nActual: '{actual}'"


def _commands_for_artifacts():
    home = Path('/home/user')
    commands = []
    seen = set()
    interpreters = {
        '.py': ['python3'],
        '.sh': ['bash'],
        '.js': ['node'],
        '.rb': ['ruby'],
        '.pl': ['perl'],
    }

    for root, dirs, files in os.walk(home):
        root_path = Path(root)
        relative_parts = root_path.relative_to(home).parts
        if len(relative_parts) >= 4:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in {'data', 'output', '__pycache__'} and not d.startswith('.')]

        for name in files:
            if name.startswith('.'):
                continue
            path = root_path / name
            try:
                if not path.is_file() or path.stat().st_size > 5_000_000:
                    continue
                prefix = path.read_bytes()[:256]
            except OSError:
                continue

            options = []
            suffix = path.suffix.lower()
            if suffix in interpreters and shutil.which(interpreters[suffix][0]):
                options.append(interpreters[suffix] + [str(path)])
            elif prefix.startswith(b'#!'):
                first = prefix.splitlines()[0].decode('utf-8', 'ignore').lower()
                if 'python' in first:
                    options.append(['python3', str(path)])
                elif 'bash' in first or '/sh' in first:
                    options.append(['bash', str(path)])
                elif os.access(path, os.X_OK):
                    options.append([str(path)])
            elif os.access(path, os.X_OK):
                options.append([str(path)])
            elif path.parent == home and b'\x00' not in prefix:
                # Also support a top-level script saved without an extension.
                options.append(['bash', str(path)])
                options.append(['python3', str(path)])

            for command in options:
                key = tuple(command)
                if key not in seen:
                    seen.add(key)
                    commands.append(command)

    def priority(command):
        text = ' '.join(command).lower()
        return (0 if any(word in text for word in ('pipeline', 'process', 'solution', 'main')) else 1, text)

    return sorted(commands, key=priority)


def _iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def test_reusable_pipeline_on_unseen_input():
    commands = _commands_for_artifacts()
    assert commands, "No runnable pipeline script was found under /home/user."

    token = secrets.token_hex(5)
    base = 1700000000 + secrets.randbelow(2_000_000)
    servers = [f'a_{token}', f'b_{token}', f'c_{token}', f'd_{token}']
    a, b, c, d = servers

    records = [
        {'timestamp': _iso(base),       'server': a, 'config_val': 'edge',     'cpu_load': None},
        {'timestamp': _iso(base + 300), 'server': a, 'config_val': 'BADMARK',  'cpu_load': 85.0},
        {'timestamp': _iso(base + 900), 'server': a, 'config_val': 'low',      'cpu_load': 70.0},
        {'timestamp': _iso(base + 10),   'server': b, 'config_val': 'start',    'cpu_load': 70.0},
        {'timestamp': _iso(base + 410),  'server': b, 'config_val': 'BADMARK2', 'cpu_load': 95.0},
        {'timestamp': _iso(base + 1010), 'server': b, 'config_val': 'tail',     'cpu_load': None},
        {'timestamp': _iso(base + 20),  'server': c, 'config_val': 'before',   'cpu_load': 70.0},
        {'timestamp': _iso(base + 620), 'server': c, 'config_val': 'middle',   'cpu_load': None},
        {'timestamp': _iso(base + 920), 'server': c, 'config_val': 'peak',     'cpu_load': 100.0},
        {'timestamp': _iso(base + 30),  'server': d, 'config_val': 'VALIDMARK','cpu_load': 80.0},
        {'timestamp': _iso(base + 330), 'server': d, 'config_val': 'tie2',     'cpu_load': 80.0},
        {'timestamp': _iso(base + 630), 'server': d, 'config_val': 'tie3',     'cpu_load': 80.0},
        {'timestamp': _iso(base + 930), 'server': d, 'config_val': 'lower',    'cpu_load': 70.0},
    ]
    secrets.SystemRandom().shuffle(records)

    fixture_lines = []
    for record in records:
        line = json.dumps(record, separators=(',', ':'))
        line = line.replace('"BADMARK"', r'"bad\u12"')
        line = line.replace('"BADMARK2"', r'"oops\uX"')
        line = line.replace('"VALIDMARK"', r'"valid\u0041"')
        fixture_lines.append(line)
    fixture = '\n'.join(fixture_lines) + '\n'

    expected = {
        (a, _iso(base)):       ('edge',   '85.00', '1'),
        (a, _iso(base + 300)): ('bad?',   '85.00', '1'),
        (b, _iso(base + 410)): ('oops?',  '95.00', '1'),
        (b, _iso(base + 1010)):('tail',   '95.00', '1'),
        (c, _iso(base + 620)): ('middle', '90.00', '1'),
        (c, _iso(base + 920)): ('peak',  '100.00', '1'),
        (d, _iso(base + 30)):  ('validA', '80.00', '0'),
        (d, _iso(base + 330)): ('tie2',   '80.00', '0'),
    }

    input_path = Path('/home/user/data/config_changes.jsonl')
    output_dir = Path('/home/user/output')
    csv_path = output_dir / 'sampled_changes.csv'
    log_path = output_dir / 'pipeline.log'
    user = pwd.getpwnam('user')
    errors = []

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    for command in commands:
        input_path.write_text(fixture, encoding='utf-8')
        output_dir.mkdir(parents=True, exist_ok=True)
        for target in (csv_path, log_path):
            try:
                target.unlink()
            except FileNotFoundError:
                pass
        os.chmod(input_path, 0o666)
        os.chmod(output_dir, 0o777)

        try:
            result = subprocess.run(
                command,
                cwd='/home/user',
                env={**os.environ, 'HOME': '/home/user'},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
                preexec_fn=demote,
            )
        except Exception as exc:
            errors.append(f"{' '.join(command)}: {exc}")
            continue

        if result.returncode != 0 or not csv_path.is_file() or not log_path.is_file():
            errors.append(f"{' '.join(command)}: exited {result.returncode} or did not create both outputs")
            continue

        try:
            with csv_path.open('r', newline='', encoding='utf-8') as handle:
                rows = list(csv.reader(handle))
            assert rows and rows[0] == ['server', 'timestamp', 'config_val', 'cpu_load', 'high_load']
            data_rows = rows[1:]
            assert len(data_rows) == 8

            actual = {}
            for row in data_rows:
                assert len(row) == 5
                server, timestamp, config_val, cpu_load, high_load = row
                assert re.fullmatch(r'-?\d+\.\d{2}', cpu_load), f"Bad cpu_load format: {cpu_load}"
                key = (server, timestamp)
                assert key not in actual
                actual[key] = (config_val, cpu_load, high_load)
            assert actual == expected

            sort_keys = [(row[0], -float(row[3])) for row in data_rows]
            assert sort_keys == sorted(sort_keys), "Rows are not sorted by server and descending cpu_load"

            with log_path.open('r', encoding='utf-8') as handle:
                log_lines = [line.strip() for line in handle.readlines() if line.strip()]
            assert log_lines == [
                'Total lines read: 13',
                'Malformed lines fixed: 2',
                'Missing values imputed: 3',
            ]
            return
        except Exception as exc:
            errors.append(f"{' '.join(command)}: output validation failed: {exc}")

    assert False, "No discovered pipeline handled unseen input correctly. " + " | ".join(errors[-8:])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
