#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import re
import secrets
import subprocess
from datetime import datetime, timedelta

import pytest

REPORT_PATH = "/home/user/report.txt"
LOG_PATH = "/home/user/system_metrics.log"
START = datetime(2023, 10, 1, 10, 0, 0)
END = datetime(2023, 10, 1, 11, 45, 0)

EXPECTED_ORIGINAL = """Log Analysis Report
===================
Start Time: 2023-10-01 10:00:00
End Time: 2023-10-01 11:45:00
Total Resampled Intervals: 8
Max Value (after gap-filling): 56.00"""

ORIGINAL_LOG = """[2023-10-01 10:03:12] INFO Server started. METRIC_VAL: 42.5
[2023-10-01 10:12:01] DEBUG Checking connections.
[2023-10-01 10:14:30] WARN Minor spike. METRIC_VAL: 43.5
[2023-10-01 10:18:05] WARN High load detected. CPU_VAL: 99.0 METRIC_VAL: 55.2
[2023-10-01 10:25:00] INFO Still high load. METRIC_VAL: 56.8
[2023-10-01 11:02:11] ERROR Connection timeout. METRIC_VAL: 48.0
[2023-10-01 11:47:33] INFO Normal operations. METRIC_VAL: 30.1
"""

LINE_RE = re.compile(
    r"^\[([^\]]+)\].*?METRIC_VAL: ([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"
)


def expected_report(log_text):
    bins = {START + timedelta(minutes=15 * i): [] for i in range(8)}
    for line in log_text.splitlines():
        match = LINE_RE.search(line)
        if not match:
            continue
        try:
            timestamp = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
            value = float(match.group(2))
        except ValueError:
            continue
        if not START <= timestamp < END + timedelta(minutes=15):
            continue
        minutes = int((timestamp - START).total_seconds() // 60)
        bin_start = START + timedelta(minutes=(minutes // 15) * 15)
        bins[bin_start].append(value)

    values = []
    previous = None
    for bin_start in sorted(bins):
        if bins[bin_start]:
            previous = sum(bins[bin_start]) / len(bins[bin_start])
        assert previous is not None, "Generated test case unexpectedly has an empty first bin"
        values.append(previous)

    return """Log Analysis Report
===================
Start Time: 2023-10-01 10:00:00
End Time: 2023-10-01 11:45:00
Total Resampled Intervals: 8
Max Value (after gap-filling): {:.2f}""".format(max(values))


def generated_logs():
    x = secrets.randbelow(100000) / 10000.0
    first = f"""[2023-10-01 09:59:59] METRIC_VAL: 9999.0
[2023-10-01 10:00:01] alpha METRIC_VAL: {20 + x:.4f}
[2023-10-01 10:14:59] beta METRIC_VAL: {40 + x:.4f}
[2023-10-01 10:20:00] CPU_VAL: 777.0
[2023-10-01 10:30:00] gamma METRIC_VAL: {90 + x:.4f}
[2023-10-01 10:44:59] delta METRIC_VAL: {10 + x:.4f}
[2023-10-01 10:45:00] epsilon METRIC_VAL: {35 + x:.4f}
[2023-10-01 11:15:17] zeta METRIC_VAL: {60 + x:.4f}
prefix [2023-10-01 11:30:00] METRIC_VAL: 8888.0
[2023-10-01 11:45:00] eta METRIC_VAL: {55 + x:.4f}
[2023-10-01 12:00:00] METRIC_VAL: 9998.0
"""

    y = secrets.randbelow(100000) / 10000.0
    second = f"""[2023-10-01 10:00:00] boundary METRIC_VAL: {100 + y:.4f}
[2023-10-01 10:14:59] same-bin METRIC_VAL: {10 + y:.4f}
[2023-10-01 10:15:00] next-bin METRIC_VAL: {70 + y:.4f}
[2023-10-01 10:29:59] next-bin-two METRIC_VAL: {90 + y:.4f}
[2023-10-01 10:30:00] METRIC_VAL: {45 + y:.4f}
[2023-10-01 11:00:00] text METRIC_VAL: not-a-number
[2023-10-01 11:45:00] final METRIC_VAL: {75 + y:.4f}
[2023-10-01 11:59:59] final-bin-second METRIC_VAL: {65 + y:.4f}
"""
    return [first, second]


def candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            if not name.endswith(".py") or os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    ast.parse(handle.read(), filename=path)
            except (OSError, UnicodeError, SyntaxError):
                continue
            candidates.append(path)
    return sorted(candidates)


def run_script(path):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    return subprocess.run(
        ["python3", path],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote,
    )


def write_log(text):
    with open(LOG_PATH, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(LOG_PATH, 0o666)


def execute_and_check(path, log_text, expected):
    write_log(log_text)
    if os.path.lexists(REPORT_PATH):
        if os.path.isdir(REPORT_PATH) and not os.path.islink(REPORT_PATH):
            return False
        os.unlink(REPORT_PATH)
    try:
        result = run_script(path)
    except (OSError, subprocess.TimeoutExpired):
        return False
    if result.returncode != 0 or not os.path.isfile(REPORT_PATH):
        return False
    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as handle:
            return handle.read().strip() == expected
    except (OSError, UnicodeError):
        return False


def test_00_python_script_processes_log():
    candidates = candidate_scripts()
    assert candidates, "No Python script was found under /home/user."

    cases = [(text, expected_report(text)) for text in generated_logs()]
    selected = None
    for path in candidates:
        if all(execute_and_check(path, text, expected) for text, expected in cases):
            selected = path
            break

    assert selected is not None, (
        "No submitted Python script generated the correct report when executed "
        "against independently generated log inputs."
    )

    assert execute_and_check(selected, ORIGINAL_LOG, EXPECTED_ORIGINAL), (
        "The working script did not generate the required report for system_metrics.log."
    )


def test_report_exists():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"The file {report_path} does not exist. Your script did not generate the report."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."


def test_report_content():
    report_path = "/home/user/report.txt"
    expected_content = """Log Analysis Report
===================
Start Time: 2023-10-01 10:00:00
End Time: 2023-10-01 11:45:00
Total Resampled Intervals: 8
Max Value (after gap-filling): 56.00"""

    if not os.path.exists(report_path):
        pytest.fail(f"Cannot check content because {report_path} does not exist.")

    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {report_path} does not match the expected template and values. Found:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
