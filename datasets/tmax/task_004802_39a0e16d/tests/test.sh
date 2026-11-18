#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/aggregate.sh')
OUTPUT = Path('/home/user/fixed_epoch_averages.txt')
LOG_DIR = Path('/home/user/logs')


def test_fixed_averages_file_exists():
    assert os.path.isfile('/home/user/fixed_epoch_averages.txt'), "The output file /home/user/fixed_epoch_averages.txt is missing."


def test_fixed_averages_content():
    with open('/home/user/fixed_epoch_averages.txt', 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 100, f"Expected 100 lines in fixed_epoch_averages.txt, got {len(lines)}."

    loss = 1.0
    for i, line in enumerate(lines):
        epoch = i + 1
        loss *= 0.95
        expected_str = f"Epoch {epoch}: {loss:.6f}"
        assert line == expected_str, f"Mismatch at epoch {epoch}: expected '{expected_str}', got '{line}'"


def test_aggregate_script_exists_and_executable():
    script_path = '/home/user/aggregate.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def expected_from_logs():
    losses = {epoch: [] for epoch in range(1, 101)}
    pattern = re.compile(r'Epoch:\s*(\d+)\s*\|\s*Loss:\s*([^|\s]+)')

    for node in range(1, 6):
        path = LOG_DIR / f'node_{node}.log'
        assert path.is_file(), f"Missing input log {path}"
        for line in path.read_text().splitlines():
            match = pattern.search(line)
            assert match, f"Could not parse log line: {line!r}"
            epoch = int(match.group(1))
            assert 1 <= epoch <= 100, f"Invalid epoch {epoch} in {path}"
            token = match.group(2).replace(',', '.')
            losses[epoch].append(float(token))

    result = []
    for epoch in range(1, 101):
        values = losses[epoch]
        assert len(values) == 5, f"Expected five losses for epoch {epoch}, got {len(values)}"
        result.append(f"Epoch {epoch}: {sum(values) / len(values):.6f}")
    return result


def run_aggregate():
    completed = subprocess.run(
        [str(SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert completed.returncode == 0, (
        f"aggregate.sh exited with {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout.splitlines()


def replace_loss(path, epoch, new_value):
    text = path.read_text()
    pattern = re.compile(rf'(Epoch:\s*{epoch}\s*\|\s*Loss:\s*)[^|\s]+')
    updated, count = pattern.subn(rf'\g<1>{new_value}', text)
    assert count == 1, f"Could not uniquely update epoch {epoch} in {path}"
    path.write_text(updated)


def test_script_computes_output_from_logs_dynamically():
    expected = expected_from_logs()
    actual = run_aggregate()
    assert actual == expected, "aggregate.sh output is not the mean derived from all five logs"
    assert actual == OUTPUT.read_text().splitlines(), (
        "fixed_epoch_averages.txt does not match the output of aggregate.sh"
    )

    log_paths = [LOG_DIR / f'node_{node}.log' for node in range(1, 6)]
    originals = {path: path.read_bytes() for path in log_paths}
    try:
        epoch_a = 10 + secrets.randbelow(31)
        epoch_b = 60 + secrets.randbelow(31)
        decimal_value = f"0.{100000 + secrets.randbelow(800000):06d}"
        coefficient = 100000 + secrets.randbelow(800000)
        scientific_value = f"{str(coefficient)[0]},{str(coefficient)[1:]}e-02"

        replace_loss(LOG_DIR / 'node_2.log', epoch_a, decimal_value)
        replace_loss(LOG_DIR / 'node_4.log', epoch_b, scientific_value)

        mutated_expected = expected_from_logs()
        mutated_actual = run_aggregate()
        assert mutated_actual == mutated_expected, (
            "aggregate.sh did not dynamically recompute averages after log values changed"
        )
    finally:
        for path, content in originals.items():
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
