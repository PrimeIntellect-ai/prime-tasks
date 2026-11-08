#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shlex
import subprocess
import sys

import pytest

SCRIPT_PATH = "/home/user/parse.py"
OUTPUT_PATH = "/home/user/bot_changes.txt"
ARCHIVE_GLOB = "/home/user/archives/*.tar.gz"


def run_parser(changelog):
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        input=changelog,
        text=True,
        capture_output=True,
        timeout=5,
        cwd="/tmp",
    )
    assert result.returncode == 0, (
        f"parse.py exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout.splitlines()


def expected_paths(changelog):
    found = set()
    author = None
    modified = False
    record_paths = []

    for raw_line in changelog.splitlines():
        line = raw_line.strip()
        if line == "BEGIN_CHANGE":
            author = None
            modified = False
            record_paths = []
        elif line.startswith("Author:"):
            author = line.split(":", 1)[1].strip()
        elif line == "Modified:":
            modified = True
        elif line == "END_CHANGE":
            if author == "deploy_bot":
                found.update(record_paths)
            author = None
            modified = False
            record_paths = []
        elif modified and line:
            record_paths.append(line)

    return sorted(found)


def find_valid_archive():
    valid = []
    for archive in sorted(glob.glob(ARCHIVE_GLOB)):
        result = subprocess.run(
            ["tar", "-tzf", archive],
            text=True,
            capture_output=True,
            timeout=5,
        )
        if result.returncode == 0:
            members = result.stdout.splitlines()
            changelogs = [m for m in members if m == "changelog.txt" or m == "./changelog.txt"]
            if len(changelogs) == 1:
                valid.append((archive, changelogs[0]))

    assert len(valid) == 1, f"Expected exactly one readable archive containing changelog.txt, found: {valid}"
    return valid[0]


def test_parse_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_parse_script_processes_dynamic_stdin():
    token = secrets.token_hex(12)
    paths = [
        f"/srv/{token}/z-last.conf",
        f"/etc/{token}/a-first.conf",
        f"/opt/{token}/middle.yaml",
    ]
    decoy = f"/var/{token}/not-from-bot.log"

    changelog = f"""BEGIN_CHANGE
Author: admin
Date: 2026-01-01
Modified:
  {decoy}
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot
Date: 2026-01-02
Modified:
  {paths[0]}
  {paths[1]}
  {paths[0]}
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot_extra
Date: 2026-01-03
Modified:
  {decoy}
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot
Date: 2026-01-04
Modified:
  {paths[2]}
  {paths[1]}
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot
Date: 2026-01-05
Modified:
END_CHANGE
"""

    assert run_parser(changelog) == sorted(set(paths))


def test_valid_archive_can_be_piped_to_parser():
    archive, member = find_valid_archive()
    extracted = subprocess.run(
        ["tar", "-xOzf", archive, member],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert extracted.returncode == 0, extracted.stderr
    expected = expected_paths(extracted.stdout)

    command = (
        "set -o pipefail; "
        f"tar -xOzf {shlex.quote(archive)} {shlex.quote(member)} | "
        f"{shlex.quote(sys.executable)} {shlex.quote(SCRIPT_PATH)}"
    )
    pipeline = subprocess.run(
        ["bash", "-c", command],
        text=True,
        capture_output=True,
        timeout=10,
        cwd="/tmp",
    )
    assert pipeline.returncode == 0, (
        f"Archive-to-parser pipeline failed with status {pipeline.returncode}.\n"
        f"stderr:\n{pipeline.stderr}"
    )
    assert pipeline.stdout.splitlines() == expected


def test_bot_changes_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."

    expected_lines = [
        "/etc/cron.d/backup",
        "/etc/nginx/nginx.conf",
        "/etc/redis/redis.conf",
        "/opt/app/config.yaml"
    ]

    with open(OUTPUT_PATH, "r") as f:
        content = f.read()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {OUTPUT_PATH} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
