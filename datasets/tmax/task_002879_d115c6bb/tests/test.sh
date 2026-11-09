#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/process_data"
CRON_FILE = "/home/user/schedule.cron"
NUM_ITERATIONS = 500
PERIODS = [
    ("temp_morning", "morning"),
    ("temp_afternoon", "afternoon"),
    ("temp_evening", "evening"),
]


def generate_random_csv(num_rows=10):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["record_id", "operator_name", "temp_morning", "temp_afternoon", "temp_evening"])
    for _ in range(num_rows):
        record_id = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(4, 10)))
        operator_name = "".join(random.choices(string.ascii_letters, k=random.randint(3, 15)))
        temp_morning = f"{random.uniform(-50.0, 50.0):.2f}"
        temp_afternoon = f"{random.uniform(-50.0, 50.0):.2f}"
        temp_evening = f"{random.uniform(-50.0, 50.0):.2f}"
        writer.writerow([record_id, operator_name, temp_morning, temp_afternoon, temp_evening])
    return output.getvalue()


def expected_output(csv_input):
    rows = list(csv.DictReader(io.StringIO(csv_input)))
    rows.sort(key=lambda row: row["record_id"])
    lines = []
    for row in rows:
        name = row["operator_name"]
        masked_name = name[:2] + "***" if len(name) >= 2 else name + "***"
        for column, period_name in PERIODS:
            lines.append(
                f'{row["record_id"]} - Operator {masked_name} recorded '
                f'{row[column]} during {period_name}'
            )
    return "".join(line + "\n" for line in lines)


def test_cron_schedule():
    assert os.path.exists(CRON_FILE), f"Cron schedule file missing at {CRON_FILE}"
    with open(CRON_FILE, "r") as f:
        content = f.read().strip()
    assert content == "15 4 1 * *", f"Expected cron expression '15 4 1 * *', got '{content}'"


def test_process_data_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script at {AGENT_SCRIPT} is not a regular file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"
    with open(AGENT_SCRIPT, "rb") as f:
        assert f.read(2) == b"#!", "Agent script must have a shebang"


def test_fuzz_equivalence():
    random.seed(42)
    for i in range(NUM_ITERATIONS):
        csv_input = generate_random_csv(num_rows=random.randint(1, 20))
        expected = expected_output(csv_input)

        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=csv_input,
            text=True,
            capture_output=True,
        )

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script failed with return code {agent_proc.returncode}.\n"
                f"Stderr: {agent_proc.stderr}"
            )

        if agent_proc.stdout != expected:
            pytest.fail(
                f"Mismatch found on iteration {i + 1}!\n"
                f"Input CSV:\n{csv_input}\n"
                f"Expected Output:\n{expected}\n"
                f"Actual Output:\n{agent_proc.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
