#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import csv
import stat
import secrets
import subprocess
import datetime
import calendar

SCRIPT_PATH = "/home/user/process.sh"
OUTPUT_PATH = "/home/user/cleaned_logs.csv"
LEGACY_PATH = "/home/user/data/legacy.csv"
APP_PATH = "/home/user/data/app.csv"


def parse_legacy_time(ts_str):
    dt = datetime.datetime.strptime(ts_str, "%Y/%m/%d %H:%M:%S")
    return calendar.timegm(dt.utctimetuple())


def parse_app_time(ts_str):
    dt = datetime.datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
    return calendar.timegm(dt.utctimetuple())


def process_row(row, time_parser):
    ts_str, name, email, ip, age_str, score_str = row

    try:
        age = int(age_str)
        score = int(score_str)
    except ValueError:
        return None

    if not (18 <= age <= 100):
        return None
    if not (0 <= score <= 1000):
        return None

    epoch = time_parser(ts_str)

    email_parts = email.split('@')
    if len(email_parts) == 2:
        masked_email = f"***@{email_parts[1]}"
    else:
        masked_email = email

    ip_parts = ip.split('.')
    if len(ip_parts) == 4:
        masked_ip = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}.0"
    else:
        masked_ip = ip

    return (epoch, masked_email, masked_ip, age, score)


def compute_expected_output():
    results = []

    if os.path.exists(LEGACY_PATH):
        with open(LEGACY_PATH, "r", encoding="iso-8859-1") as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) == 6:
                    processed = process_row(row, parse_legacy_time)
                    if processed:
                        results.append(processed)

    if os.path.exists(APP_PATH):
        with open(APP_PATH, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) == 6:
                    processed = process_row(row, parse_app_time)
                    if processed:
                        results.append(processed)

    results.sort(key=lambda x: x[0])
    return "\n".join(
        f"{epoch},{email},{ip},{age},{score}"
        for epoch, email, ip, age, score in results
    ) + "\n"


def normalized_lines(content):
    return [line.strip() for line in content.strip().splitlines()]


def assert_output_matches(expected_content):
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read()

    actual_lines = normalized_lines(actual_content)
    expected_lines = normalized_lines(expected_content)
    assert actual_lines == expected_lines, (
        "The content of /home/user/cleaned_logs.csv does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def check_script_artifact():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"The script {SCRIPT_PATH} is empty."

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax:\n{syntax.stderr}"

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        script_text = f.read()
    command_pattern = re.compile(
        r"(?:^|[;&|]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*"
        r"(?:(?:command|exec|env)\s+)*(?:/[^\s;|&]+/)?"
        r"(?:python(?:[0-9]+(?:\.[0-9]+)*)?|perl|ruby)\b",
        re.MULTILINE | re.IGNORECASE,
    )
    assert not command_pattern.search(script_text), (
        "process.sh must be pure Bash and standard CLI tools; Python, Perl, and Ruby are forbidden."
    )


def run_script():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    env = os.environ.copy()
    env["TZ"] = "UTC"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


ORIGINAL_EXPECTED = compute_expected_output()


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_script_executes_on_original_inputs():
    check_script_artifact()
    run_script()


def test_cleaned_logs_exists():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."


def test_cleaned_logs_content():
    assert_output_matches(ORIGINAL_EXPECTED)


def test_script_processes_unseen_inputs():
    token = secrets.token_hex(8)
    base = 1609459200 + secrets.randbelow(4 * 365 * 24 * 3600)

    def legacy_ts(offset):
        return datetime.datetime.fromtimestamp(base + offset, datetime.timezone.utc).strftime(
            "%Y/%m/%d %H:%M:%S"
        )

    def app_ts(offset):
        return datetime.datetime.fromtimestamp(base + offset, datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )

    legacy_rows = [
        [legacy_ts(7200), "André", f"alpha.{token}@legacy-{token}.example", "145.23.67.219", "37", "643"],
        [legacy_ts(60), "Zoë", f"edge.{token}@bounds.example", "10.22.33.44", "18", "0"],
        [legacy_ts(180), "InvalidAge", "badage@example.test", "1.2.3.4", "17", "500"],
        [legacy_ts(240), "InvalidScore", "badscore@example.test", "5.6.7.8", "50", "1001"],
    ]
    app_rows = [
        [app_ts(3600), "Mobile", f"mobile.{token}@app-{token}.example", "198.18.45.99", "64", "777"],
        [app_ts(30), "Boundary", f"top.{token}@upper.example", "203.0.113.254", "100", "1000"],
        [app_ts(120), "NotInteger", "textage@example.test", "9.8.7.6", "twenty", "10"],
        [app_ts(300), "Negative", "negative@example.test", "4.3.2.1", "30", "-1"],
    ]

    os.chmod("/home/user/data", 0o755)
    with open(LEGACY_PATH, "w", encoding="iso-8859-1", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(legacy_rows)
    with open(APP_PATH, "w", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(app_rows)

    os.chown(LEGACY_PATH, 0, 0)
    os.chown(APP_PATH, 0, 0)
    os.chmod(LEGACY_PATH, 0o444)
    os.chmod(APP_PATH, 0o444)

    expected = compute_expected_output()
    run_script()
    assert_output_matches(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
