#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT = "/home/user/etl_pipeline.sh"
RAW = "/home/user/raw_sensor_data.csv"
CLEANED = "/home/user/cleaned_sensor_data.csv"
TUNE = "/home/user/tune.py"
METRICS = "/home/user/best_model_metrics.json"
MARKER = "/tmp/etl_tune_invocation.json"

CANONICAL_RAW = """timestamp,sensor_id,temperature,humidity,status
2023-01-01T00:00:00Z,S1,22.5,45.0,ACTIVE
2023-01-01T00:01:00Z,S2,,50.0,ACTIVE
2023-01-01T00:02:00Z,S1,23.1,105.0,ERROR
2023-01-01T00:03:00Z,S3,21.0,-5.0,ACTIVE
2023-01-01T00:04:00Z,S2,24.0,55.0,ACTIVE,EXTRA_COLUMN
2023-01-01T00:05:00Z,S1,,99.9,ACTIVE
2023-01-01T00:06:00Z,S3,19.5,40.0,ACTIVE
2023-01-01T00:07:00Z,S1,20.0,0.0,ACTIVE
2023-01-01T00:08:00Z,S2,22.0,100.0,ACTIVE
"""

CANONICAL_TUNE = '''import sys
import json
import csv

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    valid_rows = 0
    with open(sys.argv[1], "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            valid_rows += 1
    best_alpha = 0.1 if valid_rows > 3 else 1.0
    with open("/home/user/best_model_metrics.json", "w") as f:
        json.dump({"best_alpha": best_alpha, "rows_trained": valid_rows}, f)

if __name__ == "__main__":
    main()
'''


def expected_from(raw_text):
    lines = raw_text.splitlines()
    expected = [["timestamp", "sensor_id", "temperature", "humidity", "status"]]
    for line in lines[1:]:
        fields = line.split(",")
        if len(fields) != 5:
            continue
        if float(fields[3]) < 0.0 or float(fields[3]) > 100.0:
            continue
        if fields[2] == "":
            fields[2] = "25.0"
        expected.append(fields)
    return expected


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def run_pipeline():
    result = subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"ETL pipeline exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_pipeline_behavior_and_final_state():
    # Preserve the original assertion that the requested script exists, while
    # also requiring it to be a regular artifact that can actually be run.
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Script {SCRIPT} is not a regular file."

    raw_existed = os.path.exists(RAW)
    tune_existed = os.path.exists(TUNE)
    raw_backup = open(RAW, "rb").read() if raw_existed else None
    tune_backup = open(TUNE, "rb").read() if tune_existed else None
    raw_mode = stat.S_IMODE(os.stat(RAW).st_mode) if raw_existed else 0o666
    tune_mode = stat.S_IMODE(os.stat(TUNE).st_mode) if tune_existed else 0o755

    try:
        # Use unpredictable values so a submission that only writes the known
        # fixture's expected output cannot pass.
        tag = secrets.token_hex(8)
        valid_humidity = f"{10 + secrets.randbelow(8000) / 100:.2f}"
        temperature = f"{15 + secrets.randbelow(2000) / 100:.2f}"
        dynamic_raw = "\n".join([
            "timestamp,sensor_id,temperature,humidity,status",
            f"{tag}-a,R1,,{valid_humidity},ACTIVE",
            f"{tag}-b,R2,{temperature},0.0,EDGE",
            f"{tag}-c,R3,31.5,100.0,EDGE",
            f"{tag}-d,R4,18.0,-0.01,BAD",
            f"{tag}-e,R5,19.0,100.01,BAD",
            f"{tag}-f,R6,20.0,50.0,ACTIVE,EXTRA",
            f"{tag}-g,R7,21.0,55.5,ACTIVE",
            f"{tag}-h,R8,22.0,60.0",
        ]) + "\n"
        with open(RAW, "w") as f:
            f.write(dynamic_raw)

        # Replace tune.py only during this run with a behaviorally equivalent
        # probe, proving the pipeline invokes it with exactly one cleaned-data
        # argument rather than directly fabricating the metrics file.
        token = secrets.token_hex(24)
        probe = "TOKEN = " + repr(token) + "\n" + '''import csv
import json
import os
import sys

if len(sys.argv) != 2:
    sys.exit(41)
input_file = sys.argv[1]
with open(input_file, "r") as f:
    rows = sum(1 for _ in csv.DictReader(f))
with open("/tmp/etl_tune_invocation.json", "w") as f:
    json.dump({"token": TOKEN, "argv": sys.argv[1:], "input_abs": os.path.abspath(input_file)}, f)
with open("/home/user/best_model_metrics.json", "w") as f:
    json.dump({"best_alpha": 0.1 if rows > 3 else 1.0, "rows_trained": rows}, f)
'''
        with open(TUNE, "w") as f:
            f.write(probe)
        os.chmod(TUNE, 0o755)

        for path in (CLEANED, METRICS, MARKER):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        run_pipeline()
        assert os.path.isfile(CLEANED), f"File {CLEANED} is missing after running the pipeline."
        assert read_csv(CLEANED) == expected_from(dynamic_raw), "Pipeline failed the generated ETL fixture."
        assert os.path.isfile(MARKER), "The pipeline did not execute /home/user/tune.py."
        with open(MARKER) as f:
            invocation = json.load(f)
        assert invocation["token"] == token, "The tuning invocation marker is invalid."
        assert len(invocation["argv"]) == 1, "tune.py was not passed exactly one argument."
        assert os.path.realpath(invocation["input_abs"]) == os.path.realpath(CLEANED), "tune.py was not passed the cleaned data file."

        dynamic_count = len(expected_from(dynamic_raw)) - 1
        with open(METRICS) as f:
            dynamic_metrics = json.load(f)
        assert dynamic_metrics["rows_trained"] == dynamic_count
        assert dynamic_metrics["best_alpha"] == (0.1 if dynamic_count > 3 else 1.0)

        # Re-run on the original fixed fixture with the original tuning
        # behavior, retaining all assertions from the prior verifier.
        with open(RAW, "w") as f:
            f.write(CANONICAL_RAW)
        with open(TUNE, "w") as f:
            f.write(CANONICAL_TUNE)
        os.chmod(TUNE, 0o755)
        for path in (CLEANED, METRICS):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        run_pipeline()

        assert os.path.isfile(CLEANED), f"File {CLEANED} is missing."
        expected_rows = [
            ["timestamp", "sensor_id", "temperature", "humidity", "status"],
            ["2023-01-01T00:00:00Z", "S1", "22.5", "45.0", "ACTIVE"],
            ["2023-01-01T00:01:00Z", "S2", "25.0", "50.0", "ACTIVE"],
            ["2023-01-01T00:05:00Z", "S1", "25.0", "99.9", "ACTIVE"],
            ["2023-01-01T00:06:00Z", "S3", "19.5", "40.0", "ACTIVE"],
            ["2023-01-01T00:07:00Z", "S1", "20.0", "0.0", "ACTIVE"],
            ["2023-01-01T00:08:00Z", "S2", "22.0", "100.0", "ACTIVE"],
        ]
        actual_rows = read_csv(CLEANED)
        assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in cleaned data, but found {len(actual_rows)}."
        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."

        assert os.path.isfile(METRICS), f"File {METRICS} was not generated."
        with open(METRICS) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {METRICS} does not contain valid JSON.")
        assert "best_alpha" in data, "Key 'best_alpha' missing from metrics JSON."
        assert "rows_trained" in data, "Key 'rows_trained' missing from metrics JSON."
        assert data["rows_trained"] == 6, f"Expected 'rows_trained' to be 6, got {data['rows_trained']}."
        assert data["best_alpha"] == 0.1, f"Expected 'best_alpha' to be 0.1, got {data['best_alpha']}."
    finally:
        if raw_existed:
            with open(RAW, "wb") as f:
                f.write(raw_backup)
            os.chmod(RAW, raw_mode)
        elif os.path.exists(RAW):
            os.remove(RAW)
        if tune_existed:
            with open(TUNE, "wb") as f:
                f.write(tune_backup)
            os.chmod(TUNE, tune_mode)
        elif os.path.exists(TUNE):
            os.remove(TUNE)
PYTEST

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
