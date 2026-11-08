#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitize"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
EXPECTED_FIELDS = ["timestamp", "sensor_id", "measurement", "signature", "rolling_avg"]


def expected_signature(ts, sid, meas):
    return (ts + (sid * 7) + meas) % 9999


def process_reference(input_file):
    with open(input_file, "r", newline="") as f:
        rows = list(csv.DictReader(f))

    valid_rows = []
    seen_sigs = set()
    for r in rows:
        ts = int(r["timestamp"])
        sid = int(r["sensor_id"])
        meas = int(r["measurement"])
        sig = int(r["signature"])

        if expected_signature(ts, sid, meas) != sig:
            continue
        if sig in seen_sigs:
            continue
        seen_sigs.add(sig)
        valid_rows.append(r)

    sensor_history = {}
    output_rows = []
    anomalous = False
    for r in valid_rows:
        sid = int(r["sensor_id"])
        meas = int(r["measurement"])
        sensor_history.setdefault(sid, []).append(meas)
        window = sensor_history[sid][-3:]
        avg = sum(window) / len(window)
        if avg > 500.0:
            anomalous = True

        new_row = dict(r)
        new_row["rolling_avg"] = f"{avg:.2f}"
        output_rows.append(new_row)

    return output_rows, anomalous


def process_python(input_file):
    # Simulate the expected logic to get the exact output for comparison.
    return process_reference(input_file)[0]


def write_input(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "measurement", "signature"])
        writer.writerows(rows)


def assert_clean_result(input_path, output_path):
    result = subprocess.run(
        [SCRIPT_PATH, input_path, output_path], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Clean input exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(output_path), "Output file was not created"

    expected_rows, anomalous = process_reference(input_path)
    assert not anomalous
    with open(output_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == EXPECTED_FIELDS
        actual_rows = list(reader)
    assert actual_rows == expected_rows


def test_sanitize_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus dir missing: {CLEAN_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".csv")]
    assert len(clean_files) > 0, "No clean files found."

    failed_files = []
    for filename in clean_files:
        input_path = os.path.join(CLEAN_DIR, filename)
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_path = tmp.name

        try:
            result = subprocess.run(
                [SCRIPT_PATH, input_path, output_path], capture_output=True, text=True
            )
            if result.returncode != 0:
                failed_files.append((filename, f"Exit code {result.returncode} != 0"))
                continue
            if not os.path.isfile(output_path):
                failed_files.append((filename, "Output file not created"))
                continue

            expected_rows = process_python(input_path)
            with open(output_path, "r", newline="") as f:
                reader = csv.DictReader(f)
                actual_rows = list(reader)

            if len(actual_rows) != len(expected_rows):
                failed_files.append((filename, f"Row count mismatch: expected {len(expected_rows)}, got {len(actual_rows)}"))
                continue

            for i, (exp, act) in enumerate(zip(expected_rows, actual_rows)):
                for k in exp.keys():
                    if exp[k] != act.get(k):
                        failed_files.append((filename, f"Row {i} mismatch on {k}: expected {exp[k]}, got {act.get(k)}"))
                        break
                else:
                    continue
                break
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if failed_files:
        errors = "\n".join([f"{f}: {e}" for f, e in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/failed:\n{errors}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus dir missing: {EVIL_DIR}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".csv")]
    assert len(evil_files) > 0, "No evil files found."

    bypassed_files = []
    for filename in evil_files:
        input_path = os.path.join(EVIL_DIR, filename)
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_path = tmp.name

        try:
            result = subprocess.run(
                [SCRIPT_PATH, input_path, output_path], capture_output=True, text=True
            )
            if result.returncode == 0:
                bypassed_files.append((filename, "Exit code 0 (should be non-zero)"))
                continue
            if os.path.isfile(output_path) and os.path.getsize(output_path) > 0:
                bypassed_files.append((filename, "Output file created and not empty"))
                continue
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if bypassed_files:
        errors = "\n".join([f"{f}: {e}" for f, e in bypassed_files])
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed:\n{errors}")


def test_generated_clean_validation_dedup_and_per_sensor_windows():
    rng = random.SystemRandom()
    sensor_ids = rng.sample(range(20, 9000), 18)
    used_sigs = set()
    base_rows = []

    def fresh_valid(sid, meas):
        while True:
            ts = rng.randrange(1700000000, 1900000000)
            sig = expected_signature(ts, sid, meas)
            if sig not in used_sigs:
                used_sigs.add(sig)
                return [ts, sid, meas, sig]

    # Many interleaved sensors exercise independent rolling histories.
    for sid in sensor_ids:
        for _ in range(rng.randint(7, 12)):
            base_rows.append(fresh_valid(sid, rng.randint(1, 450)))
    rng.shuffle(base_rows)

    rows = list(base_rows)

    # Add distinct, valid rows whose signatures collide with earlier rows. They
    # must be removed by first-occurrence signature deduplication.
    for original in rng.sample(base_rows, 8):
        ts, sid, meas, sig = original
        rows.append([ts + 1, sid, meas - 1, sig])

    # Invalid rows include values that would be anomalous if validation were
    # skipped, and must not influence histories or output.
    for _ in range(12):
        sid = rng.choice(sensor_ids)
        meas = rng.randint(700, 1500)
        ts = rng.randrange(1700000000, 1900000000)
        valid_sig = expected_signature(ts, sid, meas)
        bad_sig = (valid_sig + rng.randint(1, 9998)) % 9999
        rows.insert(rng.randrange(len(rows) + 1), [ts, sid, meas, bad_sig])

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, f"telemetry_{rng.randrange(1 << 60)}.csv")
        output_path = os.path.join(td, f"result_{rng.randrange(1 << 60)}.csv")
        write_input(input_path, rows)
        assert_clean_result(input_path, output_path)


def test_generated_anomaly_after_validation_and_sensor_specific_windowing():
    rng = random.SystemRandom()
    target_sid, other_sid = rng.sample(range(100, 9000), 2)
    used_sigs = set()

    def fresh_valid(sid, meas):
        while True:
            ts = rng.randrange(1800000000, 1950000000)
            sig = expected_signature(ts, sid, meas)
            if sig not in used_sigs:
                used_sigs.add(sig)
                return [ts, sid, meas, sig]

    rows = [
        fresh_valid(target_sid, 490),
        fresh_valid(other_sid, 20),
        fresh_valid(target_sid, 510),
        fresh_valid(other_sid, 30),
    ]
    # This invalid high row must be ignored rather than being the reason for rejection.
    bad_ts = rng.randrange(1800000000, 1950000000)
    bad_meas = 2000
    bad_sig = (expected_signature(bad_ts, target_sid, bad_meas) + 1) % 9999
    rows.append([bad_ts, target_sid, bad_meas, bad_sig])
    rows.extend([
        fresh_valid(other_sid, 40),
        fresh_valid(target_sid, 520),
    ])

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, f"telemetry_{rng.randrange(1 << 60)}.csv")
        output_path = os.path.join(td, f"result_{rng.randrange(1 << 60)}.csv")
        write_input(input_path, rows)
        expected_rows, anomalous = process_reference(input_path)
        assert expected_rows and anomalous

        # Match the original verifier's empty pre-created output condition.
        open(output_path, "wb").close()
        result = subprocess.run(
            [SCRIPT_PATH, input_path, output_path], capture_output=True, text=True, timeout=30
        )
        assert result.returncode != 0, "Generated anomalous input was accepted"
        assert not os.path.exists(output_path) or os.path.getsize(output_path) == 0, (
            "Anomalous input left a non-empty output file"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
