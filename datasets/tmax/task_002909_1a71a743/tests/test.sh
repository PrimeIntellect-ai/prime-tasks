#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import tarfile
from collections import Counter
from datetime import datetime
import pytest

ORIGINAL_APP_CONF = (
    b"# Application Config\n"
    b"log_level=debug\n"
    b"upstream_socket=/home/user/run/agregator.sock\n"
    b"timeout=30s\n"
)


def active_shell_lines(content):
    lines = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        line = re.sub(r"\s+#.*$", "", line).strip()
        if line:
            lines.append(line)
    return lines


def test_config_backup_exists_and_valid():
    backup_path = "/home/user/backups/config_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            # Preserve the original archive-content assertion.
            assert any(name.endswith("app.conf") for name in names), "app.conf not found in the backup tarball."

            app_members = [
                member for member in tar.getmembers()
                if member.name.endswith("app.conf") and member.isfile()
            ]
            assert app_members, "The backup does not contain a regular app.conf file."
            backed_up_contents = []
            for member in app_members:
                extracted = tar.extractfile(member)
                assert extracted is not None
                backed_up_contents.append(extracted.read())
            assert ORIGINAL_APP_CONF in backed_up_contents, (
                "The backup does not contain the original, unmodified app.conf."
            )
    except tarfile.ReadError:
        pytest.fail(f"Backup file {backup_path} is not a valid gzip-compressed tarball.")


def test_app_conf_fixed():
    conf_path = "/home/user/config/app.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."

    with open(conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "upstream_socket=/home/user/run/aggregator.sock" in content, "The upstream_socket path was not correctly fixed in app.conf."

    active_assignments = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"upstream_socket\s*=\s*(\S+)\s*(?:#.*)?", line)
        if match:
            active_assignments.append(match.group(1))
    assert active_assignments == ["/home/user/run/aggregator.sock"], (
        "app.conf must have exactly one active upstream_socket assignment with the corrected path."
    )


def test_supervisor_script_fixed():
    script_path = "/home/user/supervisor.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), "supervisor.sh is not executable."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "sleep 5" in content, "The supervisor.sh script does not contain 'sleep 5'."

    lines = active_shell_lines(content)
    assert "sleep 5" in lines, "sleep 5 must be an active shell command, not a comment or unrelated text."

    # Locate a while-loop body and ensure the delay controls that loop's restart:
    # either it is the final command before `done` (the canonical fix), or it is
    # directly before an active daemon invocation.
    valid_delay = False
    stack = []
    for index, line in enumerate(lines):
        if re.match(r"^while\b", line):
            stack.append(index)
        elif line == "done" and stack:
            start = stack.pop()
            body = lines[start + 1:index]
            for pos, command in enumerate(body):
                if command != "sleep 5":
                    continue
                if pos == len(body) - 1:
                    valid_delay = True
                elif re.fullmatch(r'(?:"?\$\{?DAEMON\}?"?|/home/user/bin/log_aggregator)(?:\s+.*)?', body[pos + 1]):
                    valid_delay = True
    assert valid_delay, (
        "An active 'sleep 5' must delay the daemon restart within the while loop."
    )


def test_dashboard_metrics():
    metrics_path = "/home/user/dashboard_metrics.txt"
    log_path = "/home/user/logs/error.log"
    assert os.path.isfile(metrics_path), f"Metrics file {metrics_path} is missing."
    assert os.path.isfile(log_path), f"Source log {log_path} is missing."

    expected_lines = [
        "[2023-10-25 14:01] - 3 errors",
        "[2023-10-25 14:02] - 2 errors",
        "[2023-10-25 14:04] - 1 errors"
    ]

    with open(metrics_path, "r", encoding="utf-8") as f:
        raw_metrics = f.read()
    actual_lines = [line.strip() for line in raw_metrics.splitlines() if line.strip()]

    # Preserve the original fixture assertion.
    assert actual_lines == expected_lines, f"Dashboard metrics do not match expected output. Got: {actual_lines}"

    counts = Counter()
    with open(log_path, "r", encoding="utf-8") as f:
        for line in f:
            if "Connection refused" not in line:
                continue
            match = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}):\d{2}\b", line)
            assert match, f"Connection-refused log line has no valid timestamp: {line.rstrip()}"
            minute = match.group(1)
            datetime.strptime(minute, "%Y-%m-%d %H:%M")
            counts[minute] += 1

    derived_lines = [f"[{minute}] - {counts[minute]} errors" for minute in sorted(counts)]
    assert actual_lines == derived_lines, (
        f"Dashboard metrics were not correctly derived from error.log. Expected {derived_lines}, got {actual_lines}"
    )
    assert raw_metrics == "\n".join(derived_lines) + "\n", (
        "dashboard_metrics.txt must contain exactly the required lines with no blank or extra lines."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
