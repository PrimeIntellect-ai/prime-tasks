#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import datetime
import json
import os
import re
import subprocess

SCRIPT_PATH = "/home/user/etl_pipeline.py"
OUTPUT_PATH = "/home/user/output/region_stats.json"
USERS_PATH = "/home/user/data/users.csv"
MESSAGES_PATH = "/home/user/data/messages.csv"
BACKUP_PATH = "/home/user/cron_backup.txt"
CRON_PATTERN = r"0\s+2\s+\*\s+\*\s+\*\s+python3\s+/home/user/etl_pipeline\.py"


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {OUTPUT_PATH} does not contain valid JSON."


def assert_stats(data, expected):
    assert isinstance(data, dict), "Output JSON must contain an object."
    assert set(data.keys()) == set(expected.keys()), (
        f"Keys in JSON do not match expected regions. Got {list(data.keys())}"
    )
    for region, expected_val in expected.items():
        val = data[region]
        assert isinstance(val, (int, float)) and not isinstance(val, bool), (
            f"Value for {region} is not a number."
        )
        assert abs(val - expected_val) < 0.01, (
            f"Average word count for {region} is incorrect. "
            f"Expected {expected_val}, got {val}"
        )


def test_output_json_exists_and_correct():
    expected = {"NA": 5.0, "EU": 3.0, "APAC": 2.0}
    assert_stats(load_output(), expected)


def test_cron_backup_exists_and_correct():
    assert os.path.isfile(BACKUP_PATH), f"Cron backup file {BACKUP_PATH} does not exist."
    with open(BACKUP_PATH, "r") as f:
        content = f.read().strip()
    assert re.search(CRON_PATTERN, content) is not None, (
        f"Cron backup does not contain the correct cron schedule and command. Got: {content}"
    )


def test_etl_script_exists_and_uses_multiprocessing():
    assert os.path.isfile(SCRIPT_PATH), f"ETL script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "multiprocessing" in content or "Pool" in content, (
        "ETL script does not appear to use the multiprocessing module."
    )

    try:
        tree = ast.parse(content, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        assert False, f"ETL script is not valid Python: {exc}"

    imports_multiprocessing = any(
        (isinstance(node, ast.Import) and
         any(alias.name == "multiprocessing" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "multiprocessing")
        for node in ast.walk(tree)
    )
    uses_process_worker = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Name) and node.func.id in {"Pool", "Process"})
            or (isinstance(node.func, ast.Attribute) and node.func.attr in {"Pool", "Process"})
        )
        for node in ast.walk(tree)
    )
    assert imports_multiprocessing, "ETL script must import the multiprocessing module."
    assert uses_process_worker, "ETL script must create multiprocessing workers, such as Pool or Process."


def test_cron_job_is_actually_installed_and_backup_matches():
    result = subprocess.run(
        ["crontab", "-u", "user", "-l"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"No active crontab is installed for user: {result.stderr}"
    active = result.stdout.strip()
    assert re.search(CRON_PATTERN, active) is not None, (
        f"The active user crontab lacks the required job. Got: {active}"
    )
    with open(BACKUP_PATH, "r") as f:
        backup = f.read().strip()
    assert backup == active, "cron_backup.txt is not a copy of the active user crontab."


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def derive_expected(users, messages):
    regions = {str(row["user_id"]): row["region"] for row in users}
    counts = {}
    for row in messages:
        text = row["message_text"]
        timestamp = row["timestamp"]
        if not text or not text.strip():
            continue
        if re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", timestamp) is None:
            continue
        try:
            datetime.datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        region = regions.get(str(row["user_id"]))
        if region is None:
            continue
        counts.setdefault(region, []).append(len(text.split()))
    return {region: round(sum(values) / len(values), 2) for region, values in counts.items()}


def run_case(users, messages):
    write_csv(USERS_PATH, ["user_id", "region", "account_type"], users)
    write_csv(
        MESSAGES_PATH,
        ["msg_id", "user_id", "timestamp", "message_text"],
        messages,
    )
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    assert result.returncode == 0, (
        f"ETL script failed when executed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), "Executing the ETL script did not create region_stats.json."
    assert_stats(load_output(), derive_expected(users, messages))


def test_pipeline_executes_and_recomputes_from_csv_inputs():
    users1 = [
        {"user_id": "10", "region": "North", "account_type": "free"},
        {"user_id": "11", "region": "North", "account_type": "premium"},
        {"user_id": "12", "region": "South", "account_type": "free"},
        {"user_id": "13", "region": "West", "account_type": "premium"},
    ]
    messages1 = [
        {"msg_id": "201", "user_id": "10", "timestamp": "2025-01-02 03:04:05", "message_text": "one two"},
        {"msg_id": "202", "user_id": "11", "timestamp": "2025-01-02 03:05:06", "message_text": "alpha beta gamma delta epsilon"},
        {"msg_id": "203", "user_id": "12", "timestamp": "2025-01-02 03:06:07", "message_text": "   \t"},
        {"msg_id": "204", "user_id": "12", "timestamp": "2025-1-02 03:06:07", "message_text": "must be dropped"},
        {"msg_id": "205", "user_id": "13", "timestamp": "2025-01-02 03:07:08", "message_text": "single"},
        {"msg_id": "206", "user_id": "999", "timestamp": "2025-01-02 03:08:09", "message_text": "unmatched user row"},
    ]
    run_case(users1, messages1)

    users2 = [
        {"user_id": "21", "region": "Red", "account_type": "free"},
        {"user_id": "22", "region": "Blue", "account_type": "premium"},
        {"user_id": "23", "region": "Blue", "account_type": "free"},
    ]
    messages2 = [
        {"msg_id": "301", "user_id": "21", "timestamp": "2026-07-08 09:10:11", "message_text": "six words are counted in this sentence"},
        {"msg_id": "302", "user_id": "22", "timestamp": "2026-07-08 09:11:12", "message_text": "comma, inside text still has five"},
        {"msg_id": "303", "user_id": "23", "timestamp": "2026-07-08 09:12:13", "message_text": "two words"},
        {"msg_id": "304", "user_id": "21", "timestamp": "not-a-timestamp", "message_text": "ignore all of these words"},
        {"msg_id": "305", "user_id": "22", "timestamp": "2026-07-08T09:13:14", "message_text": "also ignored"},
    ]
    run_case(users2, messages2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
