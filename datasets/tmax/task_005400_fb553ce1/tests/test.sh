#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import random
import re
import secrets
import subprocess

GO_FILE = "/home/user/analyze.go"
LOG_FILE = "/home/user/app.log"
JSON_FILE = "/home/user/anomalies.json"
BINARY = "/tmp/submission_analyze"
ORIGINAL_EXPECTED = ["2023-10-01 10:00:25"]

HEADER_RE = re.compile(
    r"(?m)^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ([A-Z]+):"
)


def read_json_output():
    assert os.path.isfile(JSON_FILE), f"Expected JSON output file is missing at {JSON_FILE}"
    with open(JSON_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"The file {JSON_FILE} does not contain valid JSON: {exc}")
    assert isinstance(data, list), (
        f"Expected the JSON file to contain a list, but got {type(data).__name__}"
    )
    return data


def oracle(log_text):
    matches = list(HEADER_RE.finditer(log_text))
    entries = []
    for index, match in enumerate(matches):
        # All generated headers are real calendar timestamps. Validate them here
        # independently rather than trusting text embedded in an expected file.
        datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(log_text)
        message = log_text[match.end():end]
        if message.startswith(" "):
            message = message[1:]
        message = message.rstrip("\r\n")
        entries.append((match.group(1), len(message.encode("utf-8"))))

    anomalies = []
    window = []
    for timestamp, length in entries:
        if len(window) == 3 and length * 3 > 2 * sum(window):
            anomalies.append(timestamp)
        window.append(length)
        if len(window) > 3:
            window.pop(0)
    return anomalies


def run_submission(log_text):
    with open(LOG_FILE, "w", encoding="utf-8", newline="") as f:
        f.write(log_text)
    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled analyzer exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_json_output()
    expected = oracle(log_text)
    assert actual == expected, f"Expected anomalies list to be {expected}, but got {actual}"


def make_log(entries, final_newlines=1):
    blocks = []
    for timestamp, level, spacing, message in entries:
        blocks.append(f"[{timestamp}] {level}:" + spacing + message)
    return "\n".join(blocks) + ("\n" * final_newlines)


def test_complete_analyzer():
    # Preserve the original verifier's existence and exact-output assertions.
    assert os.path.isfile(GO_FILE), f"Expected Go source file is missing at {GO_FILE}"
    initial = read_json_output()
    assert initial == ORIGINAL_EXPECTED, (
        f"Expected anomalies list to be {ORIGINAL_EXPECTED}, but got {initial}"
    )

    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    with open(JSON_FILE, "rb") as f:
        original_json = f.read()

    build = subprocess.run(
        ["go", "build", "-o", BINARY, GO_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, (
        f"analyze.go did not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    try:
        # Execute the artifact against the supplied input as well as derived tests.
        run_submission(original_log.decode("utf-8"))
        assert read_json_output() == ORIGINAL_EXPECTED

        rng = random.Random(secrets.randbits(64))
        k = rng.randint(7, 19)
        strict_and_formatting = make_log([
            ("2024-04-03 11:01:00", "INFO", " ", "a" * k),
            ("2024-04-03 11:01:01", "WARN", " ", "b" * k),
            ("2024-04-03 11:01:02", "ERROR", " ", "c" * k),
            # Exactly twice the prior average: strict comparison means no anomaly.
            ("2024-04-03 11:01:03", "INFO", " ", "d" * (2 * k)),
            # Multiline UTF-8 message exercises byte length and rolling updates.
            ("2024-04-03 11:01:04", "WARN", " ",
             "long first line\nsecond line\n" + ("é" * (3 * k))),
            # Exactly one of two spaces after the colon must be retained.
            ("2024-04-03 11:01:05", "ERROR", "  ", "kept-space-" + "z" * k),
            # Newlines at the end of an entry block must not count.
            ("2024-04-03 11:01:06", "INFO", " ", "q" * k + "\n\n"),
            ("2024-04-03 11:01:07", "WARN", " ", "tail"),
        ], final_newlines=3)
        run_submission(strict_and_formatting)

        entries = []
        alphabet = "abcdefghijklmNOPQRSTUV"
        for i in range(12):
            timestamp = f"2025-07-08 09:02:{i:02d}"
            level = ("INFO", "WARN", "ERROR")[i % 3]
            size = rng.randint(3, 35)
            message = "".join(rng.choice(alphabet) for _ in range(size))
            if i in (4, 9):
                message += "\nembedded detail " + ("X" * rng.randint(70, 130))
            elif i == 6:
                message = "π" * rng.randint(8, 20) + "\ncontinuation"
            spacing = "  " if i == 7 else " "
            entries.append((timestamp, level, spacing, message))
        run_submission(make_log(entries, final_newlines=rng.randint(1, 4)))
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        with open(JSON_FILE, "wb") as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
