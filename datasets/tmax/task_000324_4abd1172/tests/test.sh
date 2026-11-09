#!/bin/bash
set -e
mkdir -p /logs/verifier

cd /home/user/telemetry

# Restore the immutable task inputs before evaluating the submitted output.
cat > initial_state.csv << 'EOF'
S1,10.0000
S2,20.0000
EOF
cat > sensor.wal << 'EOF'
1,S1,12.0000
2,S2,18.0000
3,S1,15.0000
4,S2,ERROR_NULL
5,S1,11.0000
6,S2,22.0000
EOF
chown root:root initial_state.csv sensor.wal
chmod 444 initial_state.csv sensor.wal

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
from decimal import Decimal, getcontext, ROUND_DOWN


def test_final_state_csv_exists():
    filepath = "/home/user/telemetry/final_state.csv"
    assert os.path.isfile(filepath), f"The required output file {filepath} does not exist."


def test_final_state_csv_content():
    initial_filepath = "/home/user/telemetry/initial_state.csv"
    wal_filepath = "/home/user/telemetry/sensor.wal"
    final_filepath = "/home/user/telemetry/final_state.csv"

    assert os.path.isfile(initial_filepath), "Missing initial_state.csv"
    assert os.path.isfile(wal_filepath), "Missing sensor.wal"
    assert os.path.isfile(final_filepath), "Missing final_state.csv"

    getcontext().prec = 28

    state = {}
    with open(initial_filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            sensor, val = line.split(',')
            state[sensor] = Decimal(val).quantize(Decimal('0.0000'), rounding=ROUND_DOWN)

    with open(wal_filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) != 3:
                continue
            seq, sensor, val_str = parts
            try:
                val = Decimal(val_str)
            except Exception:
                continue

            if sensor in state:
                curr_val = state[sensor]
                term1 = (curr_val * Decimal('0.9')).quantize(Decimal('0.0000'), rounding=ROUND_DOWN)
                term2 = (val * Decimal('0.1')).quantize(Decimal('0.0000'), rounding=ROUND_DOWN)
                new_val = (term1 + term2).quantize(Decimal('0.0000'), rounding=ROUND_DOWN)
                state[sensor] = new_val

    actual_state = {}
    with open(final_filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            assert len(parts) == 2, f"Invalid format in final_state.csv: {line}"
            sensor, val = parts
            actual_state[sensor] = val

    for sensor, expected_val in state.items():
        expected_str = f"{expected_val:.4f}"
        assert sensor in actual_state, f"Sensor {sensor} missing from final_state.csv"
        actual_val = actual_state[sensor]
        assert actual_val == expected_str, f"Sensor {sensor} has incorrect EMA. Expected {expected_str}, got {actual_val}"

    for sensor in actual_state:
        assert sensor in state, f"Unexpected sensor {sensor} found in final_state.csv"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_process_wal.py
import os
import re
import shutil
import subprocess
from decimal import Decimal, ROUND_DOWN

BASE = "/home/user/telemetry"
SCRIPT = os.path.join(BASE, "process_wal.sh")
Q = Decimal("0.0000")


def expected_state(initial, wal):
    state = {}
    for line in initial.splitlines():
        if line.strip():
            sensor, value = line.strip().split(",")
            state[sensor] = Decimal(value).quantize(Q, rounding=ROUND_DOWN)

    for line in wal.splitlines():
        parts = line.strip().split(",")
        if len(parts) != 3:
            continue
        _, sensor, raw_value = parts
        try:
            value = Decimal(raw_value)
        except Exception:
            continue
        if sensor not in state:
            continue
        term1 = (state[sensor] * Decimal("0.9")).quantize(Q, rounding=ROUND_DOWN)
        term2 = (value * Decimal("0.1")).quantize(Q, rounding=ROUND_DOWN)
        state[sensor] = (term1 + term2).quantize(Q, rounding=ROUND_DOWN)
    return {sensor: f"{value:.4f}" for sensor, value in state.items()}


def read_state(path):
    result = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid generated state line: {line}"
            sensor, value = parts
            assert sensor not in result, f"Duplicate sensor in generated state: {sensor}"
            assert re.fullmatch(r"-?[0-9]+\.[0-9]{4}", value), f"Value is not formatted to exactly four decimals: {value}"
            result[sensor] = value
    return result


def run_case(initial, wal):
    with open(os.path.join(BASE, "initial_state.csv"), "w", encoding="utf-8") as f:
        f.write(initial)
    with open(os.path.join(BASE, "sensor.wal"), "w", encoding="utf-8") as f:
        f.write(wal)

    current = os.path.join(BASE, "current_state.csv")
    if os.path.exists(current):
        os.remove(current)

    completed = subprocess.run(
        [SCRIPT], cwd=BASE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"process_wal.sh failed with exit code {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(current), "process_wal.sh did not produce current_state.csv"
    assert read_state(current) == expected_state(initial, wal)


def main():
    assert os.path.isfile(SCRIPT), "Missing process_wal.sh"
    assert not os.path.islink(SCRIPT), "process_wal.sh must be a regular script"
    assert os.access(SCRIPT, os.X_OK), "process_wal.sh is not executable"

    with open(SCRIPT, encoding="utf-8") as f:
        source = f.read()
    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bbc\b", active_source), "process_wal.sh must use bc"
    assert re.search(r"scale\s*=\s*4", active_source), "bc calculations must set scale=4"

    final_path = os.path.join(BASE, "final_state.csv")
    saved_final = None
    if os.path.isfile(final_path):
        with open(final_path, "rb") as f:
            saved_final = f.read()
        os.remove(final_path)

    cases = [
        (
            "S1,10.0000\nS2,20.0000\n",
            "1,S1,12.0000\n2,S2,18.0000\n3,S1,15.0000\n4,S2,ERROR_NULL\n5,S1,11.0000\n6,S2,22.0000\n",
        ),
        (
            "A,1.2345\nB,-2.5000\n",
            "1,A,2.3456\n2,A,4x\n3,B,-1.1111\n4,A,9.8765\n5,B,BAD_VALUE\n",
        ),
    ]

    try:
        for initial, wal in cases:
            run_case(initial, wal)
    finally:
        if saved_final is not None:
            with open(final_path, "wb") as f:
                f.write(saved_final)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_process_wal.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
