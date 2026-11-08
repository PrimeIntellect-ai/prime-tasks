#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
from collections import defaultdict

SCRIPT = "/home/user/analyze_logs.py"
SOURCE_LOG = "/home/user/data/server_logs.txt"
JSON_OUTPUT = "/home/user/flagged_hours.json"
PIPELINE_LOG = "/home/user/pipeline.log"


def get_expected_flagged_hours():
    log_file = SOURCE_LOG
    assert os.path.exists(log_file), f"Source log file {log_file} missing."

    buckets = defaultdict(lambda: {"total": 0, "errors": 0})
    with open(log_file, "r") as f:
        for line in f:
            # Match format: [YYYY-MM-DD HH:MM:SS] IP METHOD PATH HTTP_VER STATUS
            m = re.match(r"^\[(\d{4}-\d{2}-\d{2} \d{2}):\d{2}:\d{2}\].*? (\d{3})$", line.strip())
            if m:
                hour = f"{m.group(1)}:00"
                status = int(m.group(2))
                buckets[hour]["total"] += 1
                if status >= 500:
                    buckets[hour]["errors"] += 1

    expected_flagged = []
    for hour in sorted(buckets.keys()):
        total = buckets[hour]["total"]
        errors = buckets[hour]["errors"]
        rate = errors / total
        if rate > 0.05:
            expected_flagged.append({
                "hour": hour,
                "total": total,
                "errors": errors,
                "error_rate": round(rate, 4)
            })
    return expected_flagged


def run_script():
    for path in (JSON_OUTPUT, PIPELINE_LOG):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_OUTPUT), f"Executing {SCRIPT} did not create {JSON_OUTPUT}."
    assert os.path.isfile(PIPELINE_LOG), f"Executing {SCRIPT} did not create {PIPELINE_LOG}."


def assert_current_outputs(expected):
    with open(JSON_OUTPUT, "r") as f:
        actual = json.load(f)
    assert actual == expected, f"Pipeline output for exercised input was {actual!r}, expected {expected!r}."

    with open(PIPELINE_LOG, "r") as f:
        content = f.read()
    for line in (
        "[INFO] Stage: Extract and Bucket - Completed",
        "[INFO] Stage: Aggregate - Completed",
        "[INFO] Stage: Validation Gate - Completed",
        f"[INFO] Pipeline finished. Flagged hours: {len(expected)}",
    ):
        assert line in content, f"Expected log line '{line}' not found after executing the pipeline."


def test_00_script_exists_and_processes_logs():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."
    assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty."

    with open(SOURCE_LOG, "rb") as f:
        original_logs = f.read()

    probe_lines = []
    # Deliberately unsorted buckets: 09:00 is exactly 5% and must not be flagged.
    for i in range(19):
        probe_lines.append(f"[2024-02-03 09:{i:02d}:00] 192.0.2.1 GET /ok 1.1 200")
    probe_lines.append("[2024-02-03 09:59:59] 192.0.2.2 GET /edge 1.1 500")
    probe_lines.extend([
        "[2024-02-03 10:02:03] 192.0.2.3 POST /late 1.1 503",
        "[2024-02-03 08:01:02] 192.0.2.4 GET /early 1.1 200",
        "[2024-02-03 10:04:05] 192.0.2.5 GET /late 1.1 204",
        "[2024-02-03 08:03:04] 192.0.2.6 GET /early 1.1 599",
        "[2024-02-03 08:05:06] 192.0.2.7 GET /early 1.1 404",
    ])

    try:
        with open(SOURCE_LOG, "w") as f:
            f.write("\n".join(probe_lines) + "\n")
        expected_probe = get_expected_flagged_hours()
        run_script()
        assert_current_outputs(expected_probe)
    finally:
        with open(SOURCE_LOG, "wb") as f:
            f.write(original_logs)
        # Produce the required final artifacts from the original source data.
        run_script()


def test_flagged_hours_json():
    expected_flagged = get_expected_flagged_hours()
    json_file = JSON_OUTPUT

    assert os.path.exists(json_file), f"Output file {json_file} does not exist."

    with open(json_file, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_file} is not valid JSON."

    assert isinstance(actual_data, list), f"{json_file} should contain a JSON list."
    assert len(actual_data) == len(expected_flagged), f"Expected {len(expected_flagged)} flagged hours, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_flagged)):
        assert "hour" in actual, f"Missing 'hour' key in item {i}."
        assert actual["hour"] == expected["hour"], f"Expected hour {expected['hour']}, got {actual['hour']}."

        assert "total" in actual, f"Missing 'total' key in item {i}."
        assert actual["total"] == expected["total"], f"Expected total {expected['total']}, got {actual['total']}."

        assert "errors" in actual, f"Missing 'errors' key in item {i}."
        assert actual["errors"] == expected["errors"], f"Expected errors {expected['errors']}, got {actual['errors']}."

        assert "error_rate" in actual, f"Missing 'error_rate' key in item {i}."
        assert isinstance(actual["error_rate"], float), f"'error_rate' should be a float in item {i}."
        assert abs(actual["error_rate"] - expected["error_rate"]) < 1e-5, f"Expected error_rate {expected['error_rate']}, got {actual['error_rate']}."


def test_error_rate_has_exactly_four_decimal_places():
    class LexicalFloat(float):
        def __new__(cls, token):
            value = float.__new__(cls, token)
            value.token = token
            return value

    with open(JSON_OUTPUT, "r") as f:
        data = json.load(f, parse_float=LexicalFloat)

    for i, item in enumerate(data):
        rate = item["error_rate"]
        assert isinstance(rate, LexicalFloat), f"'error_rate' must be represented as a JSON float in item {i}."
        assert re.fullmatch(r"-?(?:0|[1-9]\d*)\.\d{4}", rate.token), (
            f"'error_rate' must have exactly four decimal places in item {i}; got {rate.token}."
        )


def test_pipeline_log():
    expected_flagged = get_expected_flagged_hours()
    log_file = PIPELINE_LOG

    assert os.path.exists(log_file), f"Pipeline log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read()

    expected_lines = [
        "[INFO] Stage: Extract and Bucket - Completed",
        "[INFO] Stage: Aggregate - Completed",
        "[INFO] Stage: Validation Gate - Completed"
    ]

    for line in expected_lines:
        assert line in content, f"Expected log line '{line}' not found in {log_file}."

    expected_final_line = f"[INFO] Pipeline finished. Flagged hours: {len(expected_flagged)}"
    assert expected_final_line in content, f"Expected final log line '{expected_final_line}' not found in {log_file}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
