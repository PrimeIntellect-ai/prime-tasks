#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
SERVERS = HOME / 'servers.csv'
MODEL = HOME / 'model_spec.txt'
PREDICTIONS = HOME / 'predictions.csv'

ORIGINAL_SERVERS = SERVERS.read_bytes()
ORIGINAL_MODEL = MODEL.read_bytes()
ORIGINAL_PREDICTIONS = PREDICTIONS.read_bytes() if PREDICTIONS.is_file() else None


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_01_predictions_csv_exists_and_correct():
    file_path = '/home/user/predictions.csv'
    assert os.path.isfile(file_path), f'Output file {file_path} is missing. The script did not generate it.'

    expected_lines = [
        'ServerID,RiskScore,Alert',
        'srv_004,174.19,1',
        'srv_005,81.78,1',
        'srv_001,48.28,0',
        'srv_002,45.19,0',
        'srv_003,1.60,0'
    ]

    actual_lines = read_nonempty_lines(file_path)
    assert actual_lines == expected_lines, (
        f'The content of {file_path} does not match the expected output. '
        f"Expected:\n{chr(10).join(expected_lines)}\n\nActual:\n{chr(10).join(actual_lines)}"
    )


def find_shell_artifacts():
    artifacts = []
    excluded = {SERVERS.resolve(), MODEL.resolve(), PREDICTIONS.resolve()}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for name in files:
            if name.startswith('.'):
                continue
            path = Path(root) / name
            try:
                resolved = path.resolve()
                mode = path.stat().st_mode
                data = path.read_bytes()
            except (OSError, ValueError):
                continue
            if resolved in excluded or not stat.S_ISREG(mode) or len(data) > 1024 * 1024 or b'\0' in data:
                continue
            artifacts.append(path)
    return artifacts


def make_case(rng):
    while True:
        bias = rng.randint(-300, 100) / 10.0
        threshold = rng.randint(250, 1300) / 10.0
        weights = {
            'CPU_Load': rng.randint(15, 175) / 100.0,
            'Mem_Used_MB': rng.randint(1, 45) / 10000.0,
            'Disk_IOPS': rng.randint(1, 30) / 100.0,
        }
        os_weights = {
            'Linux': rng.randint(-50, 200) / 10.0,
            'Windows': rng.randint(-50, 200) / 10.0,
            'BSD': rng.randint(-50, 200) / 10.0,
        }
        tag = rng.randrange(100000, 999999)
        raw_rows = [
            [f'node_{tag}_a', 'Linux', f'{rng.randint(1, 990) / 10:.1f}', str(rng.randint(512, 24000)), str(rng.randint(1, 1800))],
            [f'node_{tag}_b', 'Windows', '', str(rng.randint(512, 24000)), str(rng.randint(1, 1800))],
            [f'node_{tag}_c', 'BSD', f'{rng.randint(1, 990) / 10:.1f}', '', str(rng.randint(1, 1800))],
            [f'node_{tag}_d', 'Linux', f'{rng.randint(1, 990) / 10:.1f}', str(rng.randint(512, 24000)), ''],
            [f'node_{tag}_e', 'Windows', '', '', str(rng.randint(1, 1800))],
            [f'node_{tag}_f', 'BSD', f'{rng.randint(1, 990) / 10:.1f}', str(rng.randint(512, 24000)), str(rng.randint(1, 1800))],
        ]

        scored = []
        safe = True
        for row in raw_rows:
            cpu = float(row[2]) if row[2] else 0.0
            mem = float(row[3]) if row[3] else 0.0
            disk = float(row[4]) if row[4] else 0.0
            score = os_weights[row[1]] + cpu * weights['CPU_Load'] + mem * weights['Mem_Used_MB'] + disk * weights['Disk_IOPS'] + bias
            fraction = (abs(score) * 100.0) % 1.0
            if abs(fraction - 0.5) < 0.03:
                safe = False
                break
            scored.append((score, row[0]))
        if not safe:
            continue
        ordered_scores = sorted((score for score, _ in scored), reverse=True)
        if any(abs(a - b) < 0.05 for a, b in zip(ordered_scores, ordered_scores[1:])):
            continue

        servers_text = 'ServerID,OS,CPU_Load,Mem_Used_MB,Disk_IOPS\n' + ''.join(','.join(row) + '\n' for row in raw_rows)
        model_text = f'''MODEL_CONFIG_v1.0
BIAS: {bias:.1f}
ALERT_THRESHOLD: {threshold:.1f}

WEIGHTS_CONTINUOUS:
CPU_Load: {weights['CPU_Load']:.2f}
Mem_Used_MB: {weights['Mem_Used_MB']:.4f}
Disk_IOPS: {weights['Disk_IOPS']:.2f}

WEIGHTS_CATEGORICAL_OS:
Linux: {os_weights['Linux']:.1f}
Windows: {os_weights['Windows']:.1f}
BSD: {os_weights['BSD']:.1f}
'''
        scored.sort(key=lambda item: item[0], reverse=True)
        expected = ['ServerID,RiskScore,Alert']
        expected.extend(f'{server_id},{score:.2f},{1 if score >= threshold else 0}' for score, server_id in scored)
        return servers_text, model_text, expected


def run_artifact(path, cases):
    for servers_text, model_text, expected in cases:
        SERVERS.write_text(servers_text)
        MODEL.write_text(model_text)
        os.chmod(SERVERS, 0o777)
        os.chmod(MODEL, 0o777)
        try:
            PREDICTIONS.unlink()
        except FileNotFoundError:
            pass

        try:
            completed = subprocess.run(
                ['runuser', '-u', 'user', '--', 'timeout', '12', '/bin/bash', str(path)],
                cwd=str(HOME), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=15, check=False
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        if completed.returncode != 0 or not PREDICTIONS.exists() or PREDICTIONS.is_symlink() or not PREDICTIONS.is_file():
            return False
        try:
            actual = read_nonempty_lines(PREDICTIONS)
        except (OSError, UnicodeError):
            return False
        if actual != expected:
            return False
    return True


def test_02_solution_is_programmatic_and_reads_both_inputs():
    artifacts = find_shell_artifacts()
    rng = random.SystemRandom()
    cases = [make_case(rng), make_case(rng)]
    try:
        passing = [str(path) for path in artifacts if run_artifact(path, cases)]
        assert passing, (
            'No submitted shell artifact regenerated predictions.csv for dynamically generated '
            'server data and model specifications. The solution must parse servers.csv and '
            'model_spec.txt rather than writing the fixed expected rows.'
        )
    finally:
        SERVERS.write_bytes(ORIGINAL_SERVERS)
        MODEL.write_bytes(ORIGINAL_MODEL)
        os.chmod(SERVERS, 0o777)
        os.chmod(MODEL, 0o777)
        try:
            PREDICTIONS.unlink()
        except FileNotFoundError:
            pass
        if ORIGINAL_PREDICTIONS is not None:
            PREDICTIONS.write_bytes(ORIGINAL_PREDICTIONS)
            os.chmod(PREDICTIONS, 0o666)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
