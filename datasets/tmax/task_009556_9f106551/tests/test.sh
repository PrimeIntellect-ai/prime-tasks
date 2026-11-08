#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import pytest

WORKFLOW = "/home/user/workflow.sh"
SOURCE = "/home/user/process_ts.c"
RAW = "/home/user/raw_sensors.csv"
OUTPUT = "/home/user/processed_sensors.csv"
BINARY = "/home/user/process_ts"


def run_workflow():
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        [WORKFLOW], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"workflow.sh failed with exit code {result.returncode}:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY), "workflow.sh did not create /home/user/process_ts."
    assert os.access(BINARY, os.X_OK), "/home/user/process_ts is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process_ts is not a compiled ELF program."


def test_workflow_script_exists_and_executable():
    script_path = "/home/user/workflow.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_c_program_exists():
    c_path = "/home/user/process_ts.c"
    assert os.path.exists(c_path), f"{c_path} does not exist."


def test_processed_sensors_output():
    run_workflow()

    output_path = "/home/user/processed_sensors.csv"
    assert os.path.exists(output_path), f"{output_path} does not exist. Did the workflow run?"

    with open(output_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_data = [
        ("1620000000", "正常启动", 10.0, -0.501634, 0),
        ("1620000060", "警告: 信号弱", 12.0, -0.440830, 0),
        ("1620000120", "Система OK", 14.0, -0.380026, 0),
        ("1620000180", "En attente", 12.0, -0.440830, 0),
        ("1620000240", "ERROR_SPIKE", 100.0, 2.234551, 1),
        ("1620000300", "استئناف", 11.0, -0.471232, 0)
    ]

    assert len(lines) == len(expected_data), f"Expected {len(expected_data)} rows in output, found {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, expected_data)):
        parts = line.split(",")
        assert len(parts) >= 5, f"Row {i+1} does not have at least 5 comma-separated columns."

        timestamp = parts[0]
        event_message = ",".join(parts[1:-3])
        interp_val_str = parts[-3]
        zscore_str = parts[-2]
        anomaly_str = parts[-1]

        exp_timestamp, exp_event, exp_interp, exp_zscore, exp_anomaly = expected

        assert timestamp == exp_timestamp, f"Row {i+1} timestamp mismatch: expected {exp_timestamp}, got {timestamp}."
        assert event_message == exp_event, f"Row {i+1} event message mismatch: expected {exp_event}, got {event_message}."

        try:
            interp_val = float(interp_val_str)
            zscore = float(zscore_str)
            anomaly = int(anomaly_str)
        except ValueError:
            pytest.fail(f"Row {i+1} contains non-numeric values for interpolated value, z-score, or anomaly flag.")

        assert math.isclose(interp_val, exp_interp, abs_tol=0.0002), \
            f"Row {i+1} interpolated value mismatch: expected ~{exp_interp:.4f}, got {interp_val_str}."

        assert math.isclose(zscore, exp_zscore, abs_tol=0.0002), \
            f"Row {i+1} Z-score mismatch: expected ~{exp_zscore:.4f}, got {zscore_str}."

        assert anomaly == exp_anomaly, \
            f"Row {i+1} anomaly flag mismatch: expected {exp_anomaly}, got {anomaly}."


def derive_expected(rows):
    values = [row[2] for row in rows]
    interpolated = list(values)
    i = 0
    while i < len(interpolated):
        if interpolated[i] is not None:
            i += 1
            continue
        left = i - 1
        right = i
        while right < len(interpolated) and interpolated[right] is None:
            right += 1
        assert left >= 0 and right < len(interpolated)
        start = interpolated[left]
        end = interpolated[right]
        span = right - left
        for j in range(left + 1, right):
            interpolated[j] = start + (end - start) * (j - left) / span
        i = right

    mean = sum(interpolated) / len(interpolated)
    variance = sum((v - mean) ** 2 for v in interpolated) / len(interpolated)
    stddev = math.sqrt(variance)
    return [
        (ts, message, value, (value - mean) / stddev,
         1 if abs((value - mean) / stddev) > 2.0 else 0)
        for (ts, message, _), value in zip(rows, interpolated)
    ]


def csv_text(rows):
    return "".join(
        f"{ts},{message},{'' if value is None else value}\n"
        for ts, message, value in rows
    )


def validate_output(text, rows):
    expected = derive_expected(rows)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == len(expected), f"Expected {len(expected)} output rows, got {len(lines)}."

    number_4dp = re.compile(r"^-?(?:\d+)\.\d{4}$")
    for index, (line, exp) in enumerate(zip(lines, expected), 1):
        parts = line.split(",")
        assert len(parts) >= 5, f"Dynamic row {index} has fewer than five columns."
        timestamp = parts[0]
        message = ",".join(parts[1:-3])
        value_text, z_text, anomaly_text = parts[-3:]
        exp_ts, exp_message, exp_value, exp_z, exp_anomaly = exp

        assert timestamp == exp_ts
        assert message == exp_message
        assert number_4dp.fullmatch(value_text), f"Row {index} value is not formatted with %.4f: {value_text}"
        assert number_4dp.fullmatch(z_text), f"Row {index} Z-score is not formatted with %.4f: {z_text}"
        assert anomaly_text in ("0", "1")

        value = float(value_text)
        zscore = float(z_text)
        assert math.isfinite(value) and math.isfinite(zscore)
        assert math.isclose(value, exp_value, rel_tol=0.0, abs_tol=0.00011)
        assert math.isclose(zscore, exp_z, rel_tol=0.0, abs_tol=0.00011)
        assert int(anomaly_text) == exp_anomaly


def test_c_program_and_workflow_on_derived_inputs():
    datasets = [
        [
            ("1700000000", "起動", 1.0),
            ("1700000060", "ожидание", None),
            ("1700000120", "تحذير", None),
            ("1700000180", "reprendre", 7.0),
            ("1700000240", "正常", 9.0),
            ("1700000300", "missing", None),
            ("1700000360", "fin", 13.0),
            ("1700000420", "EXTREME", 60.0),
        ],
        [
            ("1800000000", "α", 0.0),
            ("1800000060", "β", 0.0),
            ("1800000120", "γ", 0.0),
            ("1800000180", "δ", 0.0),
            ("1800000240", "exact-boundary", 10.0),
        ],
    ]

    with open(RAW, "rb") as f:
        original_raw = f.read()

    compiled = "/tmp/process_ts_from_source"
    try:
        build = subprocess.run(
            ["gcc", SOURCE, "-o", compiled, "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert build.returncode == 0, f"process_ts.c did not compile:\n{build.stderr}"

        for rows in datasets:
            input_text = csv_text(rows)

            direct = subprocess.run(
                [compiled], input=input_text, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=10
            )
            assert direct.returncode == 0, f"Compiled C program failed:\n{direct.stderr}"
            validate_output(direct.stdout, rows)

            with open(RAW, "w", encoding="utf-8") as f:
                f.write(input_text)
            run_workflow()
            assert os.path.exists(OUTPUT), "workflow.sh did not create processed_sensors.csv."
            with open(OUTPUT, "r", encoding="utf-8") as f:
                validate_output(f.read(), rows)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        try:
            subprocess.run([WORKFLOW], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
