#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

BASE = "/home/user/legacy_analytics"
SCRIPT = os.path.join(BASE, "process_logs.sh")
ACCESS_LOGS = os.path.join(BASE, "access_logs.csv")
REPORT = os.path.join(BASE, "august_report.txt")
MRE = os.path.join(BASE, "mre.csv")


def run_script(csv_path, month):
    return subprocess.run(
        [SCRIPT, csv_path, str(month)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def expected_lines(rows, target_month):
    totals = {}
    for date, user, byte_text in rows:
        if int(date.split("-")[1], 10) == target_month:
            totals[user] = totals.get(user, 0) + int(byte_text, 10)
    return sorted(f"{user}: {total}" for user, total in totals.items())


def test_august_report_content():
    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."

    with open(REPORT, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "user_1: 2500",
        "user_2: 2000",
        "user_3: 800",
    ]
    assert sorted(content) == sorted(expected), (
        f"Content of {REPORT} is incorrect. Expected {expected}, got {content}"
    )


def test_mre_csv_content_and_behavior():
    assert os.path.isfile(MRE), f"MRE file {MRE} is missing."

    with open(MRE, "r", newline="") as f:
        raw = f.read()
    lines = raw.splitlines()

    assert len(lines) == 2, (
        f"MRE file should have exactly 2 lines (header + 1 data row), but has {len(lines)}."
    )
    assert lines[0] == "date,user_id,bytes", "MRE must use the input CSV header."

    parts = lines[1].split(",")
    assert len(parts) == 3, "MRE data row must have exactly three CSV columns."
    date_part, user, byte_text = parts
    assert re.fullmatch(r"[0-9]{4}-08-[0-9]{2}", date_part), (
        "The MRE data row must contain a zero-padded August date."
    )
    assert user, "The MRE user_id must not be empty."
    assert re.fullmatch(r"[0-9]+", byte_text), "The MRE byte count must be a nonnegative integer."

    # Confirm that the row's month causes the precise arithmetic construct from
    # the original implementation to fail under Bash.
    month = date_part.split("-")[1]
    original_expression = subprocess.run(
        ["/bin/bash", "-c", 'month="$1"; if [ $((month)) -eq 8 ]; then :; fi', "_", month],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert original_expression.returncode != 0, (
        "The MRE month does not trigger the original leading-zero arithmetic failure."
    )
    assert original_expression.stderr.strip(), "The reproduced Bash failure produced no diagnostic."

    # The repaired script must process the sole data row (not skip it) and must
    # handle the same zero-padded month successfully.
    result = run_script(MRE, 8)
    assert result.returncode == 0, f"Fixed script fails on MRE: {result.stderr}"
    assert result.stderr == "", f"Fixed script wrote unexpected stderr on MRE: {result.stderr}"
    assert result.stdout.strip().splitlines() == [f"{user}: {int(byte_text, 10)}"]


def test_process_logs_script_fixed_and_report_is_exact_run_output():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    result = run_script(ACCESS_LOGS, 8)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert result.stderr == "", f"Script wrote unexpected stderr: {result.stderr}"

    output_lines = result.stdout.strip().splitlines()
    expected = [
        "user_1: 2500",
        "user_2: 2000",
        "user_3: 800",
    ]
    assert sorted(output_lines) == sorted(expected), (
        f"Script output is incorrect. Expected {expected}, got {output_lines}"
    )

    with open(REPORT, "rb") as f:
        report_bytes = f.read()
    assert report_bytes == result.stdout.encode(), (
        "august_report.txt is not exactly the output printed by the repaired script."
    )


def test_script_is_bash_and_retains_while_read_loop():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.fullmatch(r"#!\s*/(?:usr/bin/env\s+)?bash", first_line), (
        "process_logs.sh must be a Bash script."
    )
    active = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(?m)^\s*while\b[^\n]*\bread\b[^\n]*(?:;\s*)?do\b", active), (
        "The core processing loop must remain a Bash while-read loop."
    )


def test_randomized_parsing_months_first_row_and_missing_final_newline():
    token = secrets.token_hex(8)
    users = [f"qa_{token}_{i}" for i in range(6)]
    amounts = [secrets.randbelow(9000) + 1 for _ in range(11)]

    # The first data row and the final non-newline-terminated row both matter.
    rows = [
        ("2041-08-01", users[0], str(amounts[0])),
        ("2041-07-02", users[1], str(amounts[1])),
        ("2041-08-03", users[2], str(amounts[2])),
        ("2041-09-04", users[0], str(amounts[3])),
        ("2041-08-05", users[0], str(amounts[4])),
        ("2041-09-06", users[3], str(amounts[5])),
        ("2041-08-07", users[2], str(amounts[6])),
        ("2041-07-08", users[4], str(amounts[7])),
        ("2041-09-09", users[3], str(amounts[8])),
        ("2041-08-10", users[5], str(amounts[9])),
        ("2041-08-31", users[1], str(amounts[10])),
    ]

    fd, path = tempfile.mkstemp(prefix="dynamic_logs_", suffix=".csv")
    os.close(fd)
    try:
        payload = "date,user_id,bytes\n" + "\n".join(
            ",".join(row) for row in rows
        )
        with open(path, "w", newline="") as f:
            f.write(payload)  # deliberately no final newline

        for target in (8, 9, 7):
            result = run_script(path, target)
            assert result.returncode == 0, (
                f"Script failed for randomized month {target}: {result.stderr}"
            )
            assert result.stderr == "", (
                f"Script wrote stderr for randomized month {target}: {result.stderr}"
            )
            actual = sorted(result.stdout.strip().splitlines()) if result.stdout.strip() else []
            assert actual == expected_lines(rows, target), (
                f"Incorrect aggregation for randomized month {target}: "
                f"expected {expected_lines(rows, target)}, got {actual}"
            )
    finally:
        os.unlink(path)


def test_header_only_file_has_no_output():
    fd, path = tempfile.mkstemp(prefix="header_only_", suffix=".csv")
    os.close(fd)
    try:
        with open(path, "w", newline="") as f:
            f.write("date,user_id,bytes\n")
        result = run_script(path, 8)
        assert result.returncode == 0, result.stderr
        assert result.stdout == ""
        assert result.stderr == ""
    finally:
        os.unlink(path)
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
