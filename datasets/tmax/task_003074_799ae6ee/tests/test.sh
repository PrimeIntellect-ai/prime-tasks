#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import os
import secrets
import subprocess
import uuid

SCRIPT_PATH = "/home/user/process_logs.sh"
INPUT_PATH = "/home/user/events.txt"
OUTPUT_PATH = "/home/user/normalized.csv"

ORIGINAL_INPUT = """2023-11-01 10:00:00 | ERROR | Disk full
11/01/2023 10:00:00 | ERROR | Disk full
1698832800 | ERROR | Disk full
2023-11-01 10:05:00 | WARN | CPU high
1698833100 | WARN | CPU high
11/01/2023 10:10:00 | INFO | Service up
2023-11-01 10:10:00 | INFO | Service up
1698833400 | INFO | Service up
2023-11-02 08:30:00 | ERROR | Network timeout
1698913800 | ERROR | Network timeout
"""

EXPECTED_ORIGINAL = """timestamp,level,message
1698832800,ERROR,Disk full
1698833100,WARN,CPU high
1698833400,INFO,Service up
1698913800,ERROR,Network timeout"""


def run_script(input_content):
    with open(INPUT_PATH, "w") as f:
        f.write(input_content)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    env["TZ"] = "UTC"
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script file {SCRIPT_PATH} is not executable."


def test_normalized_csv_exists_and_correct():
    # Regenerate the original output rather than trusting a preexisting CSV.
    run_script(ORIGINAL_INPUT)
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_ORIGINAL, (
        f"The contents of {OUTPUT_PATH} do not match the expected output."
    )


def test_script_processes_altered_input():
    # Generate an unpredictable second input so a hardcoded original CSV cannot pass.
    base = 1609459200 + secrets.randbelow(300_000_000)
    token = uuid.uuid4().hex[:12]

    def iso(epoch):
        return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime(
            "%Y-%m-%d %H:%M:%S"
        )

    def us(epoch):
        return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime(
            "%m/%d/%Y %H:%M:%S"
        )

    records = {
        (base - 73, "DEBUG", f"Earlier {token}"),
        (base, "ERROR", f"Primary {token}"),
        (base + 137, "WARN", f"Later {token}"),
        (base + 137, "INFO", f"Same time distinct {token}"),
    }

    lines = [
        f"  {iso(base)}   |  ERROR  |  Primary {token}  ",
        f"{us(base)} | ERROR | Primary {token}",
        f"{base} | ERROR | Primary {token}",
        f" {base - 73} | DEBUG | Earlier {token} ",
        f"{iso(base + 137)} | WARN | Later {token}",
        f"{us(base + 137)} | WARN | Later {token}",
        f"{base + 137} | INFO | Same time distinct {token}",
    ]
    # Randomize line order to ensure output is actually sorted.
    for i in range(len(lines) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        lines[i], lines[j] = lines[j], lines[i]

    run_script("\n".join(lines) + "\n")

    with open(OUTPUT_PATH, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "The normalized CSV is empty."
    assert rows[0] == ["timestamp", "level", "message"], "CSV header is incorrect."
    assert all(len(row) == 3 for row in rows[1:]), "Every output record must have three fields."

    actual = [(int(row[0]), row[1], row[2]) for row in rows[1:]]
    assert [row[0] for row in actual] == sorted(row[0] for row in actual), (
        "Output records are not sorted chronologically."
    )
    assert len(actual) == len(records), "Output contains missing or duplicate records."
    assert set(actual) == records, "Altered input was not normalized and deduplicated correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
