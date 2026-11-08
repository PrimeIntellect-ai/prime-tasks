#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import uuid
from collections import defaultdict

import pytest

SRC_FILE = "/home/user/src/aggregator.cpp"
BIN_FILE = "/home/user/bin/aggregator"
LOG_FILE = "/home/user/data/config_logs.txt"
META_FILE = "/home/user/data/server_meta.csv"
OUTPUT_FILE = "/home/user/output/hourly_summary.json"


def compute_expected():
    server_env = {}
    with open(META_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            server_env[row["ServerID"]] = row["Environment"]

    log_pattern = re.compile(r"^\[(.*?)\] .*?: Server \{(.*?)\} updated config \[(.*?)\] -> (.*)$")
    unique_records = set()
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = log_pattern.match(line)
            if match:
                unique_records.add(match.groups())

    counts = defaultdict(int)
    for timestamp, server_id, config_key, new_value in unique_records:
        if server_id not in server_env:
            continue
        hour = timestamp[:13] + ":00:00Z"
        counts[(hour, server_env[server_id])] += 1

    expected = [
        {"change_count": count, "environment": env, "hour": hour}
        for (hour, env), count in counts.items()
    ]
    expected.sort(key=lambda x: (x["hour"], x["environment"]))
    return expected


def load_output():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file {OUTPUT_FILE} is not valid JSON: {e}")


def assert_current_output():
    actual_data = load_output()
    expected_data = compute_expected()
    assert actual_data == expected_data, (
        f"Data mismatch in {OUTPUT_FILE}.\n"
        f"Expected:\n{json.dumps(expected_data, indent=4)}\n"
        f"Got:\n{json.dumps(actual_data, indent=4)}"
    )


def test_hourly_summary_json():
    assert os.path.exists(META_FILE), f"Metadata file {META_FILE} missing."
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} missing."
    assert_current_output()


def test_source_code_exists():
    assert os.path.exists(SRC_FILE), f"Source file {SRC_FILE} does not exist."


def test_binary_exists():
    assert os.path.exists(BIN_FILE), f"Binary file {BIN_FILE} does not exist."
    assert os.access(BIN_FILE, os.X_OK), f"File {BIN_FILE} is not executable."


def test_source_compiles_and_binary_processes_derived_inputs():
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SRC_FILE, "-o", BIN_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        "aggregator.cpp failed to compile:\n" + compile_result.stdout + compile_result.stderr
    )
    assert os.path.exists(BIN_FILE), f"Binary file {BIN_FILE} does not exist after compilation."
    assert os.access(BIN_FILE, os.X_OK), f"File {BIN_FILE} is not executable after compilation."

    with open(META_FILE, "rb") as f:
        original_meta = f.read()
    with open(LOG_FILE, "rb") as f:
        original_logs = f.read()

    token = uuid.uuid4().hex
    srv_a = "srv-a-" + token[:8]
    srv_b = "srv-b-" + token[8:16]
    srv_c = "srv-c-" + token[16:24]
    unknown = "srv-missing-" + token[24:]
    env_a = "Zulu_" + token[:6]
    env_b = "Alpha_" + token[6:12]
    env_c = "Middle_" + token[12:18]
    hour = 1 + (int(token[:4], 16) % 19)
    hour1 = f"2025-07-19T{hour:02d}"
    hour2 = f"2025-07-19T{hour + 1:02d}"

    metadata = (
        "ServerID,Role,Environment\n"
        f"{srv_c},Worker,{env_c}\n"
        f"{srv_a},Database,{env_a}\n"
        f"{srv_b},Web,{env_b}\n"
    )
    logs = [
        f"[{hour1}:47:31Z] INFO: Server {{{srv_a}}} updated config [key_{token[:5]}] -> value-one-{token}",
        f"[{hour1}:47:31Z] INFO: Server {{{srv_a}}} updated config [key_{token[:5]}] -> value-one-{token}",
        f"[{hour1}:47:31Z] WARN: Server {{{srv_a}}} updated config [key_{token[:5]}] -> value-two-{token}",
        f"[{hour1}:02:09Z] INFO: Server {{{srv_b}}} updated config [other_{token[5:10]}] -> enabled",
        f"[{hour2}:59:58Z] INFO: Server {{{srv_c}}} updated config [later_{token[10:15]}] -> 900",
        f"[{hour2}:59:58Z] INFO: Server {{{srv_c}}} updated config [later_{token[10:15]}] -> 900",
        f"[{hour1}:11:12Z] INFO: Server {{{unknown}}} updated config [ignored] -> {token}",
        "this line is intentionally malformed",
        f"[{hour1}:55:00Z] INFO: Server {{{srv_a}}} updated config [third_{token[15:20]}] -> spaced value {token}",
    ]

    try:
        with open(META_FILE, "w", encoding="utf-8", newline="") as f:
            f.write(metadata)
        with open(LOG_FILE, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(logs) + "\n")
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        run_result = subprocess.run(
            [BIN_FILE],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "Compiled aggregator failed on derived inputs:\n"
            + run_result.stdout
            + run_result.stderr
        )
        assert_current_output()
    finally:
        with open(META_FILE, "wb") as f:
            f.write(original_meta)
        with open(LOG_FILE, "wb") as f:
            f.write(original_logs)

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    restore_result = subprocess.run(
        [BIN_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert restore_result.returncode == 0, (
        "Compiled aggregator failed on the original inputs:\n"
        + restore_result.stdout
        + restore_result.stderr
    )
    assert_current_output()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
