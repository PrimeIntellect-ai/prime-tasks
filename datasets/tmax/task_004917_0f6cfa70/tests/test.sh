#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import subprocess
from datetime import datetime

SCRIPT = "/home/user/analyze_logs.py"
LOG_DIR = "/home/user/logs"
REPORT = "/home/user/report.md"
ERROR = "/home/user/error.log"

VALID_AUTH = '''{"timestamp": "2024-01-01T00:00:00Z", "event": "login_failed", "ip": "192.0.2.10", "user": "ann"}
{"timestamp": "2024-01-01T00:00:10Z", "event": "login_success", "ip": "192.0.2.20", "user": "other"}
{"timestamp": "2024-01-01T00:00:20Z", "event": "login_failed", "ip": "192.0.2.30", "user": "bob"}
'''

VALID_API = '''timestamp,ip,endpoint,status
2023-12-31T23:59:55Z,192.0.2.10,/login,401
2024-01-01T00:00:00Z,192.0.2.10,/login,401
2024-01-01T00:00:05Z,192.0.2.10,/login,401
2024-01-01T00:00:06Z,192.0.2.10,/login,401
2024-01-01T00:00:15Z,192.0.2.30,/login,401
2024-01-01T00:00:25Z,192.0.2.30,/login,401
2024-01-01T00:00:26Z,192.0.2.30,/login,401
'''

VALID_DB = '''[31/Dec/2023:23:59:55 +0000] INFO: audit for user ann
[01/Jan/2024:00:00:05 +0000] ERROR: retry for user ann
[01/Jan/2024:00:00:06 +0000] WARN: outside window for user ann
[01/Jan/2024:00:00:20 +0000] INFO: unrelated operation
'''


def parse_iso_time(value):
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")


def parse_db_time(value):
    return datetime.strptime(value, "%d/%b/%Y:%H:%M:%S +0000")


def expected_report(auth_text, api_text, db_text):
    failed_logins = []
    for line in auth_text.splitlines():
        if line.strip():
            data = json.loads(line)
            if data.get("event") == "login_failed":
                failed_logins.append(data)

    api_requests = list(csv.DictReader(io.StringIO(api_text)))
    db_logs = []
    for line in db_text.splitlines():
        if not line.strip():
            continue
        time_part, rest = line.split("]", 1)
        db_logs.append({"time": time_part[1:], "msg": rest.strip()})

    lines = ["# Incident Report"]
    for login in failed_logins:
        auth_time = parse_iso_time(login["timestamp"])
        user = login["user"]
        ip = login["ip"]
        lines.extend([
            "",
            f"## Failed Login for user: {user} at {login['timestamp']}",
            f"- IP Address: {ip}",
        ])

        matched_api = 0
        for request in api_requests:
            if request["ip"] == ip:
                request_time = parse_iso_time(request["timestamp"])
                if abs((request_time - auth_time).total_seconds()) <= 5:
                    matched_api += 1
        lines.append(f"- Matched API Requests: {matched_api}")
        lines.append("- DB Logs:")

        matched_db = []
        for entry in db_logs:
            db_time = parse_db_time(entry["time"])
            if f"user {user}" in entry["msg"] and abs((db_time - auth_time).total_seconds()) <= 5:
                matched_db.append(entry["msg"])
        if matched_db:
            lines.extend(f"  - {message}" for message in matched_db)
        else:
            lines.append("  - None")

    return "\n".join(lines) + "\n"


def read_inputs():
    with open(os.path.join(LOG_DIR, "auth.jsonl")) as f:
        auth = f.read()
    with open(os.path.join(LOG_DIR, "api.csv")) as f:
        api = f.read()
    with open(os.path.join(LOG_DIR, "db.log")) as f:
        db = f.read()
    return auth, api, db


def assert_report_matches(expected):
    assert os.path.exists(REPORT), "The report.md file was not generated."
    assert not os.path.exists(ERROR), "An error.log was generated, but the logs were in chronological order."
    with open(REPORT) as f:
        actual = f.read()
    actual_lines = [line.strip() for line in actual.strip().split("\n")]
    expected_lines = [line.strip() for line in expected.strip().split("\n")]
    assert actual_lines == expected_lines, "The generated report.md does not match the expected recomputed output."


def write_inputs(auth=VALID_AUTH, api=VALID_API, db=VALID_DB):
    os.makedirs(LOG_DIR, exist_ok=True)
    for name, content in (("auth.jsonl", auth), ("api.csv", api), ("db.log", db)):
        with open(os.path.join(LOG_DIR, name), "w") as f:
            f.write(content)


def clear_outputs():
    for path in (REPORT, ERROR):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script():
    return subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def test_submission():
    assert os.path.isfile(SCRIPT), "The required /home/user/analyze_logs.py script does not exist."

    # Preserve the original final-state assertions against the agent's submitted files.
    assert os.path.exists(REPORT), "The report.md file was not generated."
    assert not os.path.exists(ERROR), "An error.log was generated, but the logs were in chronological order."
    original_auth, original_api, original_db = read_inputs()
    assert_report_matches(expected_report(original_auth, original_api, original_db))

    # Execute the submitted artifact on verifier-controlled valid input.
    clear_outputs()
    write_inputs()
    controlled_expected = expected_report(VALID_AUTH, VALID_API, VALID_DB)
    result = run_script()
    assert result.returncode == 0, f"Script failed on valid ordered logs: {result.stderr}"
    assert_report_matches(controlled_expected)

    # Exercise invalid ordering independently in every required input format.
    invalid_cases = {
        "auth.jsonl": (
            "\n".join([VALID_AUTH.splitlines()[1], VALID_AUTH.splitlines()[0], VALID_AUTH.splitlines()[2]]) + "\n",
            VALID_API,
            VALID_DB,
        ),
        "api.csv": (
            VALID_AUTH,
            "\n".join([VALID_API.splitlines()[0], VALID_API.splitlines()[2], VALID_API.splitlines()[1]] + VALID_API.splitlines()[3:]) + "\n",
            VALID_DB,
        ),
        "db.log": (
            VALID_AUTH,
            VALID_API,
            "\n".join([VALID_DB.splitlines()[1], VALID_DB.splitlines()[0]] + VALID_DB.splitlines()[2:]) + "\n",
        ),
    }

    for filename, inputs in invalid_cases.items():
        clear_outputs()
        write_inputs(*inputs)
        result = run_script()
        assert result.returncode == 1, f"Script did not exit with code 1 for invalid ordering in {filename}."
        assert os.path.isfile(ERROR), f"error.log was not generated for invalid ordering in {filename}."
        with open(ERROR) as f:
            error_text = f.read()
        assert error_text == f"ERROR: INVALID_ORDER {filename}", f"Incorrect error.log for {filename}."
        assert not os.path.exists(REPORT), f"report.md was generated despite invalid ordering in {filename}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
