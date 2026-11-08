#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from decimal import Decimal

import pytest

PROCESS_GO_PATH = "/home/user/process.go"
SETUP_CRON_PATH = "/home/user/setup_cron.sh"
PROCESSED_DATA_PATH = "/home/user/processed_data.csv"
RAW_DATA_PATH = "/home/user/raw_data.csv"
EXPECTED_CRON_JOB = "0 2 * * * cd /home/user && go run /home/user/process.go"

EXPECTED_PROCESSED_DATA = """id,masked_email,distance
4,***@site.net,0.00
3,***@domain.com,30.50
9,***@tech.co,30.50
6,***@hello.com,90.00
1,***@example.com,114.71"""


def test_go_program_exists():
    """Ensure process.go was created."""
    assert os.path.isfile(PROCESS_GO_PATH), f"Go program {PROCESS_GO_PATH} does not exist."


def test_setup_cron_script_exists():
    """Ensure setup_cron.sh was created."""
    assert os.path.isfile(SETUP_CRON_PATH), f"Bash script {SETUP_CRON_PATH} does not exist."


def test_processed_data_correct():
    """Verify the contents of processed_data.csv produced for the original input."""
    assert os.path.isfile(PROCESSED_DATA_PATH), f"Processed data file {PROCESSED_DATA_PATH} does not exist."

    with open(PROCESSED_DATA_PATH, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_PROCESSED_DATA, (
        f"Contents of {PROCESSED_DATA_PATH} do not match the expected output.\n"
        f"Expected:\n{EXPECTED_PROCESSED_DATA}\n\nGot:\n{content}"
    )


def test_crontab_installed():
    """Check if the correct cron job is currently installed."""
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed?")

    found = any(EXPECTED_CRON_JOB in line for line in crontab_output.splitlines())
    assert found, (
        f"Expected cron job '{EXPECTED_CRON_JOB}' not found in crontab.\n"
        f"Current crontab:\n{crontab_output}"
    )


def test_go_program_executes_on_unseen_input():
    """Run the submitted Go program against a fresh fixture and derive its answer."""
    with open(RAW_DATA_PATH, "rb") as f:
        original_raw = f.read()
    with open(PROCESSED_DATA_PATH, "rb") as f:
        original_processed = f.read()

    base = 10000 + secrets.randbelow(70000)
    nonce = secrets.token_hex(6)
    lat = Decimal(secrets.randbelow(3000) + 100) / Decimal(100)
    lon = Decimal(secrets.randbelow(5000) + 100) / Decimal(100)
    tied_distance = lat + lon

    valid = [
        (base + 5, f"origin.{nonce}@zero.example", "0.00", "0.00", Decimal("0"), f"***@zero.example"),
        (base + 2, f"first.{nonce}@tie.example", str(-lat), str(lon), tied_distance, f"***@tie.example"),
        (base + 7, f"second.{nonce}@other.example", str(lat), str(-lon), tied_distance, f"***@other.example"),
        (base + 9, f"far.{nonce}@far.example", "70.00", "80.00", Decimal("150"), f"***@far.example"),
    ]
    invalid = [
        [str(base + 20), f"bad1.{nonce}@invalid.example", "", "10"],
        [str(base + 21), f"bad2.{nonce}@invalid.example", "10", ""],
        [str(base + 22), f"bad3.{nonce}@invalid.example", "not-a-number", "10"],
        [str(base + 23), f"bad4.{nonce}@invalid.example", "91", "0"],
        [str(base + 24), f"bad5.{nonce}@invalid.example", "0", "-181"],
    ]

    rows = [[str(r[0]), r[1], r[2], r[3]] for r in valid] + invalid
    random.SystemRandom().shuffle(rows)
    fixture = "id,email,latitude,longitude\n" + "\n".join(",".join(row) for row in rows) + "\n"

    ordered = sorted(valid, key=lambda r: (r[4], r[0]))
    expected_lines = ["id,masked_email,distance"]
    expected_lines.extend(
        f"{record_id},{masked},{distance:.2f}"
        for record_id, _email, _lat, _lon, distance, masked in ordered
    )
    expected = "\n".join(expected_lines)

    try:
        with open(RAW_DATA_PATH, "w", newline="") as f:
            f.write(fixture)
        if os.path.exists(PROCESSED_DATA_PATH):
            os.remove(PROCESSED_DATA_PATH)

        result = subprocess.run(
            ["go", "run", PROCESS_GO_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, (
            f"go run failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(PROCESSED_DATA_PATH), (
            "The Go program did not create processed_data.csv."
        )
        with open(PROCESSED_DATA_PATH, "r") as f:
            actual = f.read().strip()
        assert actual == expected, (
            f"Go program produced incorrect output for an unseen input.\n"
            f"Expected:\n{expected}\n\nGot:\n{actual}"
        )
    finally:
        with open(RAW_DATA_PATH, "wb") as f:
            f.write(original_raw)
        with open(PROCESSED_DATA_PATH, "wb") as f:
            f.write(original_processed)


def test_setup_script_actually_installs_cron_job():
    """Remove the existing crontab, execute the installer, and inspect its result."""
    subprocess.run(["crontab", "-r"], capture_output=True, text=True)

    result = subprocess.run(
        ["bash", SETUP_CRON_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"setup_cron.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    installed = subprocess.run(
        ["crontab", "-l"], capture_output=True, text=True
    )
    assert installed.returncode == 0, (
        "setup_cron.sh did not install a readable crontab.\n"
        f"stderr:\n{installed.stderr}"
    )
    lines = [line.strip() for line in installed.stdout.splitlines()]
    assert EXPECTED_CRON_JOB in lines, (
        f"Executing setup_cron.sh did not install the exact required job "
        f"'{EXPECTED_CRON_JOB}'.\nCurrent crontab:\n{installed.stdout}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
