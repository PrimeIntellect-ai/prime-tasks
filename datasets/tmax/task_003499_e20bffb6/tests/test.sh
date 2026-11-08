#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/etl_project')
SOURCE = PROJECT / 'src/main.rs'
INPUT = PROJECT / 'transactions.jsonl'
REPORT = PROJECT / 'deadlock_report.json'

ORIGINAL_INPUT = '''{"tx_id": "T1", "waits_for": "T2", "wait_time_ms": 100}
{"tx_id": "T2", "waits_for": "T3", "wait_time_ms": 200}
{"tx_id": "T3", "waits_for": "T1", "wait_time_ms": 50}
{"tx_id": "T4", "waits_for": "T5", "wait_time_ms": 300}
{"tx_id": "T5", "waits_for": "T6", "wait_time_ms": 100}
{"tx_id": "T6", "waits_for": "T4", "wait_time_ms": 400}
{"tx_id": "T7", "waits_for": "T8", "wait_time_ms": 50}
{"tx_id": "T8", "waits_for": "T9", "wait_time_ms": 20}
{"tx_id": "T10", "waits_for": "T11", "wait_time_ms": 600}
{"tx_id": "T11", "waits_for": "T10", "wait_time_ms": 400}
'''


def run_program():
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet'], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f'Rust program failed:\n{result.stdout}\n{result.stderr}'
    assert REPORT.is_file(), 'The program did not generate deadlock_report.json.'


def expected_report(rows):
    edges = {row['tx_id']: row for row in rows}
    cycles = {}
    for start in edges:
        path = []
        positions = {}
        current = start
        while current in edges and current not in positions:
            positions[current] = len(path)
            path.append(current)
            current = edges[current]['waits_for']
        if current in positions:
            members = path[positions[current]:]
            key = tuple(sorted(members))
            cycles[key] = {
                'cycle': list(key),
                'total_wait_ms': sum(edges[tx]['wait_time_ms'] for tx in members),
                'max_wait_tx': max(members, key=lambda tx: edges[tx]['wait_time_ms']),
            }
    return sorted(cycles.values(), key=lambda item: (-item['total_wait_ms'], item['cycle'][0]))


def write_rows(rows):
    INPUT.write_text(''.join(json.dumps(row) + '\n' for row in rows))


@pytest.fixture(scope='module', autouse=True)
def compile_and_run_original_fixture():
    old_input = INPUT.read_bytes() if INPUT.exists() else None
    old_report = REPORT.read_bytes() if REPORT.exists() and REPORT.is_file() else None
    try:
        assert SOURCE.exists(), 'src/main.rs was not found.'
        assert stat.S_ISREG(SOURCE.lstat().st_mode), 'src/main.rs must be a regular file.'
        source_text = SOURCE.read_text()
        assert source_text.strip() != 'fn main() {\n    println!("Hello, world!");\n}', 'src/main.rs is still the starter program.'

        clean = subprocess.run(
            ['cargo', 'clean'], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert clean.returncode == 0, f'cargo clean failed:\n{clean.stderr}'
        build = subprocess.run(
            ['cargo', 'build'], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert build.returncode == 0, f'Cargo project did not compile:\n{build.stdout}\n{build.stderr}'

        INPUT.write_text(ORIGINAL_INPUT)
        run_program()
        yield
    finally:
        if old_input is None:
            if INPUT.exists():
                INPUT.unlink()
        else:
            INPUT.write_bytes(old_input)
        if old_report is None:
            if REPORT.exists() or REPORT.is_symlink():
                REPORT.unlink()
        else:
            REPORT.write_bytes(old_report)


def test_deadlock_report_exists():
    assert os.path.isfile('/home/user/etl_project/deadlock_report.json'), "The deadlock_report.json file was not found in /home/user/etl_project."


def test_deadlock_report_content():
    with open('/home/user/etl_project/deadlock_report.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "deadlock_report.json is not a valid JSON file."

    assert isinstance(data, list), "The root of the JSON file must be an array."
    assert len(data) == 3, f"Expected 3 cycles in the report, found {len(data)}."

    expected_data = [
        {
            "cycle": ["T10", "T11"],
            "max_wait_tx": "T10",
            "total_wait_ms": 1000
        },
        {
            "cycle": ["T4", "T5", "T6"],
            "max_wait_tx": "T6",
            "total_wait_ms": 800
        },
        {
            "cycle": ["T1", "T2", "T3"],
            "max_wait_tx": "T2",
            "total_wait_ms": 350
        }
    ]

    for i, expected_cycle in enumerate(expected_data):
        actual_cycle = data[i]
        assert "cycle" in actual_cycle, f"Missing 'cycle' key in item {i}."
        assert "max_wait_tx" in actual_cycle, f"Missing 'max_wait_tx' key in item {i}."
        assert "total_wait_ms" in actual_cycle, f"Missing 'total_wait_ms' key in item {i}."

        assert isinstance(actual_cycle["cycle"], list), f"'cycle' should be a list in item {i}."
        assert sorted(actual_cycle["cycle"]) == actual_cycle["cycle"], f"'cycle' array is not sorted alphabetically in item {i}."
        assert actual_cycle["cycle"] == expected_cycle["cycle"], f"Expected cycle {expected_cycle['cycle']}, got {actual_cycle['cycle']} at index {i}."

        assert actual_cycle["max_wait_tx"] == expected_cycle["max_wait_tx"], f"Expected max_wait_tx {expected_cycle['max_wait_tx']}, got {actual_cycle['max_wait_tx']} at index {i}."
        assert actual_cycle["total_wait_ms"] == expected_cycle["total_wait_ms"], f"Expected total_wait_ms {expected_cycle['total_wait_ms']}, got {actual_cycle['total_wait_ms']} at index {i}."


def test_program_processes_changed_inputs():
    rng = random.Random(secrets.randbits(128))
    for trial in range(3):
        rows = []
        cycle_count = rng.randint(2, 5)
        for cycle_index in range(cycle_count):
            length = rng.randint(2, 6)
            token = secrets.token_hex(5)
            members = [f'R{trial}_{cycle_index}_{i}_{token}' for i in range(length)]
            waits = rng.sample(range(10, 5000), length)
            for i, tx in enumerate(members):
                rows.append({
                    'tx_id': tx,
                    'waits_for': members[(i + 1) % length],
                    'wait_time_ms': waits[i],
                })

        for noise_index in range(rng.randint(2, 6)):
            token = secrets.token_hex(5)
            rows.append({
                'tx_id': f'N{trial}_{noise_index}_{token}',
                'waits_for': f'END_{trial}_{noise_index}_{token}',
                'wait_time_ms': rng.randint(1, 5000),
            })

        rng.shuffle(rows)
        expected = expected_report(rows)
        write_rows(rows)
        run_program()
        try:
            actual = json.loads(REPORT.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f'Generated report is not valid JSON: {exc}')
        assert actual == expected, f'Incorrect report for changed input on trial {trial}. Expected {expected}, got {actual}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
