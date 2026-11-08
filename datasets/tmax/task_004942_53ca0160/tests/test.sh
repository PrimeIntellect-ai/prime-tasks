#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid

PIPELINE = "/home/user/pipeline"
AGGREGATE = os.path.join(PIPELINE, "aggregate.sh")
RAW_EVENTS = os.path.join(PIPELINE, "raw_events.log")
SUMMARY = os.path.join(PIPELINE, "summary.csv")


def run_pipeline():
    result = subprocess.run(
        ["bash", AGGREGATE],
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"aggregate.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(SUMMARY), f"The final report {SUMMARY} was not generated."
    with open(SUMMARY, "r") as f:
        return [line.strip() for line in f if line.strip()]


def clear_outputs():
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    for path in ("/tmp/enriched.log", os.path.join(PIPELINE, "nonexistent_tmp", "enriched.log")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_missing_config_path_file():
    path_file = "/home/user/missing_config_path.txt"
    assert os.path.isfile(path_file), f"The file {path_file} was not created."

    with open(path_file, "r") as f:
        content = f.read().strip()

    expected_path = "/home/user/pipeline/.hidden_conf/rules.ini"
    assert content == expected_path, f"Expected {path_file} to contain '{expected_path}', but found '{content}'."


def test_config_file_created():
    config_file = "/home/user/pipeline/.hidden_conf/rules.ini"
    assert os.path.isfile(config_file), f"The missing configuration file {config_file} was not created."


def test_summary_csv_content_and_pipeline_execution():
    assert os.path.isfile(AGGREGATE), f"The pipeline script {AGGREGATE} is missing."
    assert os.path.isfile(os.path.join(PIPELINE, "enricher")), "The enricher executable is missing."
    assert os.access(os.path.join(PIPELINE, "enricher"), os.X_OK), "The enricher is not executable."

    with open(AGGREGATE, "r") as f:
        script = f.read()
    assert "/home/user/pipeline/nonexistent_tmp" not in script, "aggregate.sh still uses the invalid temporary directory."

    with open(RAW_EVENTS, "rb") as f:
        original_raw = f.read()

    token = uuid.uuid4().hex[:10]
    dynamic_lines = [
        f"2042-01-03 INFO 10.23.4.5 OK_{token}",
        "BROKEN_TOO_FEW_COLUMNS",
        f"2042-01-04 WARN 10.23.4.6 RETRY_{token}",
        "2042-01-05 INFO 10.23.4.7 TOO MANY COLUMNS",
        f"2042-01-06 ERROR 10.23.4.8 FAIL_{token}",
    ]
    dynamic_expected = [
        f"2042-01-03,OK_{token}",
        f"2042-01-04,RETRY_{token}",
        f"2042-01-06,FAIL_{token}",
    ]

    try:
        with open(RAW_EVENTS, "w") as f:
            f.write("\n".join(dynamic_lines) + "\n")
        clear_outputs()
        actual_dynamic = run_pipeline()
        assert actual_dynamic == dynamic_expected, (
            "aggregate.sh did not process fresh input while safely skipping corrupted records. "
            f"Expected {dynamic_expected}, got {actual_dynamic}"
        )
    finally:
        with open(RAW_EVENTS, "wb") as f:
            f.write(original_raw)

    clear_outputs()
    actual_lines = run_pipeline()
    expected_lines = [
        "2023-10-01,SUCCESS",
        "2023-10-01,RETRY",
        "2023-10-01,FAILURE",
        "2023-10-02,SUCCESS"
    ]
    assert actual_lines == expected_lines, f"The content of {SUMMARY} is incorrect. Expected: {expected_lines}, but got: {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
