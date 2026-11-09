#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/clean_data.sh"
INPUT_PATH = "/home/user/telemetry.csv"
OUTPUT_PATH = "/home/user/clean_telemetry.csv"


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_clean_data_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), (
        f"The script {SCRIPT_PATH} is not executable."
    )


def test_clean_telemetry_output_and_pipeline_behavior():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    prior_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            prior_output = f.read()
    restored_output = prior_output

    try:
        # Execute the submitted artifact on the supplied dataset before retaining
        # the original exact-output assertion.
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        run_script()
        assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."

        expected_content = """timestamp,sensor_id,masked_ip,temperature
2023-10-01T10:00:00Z,S1,192.168.1.XXX,22.1
2023-10-01T10:01:00Z,S2,10.0.0.XXX,24.5
2023-10-01T10:03:00Z,S3,172.16.0.XXX,21.0
2023-10-01T10:04:00Z,S4,8.8.8.XXX,-5.4"""

        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual_content = f.read().strip()
        actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
        expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            f"The content of {OUTPUT_PATH} does not match the expected output."
        )
        with open(OUTPUT_PATH, "rb") as f:
            restored_output = f.read()

        # Replace the input with an unpredictable RFC 4180 fixture. This checks
        # actual CSV parsing, embedded newlines, JSON extraction, filtering, and
        # masking rather than accepting a pre-generated fixed output.
        token = secrets.token_hex(6)
        random_temp = secrets.randbelow(8000) + 1000
        octet = secrets.randbelow(240) + 10
        rows = [
            [
                "2040-01-01T00:00:00Z",
                f"sensor-{token}",
                f"203.0.113.{octet}",
                json.dumps({"status": "ok", "temp": random_temp}),
                "first line\nsecond line, with comma\nand a \"quote\"",
            ],
            [
                "2040-01-01T00:01:00Z",
                f"drop-{token}",
                "198.51.100.77",
                json.dumps({"status": "missing", "battery": 91}),
                "missing temperature\nso this row must be dropped",
            ],
            [
                "2040-01-01T00:02:00Z",
                f"cold-{token}",
                "10.20.30.44",
                json.dumps({"temp": -12.75, "status": "cold"}),
                "ordinary note",
            ],
            [
                "2040-01-01T00:03:00Z",
                f"warm-{token}",
                "172.31.9.201",
                json.dumps({"meta": [1, 2], "temp": 3.5}),
                "trailing record after embedded newlines",
            ],
        ]
        with open(INPUT_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "sensor_id", "ip_address", "payload", "notes"])
            writer.writerows(rows)

        os.unlink(OUTPUT_PATH)
        run_script()
        assert os.path.isfile(OUTPUT_PATH), (
            f"The script did not generate {OUTPUT_PATH} for alternate input."
        )

        with open(OUTPUT_PATH, "r", encoding="utf-8", newline="") as f:
            actual_rows = list(csv.reader(f))
        expected_rows = [
            ["timestamp", "sensor_id", "masked_ip", "temperature"],
            ["2040-01-01T00:00:00Z", f"sensor-{token}", "203.0.113.XXX", str(random_temp)],
            ["2040-01-01T00:02:00Z", f"cold-{token}", "10.20.30.XXX", "-12.75"],
            ["2040-01-01T00:03:00Z", f"warm-{token}", "172.31.9.XXX", "3.5"],
        ]
        assert actual_rows == expected_rows, (
            "The script failed on alternate RFC 4180 telemetry containing embedded "
            "newlines, JSON payloads, a row without temp, or IPv4 masking."
        )
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if restored_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(restored_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
