#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from datetime import datetime, timezone

import pytest

REPO = "/home/user/monitor_src"
SOURCE = os.path.join(REPO, "monitor.cpp")
HOOK = os.path.join(REPO, ".git/hooks/post-commit")
BINARY = os.path.join(REPO, "monitor_run")
LOG_DIR = "/home/user/monitoring_logs"
LOG_PATH = os.path.join(LOG_DIR, "uptime.log")


def get_expected_fstab_count():
    if not os.path.exists("/etc/fstab"):
        return 0
    with open("/etc/fstab", "r") as f:
        lines = f.readlines()

    count = 0
    for line in lines:
        line = line.strip()
        if line and not line.startswith("#"):
            count += 1
    return count


def parse_log_line(line, expected_count):
    pattern = r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] FSTAB_ENTRIES: (\d+)$"
    match = re.match(pattern, line.strip())
    assert match is not None, f"Log line does not match expected format: '{line}'"
    time_str, count_str = match.groups()
    assert int(count_str) == expected_count, (
        f"Expected {expected_count} FSTAB_ENTRIES, but found {count_str}."
    )
    log_time = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    time_diff = abs((datetime.now(timezone.utc) - log_time).total_seconds())
    assert time_diff < 300, f"Logged time {time_str} is not current UTC time."


def run_checked(command, *, env=None, cwd=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_00_submission_and_live_hook_execution():
    assert os.path.isfile(SOURCE), f"Missing source file {SOURCE}"
    assert os.path.isfile(HOOK), f"Missing hook file {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Hook file {HOOK} is not executable."

    # monitor.cpp must be changed, committed, and present in HEAD rather than only
    # edited in the working tree.
    commits = run_checked(
        ["git", "-C", REPO, "rev-list", "HEAD", "--", "monitor.cpp"]
    ).stdout.splitlines()
    assert len(commits) >= 2, "Changes to monitor.cpp were not committed."
    clean_source = subprocess.run(
        ["git", "-C", REPO, "diff", "--quiet", "HEAD", "--", "monitor.cpp"],
        timeout=10,
    )
    assert clean_source.returncode == 0, "monitor.cpp has uncommitted changes."

    with open(HOOK, "r", encoding="utf-8", errors="replace") as f:
        hook_lines = f.readlines()
    active_hook_lines = [line.split("#", 1)[0].strip() for line in hook_lines]
    tz_assignment = re.compile(
        r"^(?:export\s+)?TZ\s*=\s*(?:UTC|'UTC'|\"UTC\")(?:\s|;|$)"
    )
    assert any(tz_assignment.search(line) for line in active_hook_lines), (
        "The hook does not explicitly set TZ=UTC."
    )

    fstab_existed = os.path.exists("/etc/fstab")
    old_fstab = b""
    if fstab_existed:
        with open("/etc/fstab", "rb") as f:
            old_fstab = f.read()

    os.makedirs(LOG_DIR, exist_ok=True)
    expected = 2 + secrets.randbelow(7)
    nonce = secrets.token_hex(8)
    generated = ["", "# generated verifier comment", "   # indented comment"]
    generated.extend(
        f"/dev/verifier_{nonce}_{i} /mnt/{nonce}_{i} ext4 defaults 0 0"
        for i in range(expected)
    )

    try:
        with open("/etc/fstab", "w") as f:
            f.write("\n".join(generated) + "\n")
        with open(LOG_PATH, "w"):
            pass
        if os.path.lexists(BINARY):
            os.unlink(BINARY)

        # Trigger the actual post-commit hook from outside the repository, with a
        # hostile inherited timezone and a small standard PATH.
        env = os.environ.copy()
        env.update({"TZ": "UTC+11", "PATH": "/usr/bin:/bin"})
        run_checked(
            ["git", "--git-dir", os.path.join(REPO, ".git"),
             "--work-tree", REPO, "commit", "--allow-empty",
             "-m", "verifier live hook check"],
            env=env,
            cwd="/tmp",
        )

        assert os.path.isfile(BINARY), "The hook did not compile monitor_run."
        assert os.access(BINARY, os.X_OK), "monitor_run is not executable."
        with open(LOG_PATH, "r") as f:
            hook_lines_out = f.read().splitlines()
        assert len(hook_lines_out) == 1, (
            "A single hook invocation must append exactly one log line."
        )
        parse_log_line(hook_lines_out[0], expected)

        # Execute the produced program independently with a different absolute
        # output path, proving that monitor.cpp implements the argument-driven
        # behavior rather than the hook merely manufacturing the expected log.
        second_expected = 1 + secrets.randbelow(5)
        with open("/etc/fstab", "w") as f:
            for i in range(second_expected):
                f.write(f"server:{nonce}{i} /srv/{i} nfs defaults 0 0\n")
            f.write("# ignored\n\n")
        alternate_log = f"/tmp/monitor-verifier-{secrets.token_hex(8)}.log"
        with open(alternate_log, "w") as f:
            f.write("sentinel\n")
        direct_env = os.environ.copy()
        direct_env["TZ"] = "UTC"
        run_checked([BINARY, alternate_log], env=direct_env, cwd="/tmp")
        with open(alternate_log, "r") as f:
            alternate_lines = f.read().splitlines()
        assert alternate_lines[0] == "sentinel", "monitor_run did not append to its output file."
        assert len(alternate_lines) == 2, "monitor_run must append exactly one line per execution."
        parse_log_line(alternate_lines[1], second_expected)
        os.unlink(alternate_log)
    finally:
        if fstab_existed:
            with open("/etc/fstab", "wb") as f:
                f.write(old_fstab)
        elif os.path.exists("/etc/fstab"):
            os.unlink("/etc/fstab")

        # Leave a fresh line matching the restored system fstab for the original
        # final-state assertions below.
        if os.path.isfile(BINARY) and os.access(BINARY, os.X_OK):
            with open(LOG_PATH, "w"):
                pass
            cleanup_env = os.environ.copy()
            cleanup_env["TZ"] = "UTC"
            subprocess.run([BINARY, LOG_PATH], env=cleanup_env, timeout=30)


def test_monitoring_log_exists():
    log_path = "/home/user/monitoring_logs/uptime.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did the hook run and create it?"


def test_monitoring_log_format_and_content():
    log_path = "/home/user/monitoring_logs/uptime.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"Log file {log_path} is empty."

    last_line = lines[-1].strip()

    # Regex to match: [YYYY-MM-DD HH:MM:SS UTC] FSTAB_ENTRIES: <count>
    pattern = r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] FSTAB_ENTRIES: (\d+)$"
    match = re.match(pattern, last_line)

    assert match is not None, f"Last line in log does not match expected format: '{last_line}'"

    time_str, count_str = match.groups()

    # Check count
    expected_count = get_expected_fstab_count()
    assert int(count_str) == expected_count, f"Expected {expected_count} FSTAB_ENTRIES, but found {count_str}."

    # Check time (should be close to current UTC time)
    log_time = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    current_time = datetime.now(timezone.utc)

    time_diff = abs((current_time - log_time).total_seconds())
    assert time_diff < 3600, f"Logged time {time_str} is not close to current UTC time. Make sure TZ=UTC was used."


def test_post_commit_hook_executable():
    hook_path = "/home/user/monitor_src/.git/hooks/post-commit"
    assert os.path.isfile(hook_path), f"Hook file {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Hook file {hook_path} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
