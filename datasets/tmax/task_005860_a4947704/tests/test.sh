#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import csv
import random
import secrets
import shutil
import subprocess
from collections import defaultdict

import pytest

LOG_PATH = "/home/user/etl_dump.log"
OUTPUT_PATH = "/home/user/user_features.csv"
CPP_PATH = "/home/user/process_logs.cpp"
BINARY_PATH = "/tmp/process_logs_verified"

data_pattern = re.compile(r'DATA=\{action:\s*"([^"]*)",\s*amount:\s*"([^"]*)",\s*ip:\s*"([^"]*)"\}')


def remove_output():
    if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
        shutil.rmtree(OUTPUT_PATH)
    elif os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)


def expected_rows_for_log(log_path):
    seen = set()
    user_data = defaultdict(lambda: {"total_purchase_amount": 0, "ips": set()})

    with open(log_path, "r", encoding="utf-8") as f:
        for line in f:
            parts = [p.strip() for p in line.split("|", 3)]
            if len(parts) < 4:
                continue

            user_id = parts[2]
            raw_payload = parts[3]
            dup_key = (user_id, raw_payload)
            if dup_key in seen:
                continue
            seen.add(dup_key)

            match = data_pattern.search(raw_payload)
            if match:
                action = match.group(1).lower()
                amount = int(match.group(2))
                ip = match.group(3)
                if action == "purchase":
                    user_data[user_id]["total_purchase_amount"] += amount
                user_data[user_id]["ips"].add(ip)

    return [
        [user_id, str(user_data[user_id]["total_purchase_amount"]),
         ";".join(sorted(user_data[user_id]["ips"]))]
        for user_id in sorted(user_data)
    ]


def assert_output_matches(log_path):
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing after running the compiled program."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."
    expected = expected_rows_for_log(log_path)
    with open(OUTPUT_PATH, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Output CSV is empty."
    assert rows[0] == ["user_id", "total_purchase_amount", "unique_ips"], "Invalid CSV header."
    actual = [row for row in rows[1:] if row]
    assert actual == expected, f"Compiled C++ program produced incorrect rows. Expected {expected}, got {actual}."


def run_compiled_program():
    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def make_random_log():
    rng = random.Random(secrets.randbits(128))
    users = ["U" + secrets.token_hex(4).upper() for _ in range(7)]
    actions = ["purchase", "PURCHASE", "Purchase", "login", "View", "view"]
    ips = [f"10.{rng.randrange(1, 255)}.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}" for _ in range(8)]
    records = []
    txn = rng.randrange(10000, 90000)

    for event in range(65):
        user = rng.choice(users)
        action = rng.choice(actions)
        amount = rng.randrange(1, 500) if action.lower() == "purchase" else 0
        ip = rng.choice(ips)
        marker = secrets.token_hex(6)
        prefix = rng.choice(["Retry attempt", "Initial processing", "Failed step", "Payload received"])
        raw = f'{prefix} {marker}. DATA={{action: "{action}", amount: "{amount}", ip: "{ip}"}}'
        copies = 1 + rng.randrange(0, 3)
        for copy in range(copies):
            timestamp = f"2026-08-{1 + (event % 25):02d}T12:{event % 60:02d}:{copy:02d}Z"
            records.append(f"{timestamp} | TXN-{txn} | {user} | {raw}\n")
            txn += 1

    # The same raw payload under a different user must not be deduplicated globally.
    shared_raw = f'Shared {secrets.token_hex(6)}. DATA={{action: "Purchase", amount: "73", ip: "{ips[0]}"}}'
    records.append(f"2026-09-01T00:00:00Z | TXN-{txn} | {users[0]} | {shared_raw}\n")
    records.append(f"2026-09-01T00:00:01Z | TXN-{txn + 1} | {users[1]} | {shared_raw}\n")
    records.append(f"2026-09-01T00:00:02Z | TXN-{txn + 2} | {users[0]} | {shared_raw}\n")
    rng.shuffle(records)
    return "".join(records)


@pytest.fixture(scope="session", autouse=True)
def compile_and_exercise_cpp_program():
    assert os.path.exists(CPP_PATH), f"Source file {CPP_PATH} is missing."
    assert os.path.isfile(CPP_PATH), f"Source path {CPP_PATH} is not a file."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O3", CPP_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {CPP_PATH}. stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), "Compilation did not produce an executable."

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    try:
        for _ in range(2):
            with open(LOG_PATH, "w", encoding="utf-8") as f:
                f.write(make_random_log())
            remove_output()
            run_compiled_program()
            assert_output_matches(LOG_PATH)
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        remove_output()
        run_compiled_program()


def test_user_features_csv_correctness():
    log_file_path = "/home/user/etl_dump.log"
    output_file_path = "/home/user/user_features.csv"

    assert os.path.exists(output_file_path), f"Output file {output_file_path} is missing."
    assert os.path.isfile(output_file_path), f"{output_file_path} is not a file."

    seen = set()
    user_data = defaultdict(lambda: {"total_purchase_amount": 0, "ips": set()})

    data_pattern = re.compile(r'DATA=\{action:\s*"([^"]*)",\s*amount:\s*"([^"]*)",\s*ip:\s*"([^"]*)"\}')

    with open(log_file_path, "r", encoding="utf-8") as f:
        for line in f:
            parts = [p.strip() for p in line.split("|", 3)]
            if len(parts) < 4:
                continue

            user_id = parts[2]
            raw_payload = parts[3]

            dup_key = (user_id, raw_payload)
            if dup_key in seen:
                continue
            seen.add(dup_key)

            match = data_pattern.search(raw_payload)
            if match:
                action = match.group(1).lower()
                amount = int(match.group(2))
                ip = match.group(3)

                if action == "purchase":
                    user_data[user_id]["total_purchase_amount"] += amount
                user_data[user_id]["ips"].add(ip)

    expected_rows = []
    for user_id in sorted(user_data.keys()):
        amount = user_data[user_id]["total_purchase_amount"]
        ips = ";".join(sorted(list(user_data[user_id]["ips"])))
        expected_rows.append([user_id, str(amount), ips])

    actual_rows = []
    with open(output_file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["user_id", "total_purchase_amount", "unique_ips"], f"Invalid header in {output_file_path}"
        for row in reader:
            if row:
                actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def test_cpp_file_exists():
    cpp_file = "/home/user/process_logs.cpp"
    assert os.path.exists(cpp_file), f"Source file {cpp_file} is missing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
