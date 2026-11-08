#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import subprocess
from pathlib import Path

import pytest


def test_etl_script_exists_and_executable():
    script_path = "/home/user/etl.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_output_csv_content():
    output_path = "/home/user/output.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    expected_content = """user_id,event,region,tier
101,login,NA,Pro
102,purchase,EU,Free
103,logout,AP,Pro
105,view_item,SA,Free
"""

    with open(output_path, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]

    assert actual_lines == expected_lines, f"Content of {output_path} does not match expected output."


def test_etl_executes_on_new_input_and_joins_files():
    raw_path = Path("/home/user/raw_events.jsonl")
    users_path = Path("/home/user/users.csv")
    output_path = Path("/home/user/output.csv")
    script_path = "/home/user/etl.sh"

    def snapshot(path):
        if path.exists():
            return (True, path.read_bytes(), path.stat().st_mode & 0o7777)
        return (False, b"", None)

    def restore(path, state):
        existed, data, mode = state
        if existed:
            path.write_bytes(data)
            os.chmod(path, mode)
        elif path.exists():
            path.unlink()

    saved = {path: snapshot(path) for path in (raw_path, users_path, output_path)}

    try:
        ids = random.SystemRandom().sample(range(200, 900), 4)
        event_names = [f"evt_{secrets.token_hex(4)}" for _ in ids]
        metadata_values = [("EU", "Free"), ("NA", "Pro"), ("AP", "Free"), ("SA", "Pro")]
        metadata = dict(zip(ids, metadata_values))
        events = dict(zip(ids, event_names))

        event_order = ids[:]
        user_order = ids[:]
        random.SystemRandom().shuffle(event_order)
        random.SystemRandom().shuffle(user_order)

        raw_lines = []
        for index, uid in enumerate(event_order):
            notes = "Broken escape \\uZZZZ here" if index % 2 == 0 else "Another bad escape \\u12X3"
            raw_lines.append(
                f'{{"timestamp": "2026-01-01T00:00:{index:02d}Z", "user_id": {uid}, '
                f'"event": "{events[uid]}", "notes": "{notes}"}}'
            )
        raw_path.write_text("\n".join(raw_lines) + "\n")

        user_lines = ["user_id,region,tier"]
        for uid in user_order:
            region, tier = metadata[uid]
            user_lines.append(f"{uid},{region},{tier}")
        users_path.write_text("\n".join(user_lines) + "\n")
        os.chmod(raw_path, 0o644)
        os.chmod(users_path, 0o644)

        if output_path.exists():
            output_path.unlink()

        result = subprocess.run(
            ["runuser", "-u", "user", "--", script_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"ETL script failed when run as user (exit {result.returncode}). "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert output_path.is_file(), "ETL script did not create /home/user/output.csv."

        with output_path.open(newline="") as f:
            actual_rows = list(csv.reader(f))

        expected_rows = [["user_id", "event", "region", "tier"]]
        for uid in sorted(ids):
            region, tier = metadata[uid]
            expected_rows.append([str(uid), events[uid], region, tier])

        assert actual_rows == expected_rows, (
            "Executing etl.sh on a new malformed-JSON batch did not produce the "
            "correct numerically sorted join with users.csv."
        )
    finally:
        for path in (raw_path, users_path, output_path):
            restore(path, saved[path])


def test_crontab_entry():
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"],
            capture_output=True,
            text=True,
            check=True,
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read user account crontab: {e.stderr}")

    pattern = re.compile(r"^0\s+\*\s+\*\s+\*\s+\*.*\/home\/user\/etl\.sh", re.MULTILINE)
    assert pattern.search(crontab_output), (
        "Crontab entry for /home/user/etl.sh at minute 0 (0 * * * *) "
        "is missing or incorrect in the user account's crontab."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
