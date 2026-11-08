#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import json
import math
import os
import random
import secrets
import subprocess
import tempfile


def run_gate(script_path, csv_path):
    result = subprocess.run(
        ["python3", script_path, csv_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.stdout.strip()


def expected_result(text):
    lines = text.splitlines()
    if not lines or lines[0] != "timestamp_ms,sensor_A,sensor_B":
        return "REJECT"

    try:
        rows = list(csv.reader(io.StringIO("\n".join(lines[1:]))))
        if not rows or any(len(row) != 3 for row in rows):
            return "REJECT"

        timestamps = []
        sensor_a = []
        sensor_b = []
        for row in rows:
            timestamps.append(int(row[0]))
            sensor_a.append(float(row[1]))
            sensor_b.append(float(row[2]))

        if not all(math.isfinite(x) for x in sensor_a + sensor_b):
            return "REJECT"
        if any(timestamps[i] <= timestamps[i - 1] for i in range(1, len(timestamps))):
            return "REJECT"
        if any(timestamps[i] - timestamps[i - 1] > 1000 for i in range(1, len(timestamps))):
            return "REJECT"
        if any(sum(sensor_a[i - 2:i + 1]) / 3.0 > 100.0 for i in range(2, len(sensor_a))):
            return "REJECT"

        mean_b = sum(sensor_b) / len(sensor_b)
        if not 10.0 <= mean_b <= 20.0:
            return "REJECT"
    except (ValueError, OverflowError, csv.Error):
        return "REJECT"

    return "ACCEPT"


def make_csv(rows, header="timestamp_ms,sensor_A,sensor_B"):
    return header + "\n" + "\n".join(",".join(str(v) for v in row) for row in rows) + "\n"


def test_cycle_frames_json():
    json_path = "/home/user/cycle_frames.json"
    assert os.path.isfile(json_path), f"Missing required output file: {json_path}"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    assert "cycle_frames" in data, f"Key 'cycle_frames' missing in {json_path}"

    expected_frames = [45, 46, 47, 120, 121, 250, 251, 252, 253]
    actual_frames = data["cycle_frames"]
    assert actual_frames == expected_frames, f"Expected cycle_frames to be {expected_frames}, but got {actual_frames}"


def test_quality_gate_adversarial():
    script_path = "/home/user/quality_gate.py"
    assert os.path.isfile(script_path), f"Missing quality gate script: {script_path}"

    clean_files = glob.glob("/app/verifier/clean/*.csv")
    evil_files = glob.glob("/app/verifier/evil/*.csv")
    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_clean = []
    for path in clean_files:
        if run_gate(script_path, path) != "ACCEPT":
            failed_clean.append(os.path.basename(path))

    failed_evil = []
    for path in evil_files:
        if run_gate(script_path, path) != "REJECT":
            failed_evil.append(os.path.basename(path))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: " + ", ".join(failed_clean))
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: " + ", ".join(failed_evil))
    if error_msgs:
        assert False, " | ".join(error_msgs)

    rng = random.SystemRandom()
    cases = []

    # Exact inclusive boundary cases.
    cases.extend([
        make_csv([(0, 100, 10), (1000, 100, 10), (2000, 100, 10)]),
        make_csv([(5, 20, 20), (6, 40, 20), (7, 60, 20)]),
    ])

    for _ in range(18):
        count = rng.randint(3, 9)
        timestamps = [rng.randint(-5000, 5000)]
        for _ in range(1, count):
            timestamps.append(timestamps[-1] + rng.randint(1, 1000))
        a_values = [round(rng.uniform(-50.0, 99.0), 4) for _ in range(count)]
        b_value = round(rng.uniform(10.0, 20.0), 4)
        rows = [[timestamps[i], a_values[i], b_value] for i in range(count)]

        cases.append(make_csv(rows))

        changed = [row[:] for row in rows]
        changed[1][0] = changed[0][0]
        cases.append(make_csv(changed))

        changed = [row[:] for row in rows]
        changed[1][0] = changed[0][0] + 1001
        cases.append(make_csv(changed))

        changed = [row[:] for row in rows]
        changed[0][1] = 100.1
        changed[1][1] = 100.1
        changed[2][1] = 100.1
        cases.append(make_csv(changed))

        changed = [row[:] for row in rows]
        for row in changed:
            row[2] = rng.choice([9.99, 20.01])
        cases.append(make_csv(changed))

    cases.extend([
        make_csv([(1, 1, 15), (2, 1, 15), (3, 1, 15)], "timestamp,sensor_A,sensor_B"),
        make_csv([(1, 1, 15), (2, 1, 15), (3, 1, 15)], "timestamp_ms,sensor_B,sensor_A"),
        "timestamp_ms,sensor_A,sensor_B\n1,1,15\n2,broken,15\n3,1,15\n",
        "timestamp_ms,sensor_A,sensor_B\n1,1,15\n2,1,broken\n3,1,15\n",
        "timestamp_ms,sensor_A,sensor_B\n1,1,15\n2.5,1,15\n3,1,15\n",
        "timestamp_ms,sensor_A,sensor_B\n1,1,15,extra\n2,1,15\n3,1,15\n",
        "timestamp_ms,sensor_A,sensor_B\n",
        "",
    ])

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix=secrets.token_hex(8)) as corpus_dir:
        generated = []
        for text in cases:
            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".csv")
            with open(path, "w", newline="") as f:
                f.write(text)
            generated.append((path, expected_result(text)))

        rng.shuffle(generated)
        for path, expected in generated:
            actual = run_gate(script_path, path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual!r}")

    assert not failures, "Generated adversarial failures: " + " | ".join(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
