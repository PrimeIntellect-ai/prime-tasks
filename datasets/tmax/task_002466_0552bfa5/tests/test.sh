#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/etl.sh")
LOGINS = Path("/home/user/logins.csv")
SUBS = Path("/home/user/subs.csv")
OUTPUT = Path("/home/user/processed.csv")

ORIGINAL_LOGINS = LOGINS.read_bytes()
ORIGINAL_SUBS = SUBS.read_bytes()


def run_etl():
    subprocess.run(
        ["bash", str(SCRIPT)],
        cwd="/home/user",
        check=True,
        timeout=15,
    )


def test_etl_script_exists_and_executable():
    script_path = "/home/user/etl.sh"
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"

    # Check if executable by owner, group, or others
    st = os.stat(script_path)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Script is not executable: {script_path}"


def test_processed_csv_content():
    # The checked output must be produced by the submitted script, not prewritten.
    if OUTPUT.exists():
        OUTPUT.unlink()
    run_etl()

    output_path = "/home/user/processed.csv"
    assert os.path.exists(output_path), f"Output file missing: {output_path}"
    assert os.path.isfile(output_path), f"Path is not a file: {output_path}"

    expected_content = [
        "u101,premium,12,LowRisk",
        "u102,basic,4,HighRisk",
        "u104,premium,8,LowRisk",
        "u106,basic,3,HighRisk",
        "u107,enterprise,25,LowRisk"
    ]

    with open(output_path, "r") as f:
        # Read lines, strip whitespace/newlines, filter out empty lines
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_content, (
        f"Content of {output_path} does not match expected.\n"
        f"Expected:\n{chr(10).join(expected_content)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def derive_expected(login_text, subs_text):
    plans = {}
    for line in subs_text.splitlines():
        fields = line.split(",")
        if len(fields) == 2:
            plans[fields[0]] = fields[1]

    rows = []
    for line in login_text.splitlines():
        fields = line.split(",")
        if len(fields) != 3:
            continue
        user_id, login_count, days_inactive = fields
        if not re.fullmatch(r"[0-9]+", login_count):
            continue
        if not re.fullmatch(r"[0-9]+", days_inactive):
            continue
        if user_id not in plans:
            continue
        risk = "HighRisk" if int(login_count) < 5 else "LowRisk"
        rows.append(f"{user_id},{plans[user_id]},{login_count},{risk}")
    return sorted(rows, key=lambda row: row.split(",", 1)[0])


def test_etl_handles_changed_inputs_and_overwrites_output():
    token = secrets.token_hex(6)
    login_text = "\n".join([
        f"z_{token},5,3",
        f"bad_days_{token},8,-1",
        f"m_{token},4,12",
        f"login_only_{token},9,0",
        f"bad_count_{token},not_a_num,2",
        f"a_{token},{6 + secrets.randbelow(25)},0",
        f"negative_{token},-2,1",
        f"empty_days_{token},7,empty",
    ]) + "\n"
    subs_text = "\n".join([
        f"m_{token},basic",
        f"bad_count_{token},free",
        f"z_{token},enterprise",
        f"negative_{token},premium",
        f"a_{token},premium",
        f"bad_days_{token},basic",
        f"empty_days_{token},free",
        f"subs_only_{token},free",
    ]) + "\n"
    expected = derive_expected(login_text, subs_text)
    baseline_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        LOGINS.write_text(login_text)
        SUBS.write_text(subs_text)
        OUTPUT.write_text("stale,data,must,disappear\n")

        run_etl()
        first = OUTPUT.read_text().splitlines()
        assert first == expected, f"Changed-input result mismatch: {first!r} != {expected!r}"

        # Verify a subsequent run deterministically overwrites, rather than appends.
        with OUTPUT.open("a") as f:
            f.write("stale,data,must,disappear\n")
        run_etl()
        second = OUTPUT.read_text().splitlines()
        assert second == expected, f"Rerun result mismatch: {second!r} != {expected!r}"
    finally:
        LOGINS.write_bytes(ORIGINAL_LOGINS)
        SUBS.write_bytes(ORIGINAL_SUBS)
        if baseline_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(baseline_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
