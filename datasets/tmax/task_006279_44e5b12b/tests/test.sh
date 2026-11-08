#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile

EXECUTABLE = "/home/user/bin/log_parser"
RAW_LOG = "/home/user/logs/raw_logs.jsonl"
CLEAN_LOG = "/home/user/logs/clean_messages.txt"


def make_challenge():
    token = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(12))
    messages = [
        f"Alpha {token.upper()}!",
        f"ALPHA {token.lower()}!",
        f"Symbols #And-{token}?",
    ]

    def unicode_escape(text, offset):
        return "".join(
            f"\\u{ord(ch):04x}" if (i + offset) % 2 == 0 else ch
            for i, ch in enumerate(text)
        )

    lines = [
        '{"level": "info", "message": "' + unicode_escape(message, i) + '"}'
        for i, message in enumerate(messages)
    ]
    expected = {message.lower() for message in messages}
    return ("\n".join(lines) + "\n").encode(), expected


def normalized_lines(data):
    return [line.strip() for line in data.splitlines() if line.strip()]


def assert_deduplicated_output(data, expected):
    lines = normalized_lines(data)
    assert set(lines) == expected, f"Expected {expected}, but got {set(lines)}"
    assert len(lines) == len(expected), "Output contains duplicate lines or an incorrect number of lines."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_clean_messages_output():
    assert os.path.isfile(CLEAN_LOG), f"Output file {CLEAN_LOG} is missing."

    with open(CLEAN_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "user admin logged in!",
        "database connection reset",
        "cache miss for key 123",
    }
    actual_lines = set(lines)

    assert actual_lines == expected_lines, f"Expected {expected_lines}, but got {actual_lines}"
    assert len(lines) == len(expected_lines), "Output contains duplicate lines or incorrect number of lines."


def test_executable_processes_unseen_input():
    challenge, expected = make_challenge()
    with tempfile.NamedTemporaryFile(mode="wb", suffix=".jsonl", delete=False) as f:
        f.write(challenge)
        input_path = f.name

    try:
        result = subprocess.run(
            [EXECUTABLE, input_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"log_parser failed: {result.stderr}"
        assert_deduplicated_output(result.stdout, expected)
    finally:
        os.unlink(input_path)


def test_cron_job_scheduled_and_runs_required_pipeline():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        crontab_content = ""

    cron_lines = [
        line.strip() for line in crontab_content.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]

    commands = []
    for line in cron_lines:
        parts = line.split(None, 5)
        if len(parts) < 6:
            continue
        minute, hour, dom, mon, dow, command = parts
        if (minute, hour, dom, mon, dow) != ("0", "2", "*", "*", "*"):
            continue

        # Preserve the original cron assertion while also behaviorally testing it.
        if (
            ("raw_logs.jsonl" in line and "clean_messages.txt" in line)
            or "log_parser" in line
            or ".sh" in line
        ):
            commands.append(command)

    assert commands, "Could not find a valid cron job scheduled at 02:00 AM ('0 2 * * *') for the pipeline."

    challenge, expected = make_challenge()
    with open(RAW_LOG, "rb") as f:
        original_raw = f.read()
    clean_existed = os.path.exists(CLEAN_LOG)
    original_clean = None
    if clean_existed:
        with open(CLEAN_LOG, "rb") as f:
            original_clean = f.read()

    succeeded = False
    errors = []
    try:
        for command in commands:
            with open(RAW_LOG, "wb") as f:
                f.write(challenge)
            if os.path.exists(CLEAN_LOG):
                os.unlink(CLEAN_LOG)

            try:
                result = subprocess.run(
                    command,
                    shell=True,
                    executable="/bin/bash",
                    cwd="/home/user",
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                if result.returncode != 0:
                    errors.append(f"{command!r} exited {result.returncode}: {result.stderr}")
                    continue
                if not os.path.isfile(CLEAN_LOG):
                    errors.append(f"{command!r} did not create {CLEAN_LOG}")
                    continue
                with open(CLEAN_LOG, "r") as f:
                    output = f.read()
                try:
                    assert_deduplicated_output(output, expected)
                    succeeded = True
                    break
                except AssertionError as exc:
                    errors.append(f"{command!r}: {exc}")
            except subprocess.TimeoutExpired:
                errors.append(f"{command!r} timed out")
    finally:
        with open(RAW_LOG, "wb") as f:
            f.write(original_raw)
        if clean_existed:
            with open(CLEAN_LOG, "wb") as f:
                f.write(original_clean)
        elif os.path.exists(CLEAN_LOG):
            os.unlink(CLEAN_LOG)

    assert succeeded, "No 02:00 cron entry correctly processed the required input into the required output: " + "; ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
