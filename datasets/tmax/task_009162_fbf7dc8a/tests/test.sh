#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import subprocess

SCRIPT_PATH = "/home/user/process.sh"
INPUT_PATH = "/home/user/raw_sensors.csv"
OUTPUT_PATH = "/home/user/alerts.csv"


def run_script(csv_text):
    with open(INPUT_PATH, "w", newline="") as f:
        f.write(csv_text)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."

    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_output(rows):
    seen_regions = set()
    expected = []

    for row in rows:
        device_id, region, *values = row
        for index, value in enumerate(values, start=1):
            if float(value) > 50.0 and region not in seen_regions:
                digest = hashlib.md5(device_id.encode()).hexdigest()[:8]
                expected.append(f"{digest},{region},t{index},{value},CRITICAL")
                seen_regions.add(region)

    return expected


def test_process_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_process_script_output():
    fixture = """device_id,region,t1,t2,t3,t4
A100,US-EAST,45.2,55.1,40.0,60.2
B200,US-WEST,30.0,35.0,40.0,45.0
C300,EU-WEST,80.1,20.0,90.5,10.0
A100,US-EAST,55.1,10.0,10.0,10.0
D400,US-WEST,60.0,70.0,80.0,90.0
"""

    lines = run_script(fixture)

    expected_lines = [
        "376c12fb,US-EAST,t2,55.1,CRITICAL",
        "d83b631e,EU-WEST,t1,80.1,CRITICAL",
        "fd32d94a,US-WEST,t1,60.0,CRITICAL",
    ]

    actual_sorted = sorted(lines)
    expected_sorted = sorted(expected_lines)
    assert actual_sorted == expected_sorted, (
        f"Output in {OUTPUT_PATH} does not match expected results.\n"
        f"Expected: {expected_sorted}\nGot: {actual_sorted}"
    )


def test_process_script_on_generated_inputs():
    rng = random.SystemRandom()
    value_pool = ["-3.5", "0", "17.25", "49.9", "50", "50.0", "50.00", "50.01", "51", "72.5", "100.0"]

    for trial in range(4):
        regions = [f"REG-{secrets.token_hex(4)}-{i}" for i in range(6)]
        rows = []

        for region in regions:
            region_rows = []
            for _ in range(3):
                device = f"DEV-{secrets.token_hex(8)}"
                values = [rng.choice(value_pool) for _ in range(4)]
                region_rows.append([device, region, *values])

            # Guarantee that every region has at least one critical record while
            # leaving its earliest qualifying position dependent on row order.
            forced_row = rng.randrange(3)
            forced_column = rng.randrange(4)
            region_rows[forced_row][2 + forced_column] = rng.choice(["50.01", "51", "72.5", "100.0"])
            rows.extend(region_rows)

        rng.shuffle(rows)
        csv_text = "device_id,region,t1,t2,t3,t4\n" + "\n".join(
            ",".join(row) for row in rows
        ) + "\n"

        actual = run_script(csv_text)
        expected = expected_output(rows)
        assert sorted(actual) == sorted(expected), (
            f"Generated trial {trial} produced incorrect output.\n"
            f"Expected: {sorted(expected)}\nGot: {sorted(actual)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
