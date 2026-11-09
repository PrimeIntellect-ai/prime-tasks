#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import datetime
import itertools
import json
import os
import secrets
import subprocess


def test_script_exists_and_executable():
    script_path = "/home/user/find_deadlocks.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_deadlocks_log_exists():
    log_path = "/home/user/deadlocks.log"
    assert os.path.exists(log_path), f"The log file {log_path} does not exist. Did you run the script?"
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."


def test_deadlocks_log_content():
    log_path = "/home/user/deadlocks.log"
    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_lines = ["T001,T002", "T005,T007"]
    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {log_path} do not match expected output for 2023-10-01.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )


def test_script_parameterization():
    script_path = "/home/user/find_deadlocks.sh"
    log_path = "/home/user/deadlocks.log"

    # Run the script for another date to test parameterization
    try:
        subprocess.run([script_path, "2023-10-02"], check=True)
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to execute {script_path} with argument '2023-10-02': {e}"

    assert os.path.exists(log_path), f"The log file {log_path} was not created after running the script."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_lines = ["T009,T010"]
    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert actual_lines == expected_lines, (
        f"Script did not correctly process the date parameter '2023-10-02'.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )


def test_script_on_unseen_transaction_data():
    script_path = "/home/user/find_deadlocks.sh"
    data_path = "/home/user/transactions.jsonl"
    log_path = "/home/user/deadlocks.log"
    original_data = open(data_path, "rb").read()

    token = secrets.token_hex(6)
    start = datetime.date(2040 + secrets.randbelow(10), 4, 10 + secrets.randbelow(8))
    dates = [(start + datetime.timedelta(days=i)).isoformat() for i in range(3)]
    records = []
    counter = 0

    def add(sender, receiver, timestamp):
        nonlocal counter
        counter += 1
        records.append({
            "tx_id": f"X{token}_{counter:03d}",
            "sender": sender,
            "receiver": receiver,
            "amount": float(counter) + 0.25,
            "timestamp": timestamp,
        })

    for index, date in enumerate(dates):
        prefix = f"{token}_{index}"
        add(f"alice_{prefix}", f"bob_{prefix}", f"{date}T08:15:20Z")
        add(f"bob_{prefix}", f"alice_{prefix}", f"{date}T08:15:20Z")
        add(f"carol_{prefix}", f"dave_{prefix}", f"{date}T13:44:05Z")
        add(f"dave_{prefix}", f"carol_{prefix}", f"{date}T13:44:05Z")
        # Reciprocal directions at different timestamps are not deadlocks.
        add(f"eve_{prefix}", f"frank_{prefix}", f"{date}T17:00:00Z")
        add(f"frank_{prefix}", f"eve_{prefix}", f"{date}T17:00:01Z")
        # Same timestamp without reciprocal endpoints is also not a deadlock.
        add(f"grace_{prefix}", f"heidi_{prefix}", f"{date}T19:30:00Z")
        add(f"heidi_{prefix}", f"ivan_{prefix}", f"{date}T19:30:00Z")

    # Shuffle so neither input order nor transaction ID order reveals the answer.
    secrets.SystemRandom().shuffle(records)

    def expected_for(date):
        pairs = []
        for left, right in itertools.combinations(records, 2):
            if not left["timestamp"].startswith(date + "T"):
                continue
            if left["timestamp"] != right["timestamp"]:
                continue
            if left["sender"] == right["receiver"] and left["receiver"] == right["sender"]:
                pairs.append(",".join(sorted((left["tx_id"], right["tx_id"]))))
        return sorted(pairs)

    try:
        with open(data_path, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        for date in dates + [(start + datetime.timedelta(days=20)).isoformat()]:
            result = subprocess.run(
                [script_path, date],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"Failed to execute {script_path} for unseen date {date}.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(log_path), f"The script did not create {log_path} for {date}."
            with open(log_path, "r") as f:
                actual = [line.strip() for line in f.read().splitlines() if line.strip()]
            expected = expected_for(date)
            assert actual == expected, (
                f"Incorrect result for dynamically generated transactions on {date}.\n"
                f"Expected: {expected}\nGot: {actual}"
            )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
