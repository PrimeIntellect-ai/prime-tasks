#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest

WORKSPACE = "/home/user/workspace"
SOURCE = os.path.join(WORKSPACE, "config_analyzer.c")
INPUT_LOG = os.path.join(WORKSPACE, "config_changes.log")
EXECUTABLE = "/tmp/config_analyzer_test"

EXPECTED_CONTENT = """Date,FilePath,TotalChanges,NetSizeDiff
2023-10-14,/etc/hosts,1,20
2023-10-14,/etc/nginx/nginx.conf,2,60
2023-10-14,/etc/ssh/sshd_config,1,-1200
2023-10-15,/etc/hosts,1,-5
2023-10-15,/etc/nginx/nginx.conf,1,-20
2023-10-15,/etc/sudoers,1,10
2023-10-16,/etc/passwd,1,80
"""


def normalized_lines(text):
    return [line.strip() for line in text.strip().splitlines()]


def run_analyzer(input_path, output_path):
    result = subprocess.run(
        [EXECUTABLE, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"config_analyzer exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), "The analyzer did not create its requested output file."
    with open(output_path, "r", newline="") as f:
        return f.read()


def expected_csv(events):
    aggregates = {}
    for date, path, diff in events:
        key = (date, path)
        count, total = aggregates.get(key, (0, 0))
        aggregates[key] = (count + 1, total + diff)

    lines = ["Date,FilePath,TotalChanges,NetSizeDiff"]
    for date, path in sorted(aggregates):
        count, total = aggregates[(date, path)]
        lines.append(f"{date},{path},{count},{total}")
    return "\n".join(lines) + "\n"


@pytest.fixture(scope="session", autouse=True)
def compile_program():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"config_analyzer.c failed to compile. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(EXECUTABLE)


def test_workspace_exists():
    assert os.path.exists(WORKSPACE), "/home/user/workspace directory does not exist."
    assert os.path.isdir(WORKSPACE), "/home/user/workspace is not a directory."


def test_c_program_exists():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_report_csv_exists_and_content():
    report_file = os.path.join(WORKSPACE, "report.csv")
    assert os.path.exists(report_file), f"{report_file} does not exist."
    assert os.path.isfile(report_file), f"{report_file} is not a file."

    with open(report_file, "r") as f:
        actual_content = f.read()

    assert normalized_lines(actual_content) == normalized_lines(EXPECTED_CONTENT), (
        "The content of report.csv does not match the expected output."
    )


def test_program_processes_extracted_log():
    assert os.path.isfile(INPUT_LOG), "The staging archive was not extracted into the workspace."
    with tempfile.TemporaryDirectory() as directory:
        output_path = os.path.join(directory, "report.csv")
        actual = run_analyzer(INPUT_LOG, output_path)
    assert normalized_lines(actual) == normalized_lines(EXPECTED_CONTENT)


def test_program_parses_aggregates_sorts_and_rejects_malformed_lines():
    token = secrets.token_hex(5)
    paths = [
        f"/etc/{token}/alpha.conf",
        f"/opt/{token}/zeta.cfg",
        f"/srv/{token}/middle.ini",
        f"/var/lib/{token}/state",
    ]
    dates = ["2024-01-03", "2023-12-29", "2024-01-01"]
    diffs = [17, -8, 0, 41, -19, 6, -3]
    actions = ["MODIFIED", "CREATED", "DELETED"]
    users = ["admin", "deploy", "system"]

    events = []
    valid_lines = []
    for index in range(57):
        date = dates[(index * 5 + 1) % len(dates)]
        path = paths[(index * 7 + 2) % len(paths)]
        diff = diffs[(index * 11 + 3) % len(diffs)]
        hour = (index * 3) % 24
        minute = (index * 13) % 60
        second = (index * 17) % 60
        timestamp = f"{date}T{hour:02d}:{minute:02d}:{second:02d}Z"
        diff_text = f"+{diff}" if diff > 0 else str(diff)
        valid_lines.append(
            f"[{timestamp}] [{users[index % len(users)]}] [{path}] "
            f"[{actions[index % len(actions)]}] [{diff_text}]"
        )
        events.append((date, path, diff))

    malformed = [
        "This is not a log entry.",
        "[2024-01-01T00:00:00Z] [admin] [/should/not/count] [MODIFIED]",
        "2024-01-01T00:00:00Z [admin] [/should/not/count] [MODIFIED] [+900]",
        "[2024-01-01T00:00:00Z] [admin] [/should/not/count] [MODIFIED] [+900] trailing",
        "[2024-01-01T00:00:00] [admin] [/should/not/count] [MODIFIED] [+900]",
        "[2024-01-01T00:00:00Z] [admin] [/should/not/count] [MODIFIED] [+9x]",
        "[2024-01-01T00:00:00Z] [admin] [/should/not/count] [MODIFIED] [+900] [EXTRA]",
        "[] [admin] [/should/not/count] [MODIFIED] [+900]",
    ]

    # Interleave malformed records with valid records and reverse the input so
    # output order must be produced by the analyzer rather than inherited.
    input_lines = list(reversed(valid_lines))
    for index, bad_line in enumerate(malformed):
        input_lines.insert((index * 7) % (len(input_lines) + 1), bad_line)

    with tempfile.TemporaryDirectory() as directory:
        input_path = os.path.join(directory, "synthetic.log")
        output_path = os.path.join(directory, "synthetic.csv")
        with open(input_path, "w", newline="\n") as f:
            f.write("\n".join(input_lines) + "\n")
        actual = run_analyzer(input_path, output_path)

    assert normalized_lines(actual) == normalized_lines(expected_csv(events))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
