#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import uuid
from collections import defaultdict

SCRIPT_FILE = "/home/user/analyze_hubs.sh"
OUTPUT_FILE = "/home/user/suspicious_hubs.csv"
LOG_FILE = "/home/user/audit_logs.jsonl"


def get_expected_hubs(log_path):
    sender_receivers = defaultdict(set)
    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            if (data.get("type") == "TRANSFER" and
                    data.get("status") == "COMPLETED" and
                    data.get("amount", 0) > 50000):
                sender = data.get("sender_id")
                receiver = data.get("receiver_id")
                if sender and receiver:
                    sender_receivers[sender].add(receiver)

    counts = [(sender, len(receivers))
              for sender, receivers in sender_receivers.items()]
    counts.sort(key=lambda x: (-x[1], x[0]))
    return [f"{sender},{count}" for sender, count in counts[1:4]]


def read_actual_output():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."
    with open(OUTPUT_FILE, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_suspicious_hubs_csv_content():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist. Did you run your script and redirect output correctly?"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

    expected_lines = get_expected_hubs(LOG_FILE)
    actual_lines = read_actual_output()

    assert actual_lines == expected_lines, (
        f"Contents of {OUTPUT_FILE} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual:   {actual_lines}"
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a file."
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script file {SCRIPT_FILE} is not executable. Use 'chmod +x' to make it executable."

    with open(SCRIPT_FILE, "rb") as f:
        first_line = f.readline(512).decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and re.search(r"(?:^|[/\\s])bash(?:\\s|$)", first_line), (
        f"{SCRIPT_FILE} must be a Bash script with a Bash shebang."
    )


def make_case(counts):
    token = uuid.uuid4().hex[:10]
    senders = [f"S_{uuid.uuid4().hex[:8]}_{token}" for _ in counts]
    logs = []

    for sender, count in zip(senders, counts):
        receivers = [f"R_{uuid.uuid4().hex[:10]}" for _ in range(count)]
        for receiver in receivers:
            logs.append({
                "timestamp": "2026-01-01T00:00:00Z",
                "type": "TRANSFER",
                "sender_id": sender,
                "receiver_id": receiver,
                "amount": 50001 + random.SystemRandom().randrange(100000),
                "status": "COMPLETED",
            })

        # A duplicate must not increase degree.
        logs.append({
            "timestamp": "2026-01-02T00:00:00Z",
            "type": "TRANSFER",
            "sender_id": sender,
            "receiver_id": receivers[0],
            "amount": 999999,
            "status": "COMPLETED",
        })

        # These records must all be filtered out.
        for suffix, amount, status, event_type in [
            ("failed", 900000, "FAILED", "TRANSFER"),
            ("boundary", 50000, "COMPLETED", "TRANSFER"),
            ("low", 49999, "COMPLETED", "TRANSFER"),
            ("noise", 900000, "COMPLETED", "LOGIN"),
        ]:
            logs.append({
                "timestamp": "2026-01-03T00:00:00Z",
                "type": event_type,
                "sender_id": sender,
                "receiver_id": f"INVALID_{suffix}_{uuid.uuid4().hex[:8]}",
                "amount": amount,
                "status": status,
            })

    random.SystemRandom().shuffle(logs)
    return logs


def test_script_executes_pipeline_on_fresh_inputs():
    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    output_existed = os.path.exists(OUTPUT_FILE)
    original_output = None
    if output_existed:
        with open(OUTPUT_FILE, "rb") as f:
            original_output = f.read()

    try:
        # Different count layouts exercise distinct counting, filtering, tie
        # ordering, descending ordering, offset, and limit.
        for counts in ([9, 7, 7, 5, 4, 2], [6, 6, 4, 4, 3, 1]):
            logs = make_case(counts)
            with open(LOG_FILE, "w") as f:
                for event in logs:
                    f.write(json.dumps(event) + "\n")

            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)

            result = subprocess.run(
                [SCRIPT_FILE],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"{SCRIPT_FILE} failed when executed (exit {result.returncode}).\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )

            expected_lines = get_expected_hubs(LOG_FILE)
            actual_lines = read_actual_output()
            assert actual_lines == expected_lines, (
                "The script did not compute the required result for a fresh input.\n"
                f"Expected: {expected_lines}\nActual:   {actual_lines}"
            )
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        if output_existed:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
