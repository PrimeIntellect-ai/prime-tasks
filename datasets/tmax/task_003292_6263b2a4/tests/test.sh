#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import pytest

DISK_PATH = "/home/user/disk_image.bin"
LOG_PATH = "/home/user/recovered_logs.jsonl"
METRICS_PATH = "/home/user/metrics.json"
PROJECT_PATH = "/home/user/log_processor"


def canonical_entries():
    return [
        {"timestamp": 1670000000 + i, "sensor_val": 100000.0 + i * 0.125}
        for i in range(100)
    ]


def entries_from_disk():
    assert os.path.isfile(DISK_PATH), f"Disk image missing at {DISK_PATH}"
    with open(DISK_PATH, "rb") as f:
        data = f.read()

    entries = []
    for payload in re.findall(rb"LOG_ENTRY: ([^\r\n]+)", data):
        try:
            entries.append(json.loads(payload.decode("ascii")))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            pytest.fail(f"Invalid embedded log entry in disk image: {exc}")
    return entries


def read_metrics(path):
    assert os.path.isfile(path), f"Metrics file missing at {path}"
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file at {path} is not valid JSON")


def assert_metrics(metrics, entries):
    assert "processed_count" in metrics, "Metrics JSON missing 'processed_count'"
    assert metrics["processed_count"] == len(entries), (
        f"Expected processed_count to be {len(entries)}, got {metrics['processed_count']}"
    )
    assert "total_sensor_value" in metrics, "Metrics JSON missing 'total_sensor_value'"
    expected_total = sum(entry["sensor_val"] for entry in entries)
    actual_total = metrics["total_sensor_value"]
    assert actual_total == expected_total, (
        f"Expected total_sensor_value to be exactly {expected_total}, got {actual_total}. "
        "Check if f64 was used for accumulation."
    )


def run_processor(input_path, output_path):
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--", str(input_path), str(output_path)],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"log processor failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return read_metrics(str(output_path))


def test_recovered_logs_exist_and_valid():
    assert os.path.isfile(LOG_PATH), f"Recovered logs file missing at {LOG_PATH}"

    with open(LOG_PATH, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 100, f"Expected 100 log entries, found {len(lines)}"

    recovered = []
    for i, line in enumerate(lines):
        try:
            parsed = json.loads(line)
            assert "timestamp" in parsed, f"Line {i} missing 'timestamp' field"
            assert "sensor_val" in parsed, f"Line {i} missing 'sensor_val' field"
            recovered.append(parsed)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i} is not valid JSON: {line}")

    embedded = entries_from_disk()
    expected = canonical_entries()
    assert embedded == expected, "The embedded logs in disk_image.bin were altered or are incomplete"
    assert recovered == embedded, "Recovered logs do not exactly match the entries in disk_image.bin"


def test_metrics_json_correctness():
    metrics = read_metrics(METRICS_PATH)
    expected_entries = entries_from_disk()
    assert len(expected_entries) == 100
    assert_metrics(metrics, expected_entries)


def test_rust_code_fixes():
    main_rs_path = "/home/user/log_processor/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Rust source file missing at {main_rs_path}"

    with open(main_rs_path, "r") as f:
        content = f.read()

    assert "i <= entries.len()" not in content, "The off-by-one error (<= entries.len()) is still present in main.rs"
    assert "total: f32" not in content, "The precision loss bug (total: f32) is still present in main.rs"
    assert "as f32" not in content, "Casting to f32 is still present in main.rs"


def test_processor_executes_correctly(tmp_path):
    assert os.path.isfile(os.path.join(PROJECT_PATH, "Cargo.toml")), "Cargo.toml is missing"

    recovered_output = tmp_path / "recovered_metrics.json"
    recovered_metrics = run_processor(LOG_PATH, recovered_output)
    assert_metrics(recovered_metrics, entries_from_disk())

    synthetic_entries = [
        {"timestamp": 1, "sensor_val": 16777216.0},
        {"timestamp": 2, "sensor_val": 1.0},
        {"timestamp": 3, "sensor_val": 1.0},
        {"timestamp": 4, "sensor_val": 0.125},
        {"timestamp": 5, "sensor_val": 100000.375},
    ]
    synthetic_input = tmp_path / "synthetic.jsonl"
    synthetic_output = tmp_path / "synthetic_metrics.json"
    with open(synthetic_input, "w") as f:
        for entry in synthetic_entries:
            f.write(json.dumps(entry) + "\n")

    synthetic_metrics = run_processor(synthetic_input, synthetic_output)
    assert_metrics(synthetic_metrics, synthetic_entries)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
