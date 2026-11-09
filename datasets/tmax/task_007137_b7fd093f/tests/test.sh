#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import struct
import subprocess
import tempfile
import pytest

SRC_DIR = '/home/user/src'
RECOVER = os.path.join(SRC_DIR, 'recover')


def test_crash_time_extracted():
    crash_time_file = '/home/user/crash_time.txt'
    assert os.path.exists(crash_time_file), f"File {crash_time_file} does not exist."

    with open(crash_time_file, 'r') as f:
        content = f.read().strip()

    assert content == "1698394514", f"Expected crash time '1698394514', but got '{content}'."

    # Independently derive the final crash timestamp from the supplied logs.
    crashes = []
    for path in ('/home/user/logs/collector.log', '/home/user/logs/processor.log'):
        with open(path, 'r') as f:
            for line in f:
                if 'FATAL_CRASH' not in line:
                    continue
                line = line.strip()
                iso = re.match(r'^\[([^]]+)\]', line)
                epoch = re.match(r'^(\d+)', line)
                if iso:
                    raw = iso.group(1)
                    parsed = datetime.datetime.fromisoformat(raw.replace('Z', '+00:00')).timestamp()
                elif epoch:
                    raw = epoch.group(1)
                    parsed = int(raw)
                else:
                    pytest.fail(f"Could not parse timestamp from crash log line: {line}")
                crashes.append((parsed, raw))

    assert crashes, "No FATAL_CRASH event was found in the logs."
    assert content == max(crashes, key=lambda item: item[0])[1]


def test_recovered_data_csv():
    csv_file = '/home/user/recovered_data.csv'
    assert os.path.exists(csv_file), f"File {csv_file} does not exist."

    with open(csv_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 5, "Recovered CSV file does not contain enough lines."
    assert lines[0] == "timestamp,sensor_id,temp_f", "CSV header is incorrect."

    expected_data = [
        "1698394400,1,68.00",
        "1698394410,2,77.00",
        "1698394420,1,72.50",
        "1698394430,3,86.00"
    ]

    for i, expected in enumerate(expected_data):
        assert lines[i+1] == expected, f"Line {i+2} in CSV is incorrect. Expected '{expected}', got '{lines[i+1]}'."


def test_utils_c_fixed():
    utils_c = '/home/user/src/utils.c'
    assert os.path.exists(utils_c), f"File {utils_c} does not exist."

    with open(utils_c, 'r') as f:
        content = f.read()

    # Retain the source-level checks and supplement them with execution tests below.
    assert "(c * 5.0f / 9.0f)" not in content and "(c * 5 / 9)" not in content, "The bug in celsius_to_fahrenheit is still present."
    assert "9.0f / 5.0f" in content or "9 / 5.0" in content or "9.0 / 5" in content or "1.8" in content, "The corrected formula for celsius_to_fahrenheit was not found."


def test_makefile_fixed():
    makefile = '/home/user/src/Makefile'
    assert os.path.exists(makefile), f"File {makefile} does not exist."

    with open(makefile, 'r') as f:
        content = f.read()

    assert "-lm" in content, "The Makefile does not link the math library (-lm)."


@pytest.fixture(scope='session')
def built_recovery_tool():
    # Remove stale artifacts so success requires a real build through the Makefile.
    for name in ('recover', 'recover.o', 'utils.o'):
        path = os.path.join(SRC_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ['make', '-C', SRC_DIR, 'all'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Recovery tool failed to compile:\n{result.stdout}"
    assert os.path.isfile(RECOVER), "Makefile did not produce the recover executable."
    assert os.access(RECOVER, os.X_OK), "Built recovery tool is not executable."
    with open(RECOVER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The Makefile did not produce a compiled ELF recovery tool."
    return RECOVER


def run_tool(tool, wal_path, csv_path):
    result = subprocess.run(
        [tool, wal_path, csv_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Recovery tool exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_built_tool_reproduces_requested_recovery(built_recovery_tool, tmp_path):
    generated = tmp_path / 'recovered.csv'
    run_tool(built_recovery_tool, '/home/user/data/sensor.wal', str(generated))
    with open(generated, 'rb') as f:
        generated_bytes = f.read()
    with open('/home/user/recovered_data.csv', 'rb') as f:
        submitted_bytes = f.read()
    assert submitted_bytes == generated_bytes, (
        "The requested recovered CSV is not the output produced by the compiled tool for sensor.wal."
    )


def test_built_tool_on_unseen_wal(built_recovery_tool, tmp_path):
    # Runtime-generated records prevent a fixed CSV or hard-coded known WAL answers
    # from satisfying the behavioral test.
    rng = random.SystemRandom()
    base_ts = rng.randrange(1800000000, 3000000000)
    records = []
    for i in range(7):
        records.append((base_ts + i * rng.randrange(1, 20), rng.randrange(1, 100000), rng.randrange(0, 101)))

    wal_path = tmp_path / 'unseen.wal'
    csv_path = tmp_path / 'unseen.csv'
    with open(wal_path, 'wb') as f:
        for ts, sid, temp_c in records:
            f.write(struct.pack('<IIf', ts, sid, float(temp_c)))

    run_tool(built_recovery_tool, str(wal_path), str(csv_path))
    with open(csv_path, 'r') as f:
        lines = [line.rstrip('\r\n') for line in f]

    expected = ['timestamp,sensor_id,temp_f']
    expected.extend(
        f"{ts},{sid},{(temp_c * 9.0 / 5.0) + 32.0:.2f}"
        for ts, sid, temp_c in records
    )
    assert lines == expected, f"Recovery tool produced incorrect output for an unseen WAL: {lines!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
