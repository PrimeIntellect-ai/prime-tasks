#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import sqlite3
import subprocess

import pytest

HOME = "/home/user"
PIPELINE = "/home/user/pipeline.sh"
LOGS = "/home/user/data/logs.txt"
DB = "/home/user/data/enrichment.db"
OUTPUT = "/home/user/output.log"
FAILING = "/home/user/failing_line.txt"
EXPECTED_FAILING = "2023-10-25 192.168.1.99 O'Connor LOGIN"
USER_UID = pwd.getpwnam("user").pw_uid


def run_as_user(argv, timeout=30):
    return subprocess.run(
        ["runuser", "-u", "user", "--", *argv],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_failing_line_file():
    failing_line_path = FAILING
    assert os.path.isfile(failing_line_path), f"File {failing_line_path} does not exist."

    with open(failing_line_path, "r") as f:
        content = f.read().strip()

    expected_line = EXPECTED_FAILING
    assert content == expected_line, f"Expected {failing_line_path} to contain exactly '{expected_line}', but got '{content}'."
    assert os.stat(failing_line_path).st_uid == USER_UID, "failing_line.txt was not created by user."


def test_delta_debugging_script_was_written():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"data", ".cache", "__pycache__"}]
        for name in files:
            path = os.path.join(root, name)
            if path in {PIPELINE, FAILING, OUTPUT} or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            first = text.splitlines()[0] if text.splitlines() else ""
            is_script = name.endswith((".sh", ".bash", ".py")) or first.startswith("#!")
            if not is_script:
                continue
            lower = text.lower()
            references_inputs = "logs.txt" in lower and "pipeline.sh" in lower
            writes_result = "failing_line" in lower
            has_iteration = re.search(r"\b(for|while|until|ddmin)\b", lower) is not None
            executes_pipeline = re.search(r"subprocess|popen|os\.system|\bbash\b|\bsh\b|pipeline\.sh", lower) is not None
            if references_inputs and writes_result and has_iteration and executes_pipeline:
                candidates.append(path)

    assert candidates, (
        "No delta-debugging script was found. A script must exercise pipeline.sh on portions of "
        "logs.txt and save the isolated record to failing_line.txt."
    )
    assert any(os.stat(path).st_uid == USER_UID for path in candidates), (
        "The delta-debugging script was not written by the user user."
    )


def test_output_log_exists_and_line_count():
    logs_path = LOGS
    output_path = OUTPUT

    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the pipeline?"

    with open(logs_path, "r") as f:
        input_lines = f.readlines()

    with open(output_path, "r") as f:
        output_lines = f.readlines()

    assert len(output_lines) == len(input_lines), (
        f"Output log has {len(output_lines)} lines, but input log has {len(input_lines)} lines. "
        "The pipeline must process all lines."
    )


def test_output_log_contains_correct_entry():
    output_path = OUTPUT
    expected_output_line = "2023-10-25 192.168.1.99 O'Connor UNKNOWN LOGIN"

    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read()

    assert expected_output_line in content, (
        f"Could not find the correctly processed line '{expected_output_line}' in {output_path}. "
        "Ensure the pipeline correctly handles single quotes and defaults to 'UNKNOWN' role."
    )


def test_pipeline_is_an_executable_bash_script():
    assert os.path.isfile(PIPELINE), f"Script {PIPELINE} is missing."
    assert os.access(PIPELINE, os.X_OK), f"Script {PIPELINE} is not executable."
    assert os.stat(PIPELINE).st_uid == USER_UID, "pipeline.sh was not modified as the user user."
    with open(PIPELINE, "r", errors="strict") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!\s*(/usr/bin/env\s+)?(/bin/)?bash(?:\s|$)", first_line), (
        "pipeline.sh must be implemented as a Bash script."
    )
    assert not re.search(r"(^|[;&|]\s*)(python[0-9.]*|perl|ruby|node)\b", source, re.MULTILINE), (
        "The pipeline fix must be implemented strictly in Bash, not delegated to another language."
    )


def test_pipeline_runs_successfully():
    script_path = PIPELINE
    logs_path = LOGS

    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    result = run_as_user([script_path, logs_path])

    assert result.returncode == 0, (
        f"Pipeline script failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\n"
        f"Stderr: {result.stderr}"
    )


def test_all_provided_records_are_correctly_enriched():
    with open(LOGS, "r") as f:
        records = [line.rstrip("\n") for line in f]
    conn = sqlite3.connect(DB)
    try:
        expected = []
        for line in records:
            ts, ip, username, action = line.split()
            row = conn.execute("SELECT role FROM users WHERE username = ?", (username,)).fetchone()
            role = row[0] if row else "UNKNOWN"
            expected.append(f"{ts} {ip} {username} {role} {action}")
    finally:
        conn.close()

    with open(OUTPUT, "r") as f:
        actual = [line.rstrip("\n") for line in f]
    assert actual == expected, "output.log does not correctly enrich every input record in order."


def test_pipeline_on_unpredictable_quoted_and_database_backed_users():
    token = secrets.token_hex(10)
    quoted_user = f"qa_{token}'quoted"
    ordinary_user = f"qa_{token}_ordinary"
    absent_user = f"qa_{token}'absent"
    role1 = f"role_{secrets.token_hex(6)}"
    role2 = f"role_{secrets.token_hex(6)}"
    test_input = f"/home/user/.verifier_input_{token}.log"

    conn = sqlite3.connect(DB)
    try:
        conn.execute("INSERT INTO users(username, role) VALUES (?, ?)", (quoted_user, role1))
        conn.execute("INSERT INTO users(username, role) VALUES (?, ?)", (ordinary_user, role2))
        conn.commit()
    finally:
        conn.close()

    lines = [
        f"2026-09-12 10.9.0.1 {quoted_user} LOGIN",
        f"2026-09-12 10.9.0.2 {ordinary_user} QUERY",
        f"2026-09-12 10.9.0.3 {absent_user} LOGOUT",
    ]
    expected = [
        f"2026-09-12 10.9.0.1 {quoted_user} {role1} LOGIN",
        f"2026-09-12 10.9.0.2 {ordinary_user} {role2} QUERY",
        f"2026-09-12 10.9.0.3 {absent_user} UNKNOWN LOGOUT",
    ]

    try:
        with open(test_input, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.chown(test_input, USER_UID, pwd.getpwnam("user").pw_gid)

        result = run_as_user([PIPELINE, test_input])
        assert result.returncode == 0, (
            f"Pipeline failed on dynamically generated records.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(OUTPUT), "Pipeline did not create output.log for the dynamic input."
        with open(OUTPUT, "r") as f:
            actual = [line.rstrip("\n") for line in f]
        assert actual == expected, (
            "Pipeline did not safely query and enrich dynamically generated quoted, known, and unknown users."
        )
    finally:
        conn = sqlite3.connect(DB)
        try:
            conn.execute("DELETE FROM users WHERE username IN (?, ?)", (quoted_user, ordinary_user))
            conn.commit()
        finally:
            conn.close()
        try:
            os.remove(test_input)
        except FileNotFoundError:
            pass
        # Leave the required final artifact generated from the provided logs.
        run_as_user([PIPELINE, LOGS])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
