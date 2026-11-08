#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import struct
import subprocess


def test_metrics_out_bin_exists():
    file_path = "/home/user/metrics_out.bin"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."


def test_metrics_out_bin_content():
    file_path = "/home/user/metrics_out.bin"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_data = [
        (10, 5.0, 5.0, 0.0, 0.0),
        (11, 5.0, 5.0, 4.0, 2.0),
        (12, 7.0, 5.666666666666667, 6.0, 3.3333333333333335),
        (13, 7.0, 6.0, 6.0, 4.0),
        (14, 3.0, 5.4, 6.0, 4.4),
        (15, 3.0, 5.0, 10.0, 6.4),
        (16, 3.0, 4.6, 10.0, 7.6),
        (17, 8.0, 4.8, 10.0, 8.4),
    ]

    with open(file_path, "rb") as f:
        data = f.read()

    record_format = "@i4d"
    record_size = struct.calcsize(record_format)

    assert len(data) > 0, "Output file is empty."
    assert len(data) % record_size == 0, (
        f"Output file size ({len(data)} bytes) is not a multiple of "
        f"the expected record size ({record_size} bytes)."
    )

    records = list(struct.iter_unpack(record_format, data))
    assert len(records) == len(expected_data), (
        f"Expected {len(expected_data)} records, found {len(records)}."
    )

    for i, (actual, expected) in enumerate(zip(records, expected_data)):
        assert actual[0] == expected[0], (
            f"Record {i}: Expected timestamp {expected[0]}, got {actual[0]}."
        )
        for j, field_name in enumerate(
            ["metric1_val", "metric1_ma5", "metric2_val", "metric2_ma5"]
        ):
            actual_val = actual[j + 1]
            expected_val = expected[j + 1]
            assert math.isclose(actual_val, expected_val, rel_tol=1e-5, abs_tol=1e-5), (
                f"Record {i} at ts={expected[0]}: Expected {field_name} "
                f"to be {expected_val}, got {actual_val}."
            )


def test_required_source_and_executable_exist():
    source = "/home/user/config_tracker.c"
    executable = "/home/user/config_tracker"

    assert os.path.isfile(source), f"Required C source {source} is missing."
    assert os.path.getsize(source) > 0, f"Required C source {source} is empty."
    assert os.path.isfile(executable), f"Required executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not an ELF executable."


def expected_records(csv_updates, json_updates):
    all_updates = csv_updates + json_updates
    start = min(ts for ts, metric_id, value in all_updates)
    end = max(ts for ts, metric_id, value in all_updates)

    # Assignment in encounter order implements latest-within-file and JSON-over-CSV ties.
    by_time_and_metric = {}
    for ts, metric_id, value in all_updates:
        by_time_and_metric[(ts, metric_id)] = value

    last = {1: 0.0, 2: 0.0}
    history = {1: [], 2: []}
    result = []
    for ts in range(start, end + 1):
        for metric_id in (1, 2):
            key = (ts, metric_id)
            if key in by_time_and_metric:
                last[metric_id] = by_time_and_metric[key]
            history[metric_id].append(last[metric_id])

        ma1_values = history[1][-5:]
        ma2_values = history[2][-5:]
        result.append((
            ts,
            last[1],
            sum(ma1_values) / len(ma1_values),
            last[2],
            sum(ma2_values) / len(ma2_values),
        ))
    return result


def write_challenge_inputs(csv_updates, json_updates):
    with open("/home/user/updates.csv", "w", encoding="utf-8") as f:
        f.write("timestamp,metric_id,value\n")
        for ts, metric_id, value in csv_updates:
            f.write(f"{ts},{metric_id},{value:.17g}\n")

    with open("/home/user/updates.jsonl", "w", encoding="utf-8") as f:
        for ts, metric_id, value in json_updates:
            f.write(f'{{"ts": {ts}, "id": {metric_id}, "val": {value:.17g}}}\n')


def run_and_check(executable, expected):
    output = "/home/user/metrics_out.bin"
    if os.path.exists(output):
        os.unlink(output)

    proc = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"{executable} exited with status {proc.returncode}. stderr: {proc.stderr}"
    )
    assert os.path.isfile(output), f"{executable} did not create {output}."

    with open(output, "rb") as f:
        data = f.read()
    record_format = "@i4d"
    record_size = struct.calcsize(record_format)
    assert len(data) == len(expected) * record_size, (
        f"Expected {len(expected)} records ({len(expected) * record_size} bytes), "
        f"but got {len(data)} bytes from {executable}."
    )
    actual_records = list(struct.iter_unpack(record_format, data))

    for index, (actual, wanted) in enumerate(zip(actual_records, expected)):
        assert actual[0] == wanted[0], (
            f"Dynamic record {index}: expected timestamp {wanted[0]}, got {actual[0]}."
        )
        for field in range(1, 5):
            assert math.isclose(actual[field], wanted[field], rel_tol=1e-9, abs_tol=1e-9), (
                f"Dynamic record {index}, field {field}: expected {wanted[field]}, "
                f"got {actual[field]}."
            )


def test_program_processes_runtime_inputs():
    rng = secrets.SystemRandom()
    base = rng.randint(100, 10000)

    def value():
        return rng.randint(-200, 200) / 4.0

    csv_updates = [
        (base + 6, 1, value()),
        (base + 0, 2, value()),
        (base + 2, 1, value()),
        (base + 2, 1, value()),
        (base + 4, 2, value()),
    ]
    json_updates = [
        (base + 1, 1, value()),
        (base + 2, 1, value()),
        (base + 3, 2, value()),
        (base + 3, 2, value()),
        (base + 8, 2, value()),
        (base + 7, 1, value()),
    ]

    write_challenge_inputs(csv_updates, json_updates)
    expected = expected_records(csv_updates, json_updates)

    # Exercise the submitted compiled artifact.
    run_and_check("/home/user/config_tracker", expected)

    # Also prove that the submitted C source independently builds and implements the behavior.
    rebuilt = "/tmp/config_tracker_verified"
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/config_tracker.c", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_proc.returncode == 0, (
        f"config_tracker.c failed to compile. stderr: {compile_proc.stderr}"
    )
    run_and_check(rebuilt, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
