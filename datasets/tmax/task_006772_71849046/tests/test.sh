#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import csv
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime, timedelta

SCRIPT = "/home/user/analyze_configs.py"
CONFIG_DIR = "/home/user/configs"
REPORT = "/home/user/similarity_report.csv"

EXPECTED_ORIGINAL = [
    ["timestamp1", "timestamp2", "jaccard_similarity"],
    ["2023-10-01T00", "2023-10-01T01", "1.0000"],
    ["2023-10-01T01", "2023-10-01T02", "0.2000"],
    ["2023-10-01T02", "2023-10-01T03", "1.0000"],
    ["2023-10-01T03", "2023-10-01T04", "1.0000"],
    ["2023-10-01T04", "2023-10-01T05", "0.5000"],
]


def read_report():
    assert os.path.isfile(REPORT), f"The report file {REPORT} does not exist."
    with open(REPORT, "r", newline="") as f:
        return list(csv.reader(f))


def assert_rows(actual, expected):
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} rows in the CSV, but found {len(actual)}."
    )
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f"Row {i + 1} does not match. Expected: {want}, Got: {got}"


def run_script():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"analyze_configs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return read_report()


def normalized_tokens(content):
    tokens = set()
    for line in content.splitlines():
        line = line.strip().lower()
        if line and not line.startswith("#"):
            tokens.add(line)
    return tokens


def expected_for_fixture(files):
    times = sorted(files)
    current = times[0]
    end = times[-1]
    available = {ts: normalized_tokens(content) for ts, content in files.items()}
    expanded = []
    last = None
    while current <= end:
        if current in available:
            last = available[current]
        expanded.append((current, last))
        current += timedelta(hours=1)

    rows = [["timestamp1", "timestamp2", "jaccard_similarity"]]
    for (t1, a), (t2, b) in zip(expanded, expanded[1:]):
        union = a | b
        similarity = 1.0 if not union else len(a & b) / len(union)
        rows.append([
            t1.strftime("%Y-%m-%dT%H"),
            t2.strftime("%Y-%m-%dT%H"),
            f"{similarity:.4f}",
        ])
    return rows


def install_fixture(files):
    if os.path.exists(CONFIG_DIR):
        shutil.rmtree(CONFIG_DIR)
    os.makedirs(CONFIG_DIR)
    for timestamp, content in files.items():
        name = "config_" + timestamp.strftime("%Y-%m-%dT%H") + ".txt"
        with open(os.path.join(CONFIG_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)


assert os.path.isfile(SCRIPT), f"The script {SCRIPT} was not created."
assert not os.path.islink(SCRIPT), "analyze_configs.py must be a real file, not a symlink."
assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), "analyze_configs.py is not a regular file."
assert os.path.getsize(SCRIPT) > 0, "analyze_configs.py is empty."

backup_root = tempfile.mkdtemp(prefix="config-verifier-")
backup_configs = os.path.join(backup_root, "configs")
shutil.copytree(CONFIG_DIR, backup_configs)
original_report = None

try:
    # Preserve the original exact fixture assertion, but require the submitted
    # script itself to regenerate the report.
    original_rows = run_script()
    assert_rows(original_rows, EXPECTED_ORIGINAL)
    with open(REPORT, "rb") as f:
        original_report = f.read()

    # Hidden fixture exercising gaps, normalization, duplicate removal,
    # comments, a nontrivial Jaccard value, and a transition to an empty set.
    start = datetime(2035, 1, 1, 23) + timedelta(days=secrets.randbelow(1200))
    fixture_one = {
        start: "  # ignored\n Key = Value \nDUP\n dup \n\n",
        start + timedelta(hours=2): "KEY = VALUE\n NewToken \n # comment\nnewtoken\n",
        start + timedelta(hours=5): "# comments only\n   \n",
    }
    install_fixture(fixture_one)
    assert_rows(run_script(), expected_for_fixture(fixture_one))

    # A separate fixture explicitly exercises the both-empty Jaccard rule and
    # forward filling across a date boundary.
    start2 = datetime(2042, 7, 18, 23) + timedelta(days=secrets.randbelow(300))
    fixture_two = {
        start2: " # empty configuration\n\n",
        start2 + timedelta(hours=2): " Alpha \nALPHA\n",
        start2 + timedelta(hours=4): "alpha\n Beta \n",
    }
    install_fixture(fixture_two)
    assert_rows(run_script(), expected_for_fixture(fixture_two))
finally:
    if os.path.exists(CONFIG_DIR):
        shutil.rmtree(CONFIG_DIR)
    shutil.copytree(backup_configs, CONFIG_DIR)
    if original_report is not None:
        with open(REPORT, "wb") as f:
            f.write(original_report)
    shutil.rmtree(backup_root, ignore_errors=True)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
