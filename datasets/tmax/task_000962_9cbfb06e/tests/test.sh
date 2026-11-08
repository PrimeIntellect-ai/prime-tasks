#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import select
import secrets
import subprocess
import tempfile
import threading
import time
from decimal import Decimal

SCRIPT = "/home/user/migrate_v1_to_v2.sh"
SAMPLE_INPUT = "/home/user/v1_data.txt"
EXPECTED_SAMPLE = """id|name|calculated_value
1|Alice|7.00
2|Bob|3.33
3|Charlie|10.70
4|David|84.25
"""


def run_script(path, timeout=10):
    return subprocess.run(
        [SCRIPT, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )


def test_script_exists_and_is_executable_bash_script():
    assert os.path.isfile(SCRIPT), f"File missing or not regular: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"
    with open(SCRIPT, "rb") as f:
        first_line = f.readline(256)
    assert first_line.startswith(b"#!"), f"{SCRIPT} is missing a shebang"
    assert b"sh" in first_line.lower(), f"{SCRIPT} does not identify a shell interpreter"


def test_v2_data_correctness():
    v2_data_path = "/home/user/v2_data.txt"
    assert os.path.exists(v2_data_path), f"File missing: {v2_data_path}"

    expected_content = EXPECTED_SAMPLE
    with open(v2_data_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {v2_data_path} does not match the expected V2 output."


def test_script_reproduces_sample_output_on_stdout():
    result = run_script(SAMPLE_INPUT)
    assert result.returncode == 0, f"Script failed on sample input: {result.stderr}"
    assert result.stdout == EXPECTED_SAMPLE, "Script stdout is incorrect for the sample input"
    with open("/home/user/v2_data.txt", "r") as f:
        saved = f.read()
    assert result.stdout.strip() == saved.strip(), "Saved V2 data was not produced by the current script behavior"


def test_script_evaluates_unseen_expressions_and_uses_first_argument():
    rows = []
    expected = ["id|name|calculated_value"]
    for i in range(12):
        a = 11 + secrets.randbelow(88)
        b = 11 + secrets.randbelow(88)
        c = 2 + secrets.randbelow(8)
        d = 2 + secrets.randbelow(8)
        e = 11 + secrets.randbelow(88)
        a_text = f"{a // 10}.{a % 10}"
        b_text = f"{b // 10}.{b % 10}"
        e_text = f"{e // 10}.{e % 10}"
        expression = f"({a_text} + {b_text}) * {c} / {d} - {e_text}"
        value = (Decimal(a) / 10 + Decimal(b) / 10) * Decimal(c) / Decimal(d) - Decimal(e) / 10
        name = f"Dynamic User {i}"
        rows.append(f"{1000 + i}|{name}|{expression}")
        expected.append(f"{1000 + i}|{name}|{value:.2f}")

    data = "id|name|raw_math_formula\n" + "\n".join(rows) + "\n"
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="migration-input-", suffix=".txt") as f:
        f.write(data)
        input_path = f.name
    try:
        result = run_script(input_path)
    finally:
        os.unlink(input_path)

    assert result.returncode == 0, f"Script failed on alternate input: {result.stderr}"
    assert result.stdout == "\n".join(expected) + "\n", "Script failed unseen expression or argument-path tests"


def test_script_streams_before_input_reaches_eof():
    with tempfile.TemporaryDirectory() as directory:
        fifo = os.path.join(directory, "stream-input")
        os.mkfifo(fifo)
        allow_finish = threading.Event()
        writer_errors = []

        def writer():
            try:
                with open(fifo, "w") as f:
                    f.write("id|name|raw_math_formula\n")
                    f.write("91|Stream User|1.25 + 2 * 3\n")
                    f.flush()
                    if not allow_finish.wait(6):
                        return
                    f.write("92|Second|9 / 4\n")
                    f.flush()
            except Exception as exc:
                writer_errors.append(exc)

        thread = threading.Thread(target=writer, daemon=True)
        thread.start()
        proc = subprocess.Popen(
            ["stdbuf", "-oL", "-eL", SCRIPT, fifo],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        prefix = b""
        deadline = time.monotonic() + 5
        try:
            while prefix.count(b"\n") < 2:
                remaining = deadline - time.monotonic()
                assert remaining > 0, "Script did not emit migrated rows before input EOF; it appears to buffer the input"
                ready, _, _ = select.select([proc.stdout], [], [], remaining)
                assert ready, "Script did not emit migrated rows before input EOF; it appears to buffer the input"
                chunk = os.read(proc.stdout.fileno(), 4096)
                assert chunk, "Script exited before streaming the first data row"
                prefix += chunk

            assert prefix.startswith(b"id|name|calculated_value\n91|Stream User|7.25\n"), "Incorrect streaming output"
            allow_finish.set()
            remaining_out, stderr = proc.communicate(timeout=6)
            complete_output = prefix + remaining_out
            assert proc.returncode == 0, f"Streaming execution failed: {stderr.decode(errors='replace')}"
            assert complete_output == b"id|name|calculated_value\n91|Stream User|7.25\n92|Second|2.25\n"
            assert not writer_errors, f"FIFO writer failed: {writer_errors}"
        finally:
            allow_finish.set()
            if proc.poll() is None:
                proc.kill()
                proc.communicate()


def test_memory_profile_exists_and_valid():
    profile_path = "/home/user/memory_profile.txt"
    assert os.path.exists(profile_path), f"File missing: {profile_path}"

    with open(profile_path, "r") as f:
        content = f.read()

    assert "Maximum resident set size" in content, f"'{profile_path}' is missing 'Maximum resident set size' output from /usr/bin/time -v"
    assert "User time" in content, f"'{profile_path}' is missing 'User time' output from /usr/bin/time -v"
    assert "System time" in content, f"'{profile_path}' is missing 'System time' output from /usr/bin/time -v"
    command_lines = [line for line in content.splitlines() if "Command being timed:" in line]
    assert command_lines, f"'{profile_path}' is missing the command recorded by /usr/bin/time -v"
    command = command_lines[0]
    assert "migrate_v1_to_v2.sh" in command, "Profile does not identify the migration script as the timed command"
    assert "v1_data.txt" in command, "Profile does not identify the required sample input"
    assert re.search(r"Exit status:\s*0\s*$", content, re.MULTILINE), "Profile does not show a successful timed execution"

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
