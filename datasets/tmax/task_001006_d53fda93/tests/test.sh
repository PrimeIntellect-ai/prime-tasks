#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile

DETECT_SCRIPT = "/home/user/detect.sh"
PIPELINE_BIN = "/home/user/pipeline"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
RNG = secrets.SystemRandom()


def test_detect_script_exists_and_executable():
    assert os.path.isfile(DETECT_SCRIPT), f"{DETECT_SCRIPT} does not exist."
    assert os.access(DETECT_SCRIPT, os.X_OK), f"{DETECT_SCRIPT} is not executable."


def test_pipeline_exists_and_executable():
    assert os.path.isfile(PIPELINE_BIN), f"{PIPELINE_BIN} does not exist."
    assert os.access(PIPELINE_BIN, os.X_OK), f"{PIPELINE_BIN} is not executable."
    with open(PIPELINE_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline is not a compiled executable"


def test_detector_adversarial_corpus():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]

    clean_failures = []
    evil_failures = []

    for cf in clean_files:
        result = subprocess.run([DETECT_SCRIPT, cf], capture_output=True, text=True)
        if result.stdout.strip() != "CLEAN":
            clean_failures.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([DETECT_SCRIPT, ef], capture_output=True, text=True)
        if result.stdout.strip() != "EVIL":
            evil_failures.append(os.path.basename(ef))

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (failed to classify as CLEAN): {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed (failed to classify as EVIL): {', '.join(evil_failures)}")

    assert not clean_failures and not evil_failures, " | ".join(error_msg)


def _run_detector(contents, expected):
    name = os.path.join(tempfile.gettempdir(), "telemetry_" + secrets.token_hex(12) + ".csv")
    try:
        with open(name, "w") as f:
            f.write(contents)
        result = subprocess.run([DETECT_SCRIPT, name], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0
        assert result.stdout in (expected, expected + "\n"), (
            f"expected exactly {expected}, got {result.stdout!r}"
        )
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def test_detector_runtime_generated_inputs():
    ts = RNG.randrange(100000, 900000)
    sid = "sensor_" + secrets.token_hex(5)
    value = RNG.uniform(0.01, 999.99)
    clean = f"{ts},{sid},{value:.6f}\n{ts+1},A_9,0.0\n{ts+2},zZ0_,1000.0\n"
    _run_detector(clean, "CLEAN")

    bad_id = sid + RNG.choice(["-", ".", "<", "/", "!"])
    _run_detector(f"{ts},{sid},{value:.6f}\n{ts+1},{bad_id},25.0\n", "EVIL")
    _run_detector(f"{ts},{sid},-{RNG.uniform(0.01, 50):.6f}\n", "EVIL")
    _run_detector(f"{ts},{sid},{RNG.uniform(1000.01, 5000):.6f}\n", "EVIL")
    _run_detector(f"{ts},{sid},not_a_float\n", "EVIL")


def _parse_pipeline_output(stdout):
    parsed = {}
    for line in stdout.splitlines():
        assert line.strip(), "pipeline emitted a blank output line"
        parts = line.split(',')
        assert len(parts) == 3, f"malformed output line: {line!r}"
        try:
            bucket = int(parts[0])
            value = float(parts[2])
        except ValueError as exc:
            raise AssertionError(f"malformed output line: {line!r}") from exc
        assert math.isfinite(value), f"non-finite moving average: {line!r}"
        key = (bucket, parts[1])
        assert key not in parsed, f"duplicate aggregate line for {key}"
        parsed[key] = value
    return parsed


def _run_pipeline(input_data):
    result = subprocess.run([PIPELINE_BIN], input=input_data, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, "Pipeline failed to execute"
    return result, _parse_pipeline_output(result.stdout)


def test_pipeline_functionality():
    input_data = """1620000000,sensor_A,10.0
1620000000,sensor_A,10.0
1620000010,sensor_A,20.0
1620000060,sensor_A,30.0
1620000120,sensor_A,40.0
1620000180,sensor_A,50.0
1620000000,sensor_B,-5.0
1620000000,sensor_C,9999.0
"""
    result, parsed = _run_pipeline(input_data)
    output_lines = result.stdout.strip().split('\n')

    # Preserve the original filtering assertions without imposing output order.
    assert not any("sensor_B" in line for line in output_lines), "Pipeline failed to filter negative values"
    assert not any("sensor_C" in line for line in output_lines), "Pipeline failed to filter high values"

    expected = {
        (1620000000, "sensor_A"): 15.0,
        (1620000060, "sensor_A"): 22.5,
        (1620000120, "sensor_A"): 28.3333333333,
        (1620000180, "sensor_A"): 40.0,
    }
    assert set(parsed) == set(expected)
    for key, wanted in expected.items():
        # The original verifier accepted a one-decimal rendering of 28.333...
        tolerance = 0.1 if key[0] == 1620000120 else 0.01
        assert abs(parsed[key] - wanted) <= tolerance, (key, parsed[key], wanted)


def test_pipeline_exact_concatenated_deduplication_key():
    # Both timestamp+sensor_id strings are "123". The second event is therefore
    # a duplicate under the exact key required by the instruction.
    _, parsed = _run_pipeline("12,3,10.0\n1,23,900.0\n")
    assert set(parsed) == {(0, "3")}
    assert abs(parsed[(0, "3")] - 10.0) <= 0.01


def test_pipeline_runtime_generated_aggregation():
    base = RNG.randrange(2000000, 8000000) * 60
    sensors = ["s_" + secrets.token_hex(4), "node_" + secrets.token_hex(4)]
    rows = []
    bucket_averages = {}

    for b in range(6):
        for sensor_index, sensor in enumerate(sensors):
            values = []
            for event_index, offset in enumerate((5, 31)):
                value = RNG.uniform(1.0, 850.0)
                timestamp = base + b * 60 + offset + sensor_index
                rows.append(f"{timestamp},{sensor},{value:.6f}")
                values.append(value)
                if event_index == 0:
                    # Same timestamp and sensor, but a different value: it must
                    # be discarded because value is not part of the dedup key.
                    rows.append(f"{timestamp},{sensor},{RNG.uniform(900.0, 999.0):.6f}")
            bucket_averages[(b, sensor)] = sum(values) / len(values)

    # Independently generated invalid records must not produce aggregates.
    bad_id = "bad-" + secrets.token_hex(3)
    rows.extend([
        f"{base+9},{bad_id},25.0",
        f"{base+10},negative_{secrets.token_hex(2)},-0.25",
        f"{base+11},huge_{secrets.token_hex(2)},1000.25",
    ])

    _, parsed = _run_pipeline("\n".join(rows) + "\n")
    expected = {}
    for b in range(6):
        for sensor in sensors:
            start = max(0, b - 2)  # WINDOW extracted from the image is 3.
            window_values = [bucket_averages[(prior, sensor)] for prior in range(start, b + 1)]
            expected[(base + b * 60, sensor)] = sum(window_values) / len(window_values)

    assert set(parsed) == set(expected), (set(parsed) - set(expected), set(expected) - set(parsed))
    for key, wanted in expected.items():
        tolerance = max(0.01, abs(wanted) * 1e-5)
        assert abs(parsed[key] - wanted) <= tolerance, (key, parsed[key], wanted)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
