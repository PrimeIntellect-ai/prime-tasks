#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import stat
import subprocess
import sys

import pytest

REPORT_PATH = "/home/user/report.json"
REPO_PATH = "/home/user/pipeline_repo"
AGGREGATOR_PATH = os.path.join(REPO_PATH, "aggregator.py")
DECODER_PATH = os.path.join(REPO_PATH, "bin", "decoder")


def run_aggregator(input_text):
    result = subprocess.run(
        [sys.executable, AGGREGATOR_PATH],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"aggregator.py exited with {result.returncode}: {result.stderr}"
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"aggregator.py did not emit valid JSON: {exc}; output={result.stdout!r}")


def historical_api_keys():
    git_base = [
        "/usr/bin/git",
        "-c",
        f"safe.directory={REPO_PATH}",
        "-C",
        REPO_PATH,
    ]
    result = subprocess.run(
        git_base + ["rev-list", "--all"],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Unable to inspect git history: {result.stderr}"

    keys = []
    for commit in result.stdout.splitlines():
        shown = subprocess.run(
            git_base + ["show", f"{commit}:config.ini"],
            text=True,
            capture_output=True,
            timeout=10,
        )
        if shown.returncode != 0:
            continue
        for line in shown.stdout.splitlines():
            match = re.fullmatch(r"API_KEY=(.+)", line.strip())
            if match and match.group(1) not in keys:
                keys.append(match.group(1))
    assert keys, "No API_KEY could be recovered from config.ini in git history."
    return keys


def decode_with_historical_key():
    base_env = os.environ.copy()
    base_env.pop("DECODER_SECRET_AUTH", None)

    unauthenticated = subprocess.run(
        [DECODER_PATH],
        text=True,
        capture_output=True,
        env=base_env,
        timeout=10,
    )
    assert unauthenticated.returncode != 0, "decoder unexpectedly succeeds without authentication."

    failures = []
    for key in historical_api_keys():
        env = base_env.copy()
        env["DECODER_SECRET_AUTH"] = key
        result = subprocess.run(
            [DECODER_PATH],
            text=True,
            capture_output=True,
            env=env,
            timeout=10,
        )
        if result.returncode == 0:
            return result.stdout
        failures.append(result.stderr)

    pytest.fail(f"decoder rejected every API key recovered from git history: {failures}")


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The final report file {REPORT_PATH} is missing."


def test_report_content():
    assert os.path.isfile(REPORT_PATH), f"Cannot verify content because {REPORT_PATH} does not exist."

    try:
        with open(REPORT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_data = {
        "INFO": 2,
        "ERROR": 1,
        "CRITICAL": 1
    }

    assert data == expected_data, f"The aggregated counts in {REPORT_PATH} are incorrect. Expected {expected_data}, got {data}."
    assert all(type(value) is int for value in data.values()), "Report counts must be integers."


def test_aggregator_handles_unexpected_extra_fields():
    assert os.path.exists(AGGREGATOR_PATH), "aggregator.py is missing."
    mode = os.stat(AGGREGATOR_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), "aggregator.py must be a regular file."

    levels = [f"LEVEL_{secrets.token_hex(6).upper()}" for _ in range(5)]
    expected = {}
    lines = []
    for index, level in enumerate(levels):
        count = random.randint(2, 5)
        expected[level] = count
        for item in range(count):
            fields = [level, f"2026-09-{index + 1:02d}", f"message-{item}"]
            if item % 2 == 0:
                fields.extend(f"extra-{n}" for n in range(1, random.randint(2, 5)))
            lines.append("|".join(fields))
    random.SystemRandom().shuffle(lines)

    actual = run_aggregator("\n" + "\n".join(lines) + "\n\n")
    assert actual == expected, (
        "aggregator.py must count the first field and tolerate additional delimited fields; "
        f"expected {expected}, got {actual}."
    )
    assert all(type(value) is int for value in actual.values())


def test_historical_key_decoder_and_fresh_pipeline_output():
    assert os.path.isfile(DECODER_PATH), "The decoder binary is missing."
    assert os.access(DECODER_PATH, os.X_OK), "The decoder binary is not executable."

    decoded = decode_with_historical_key()
    decoded_lines = [line.strip() for line in decoded.splitlines() if line.strip()]
    assert decoded_lines, "Authenticated decoder produced no log records."
    assert any(len(line.split("|")) > 3 for line in decoded_lines), (
        "Decoder output does not contain the extra-delimiter edge case."
    )

    expected = {}
    for line in decoded_lines:
        level = line.split("|", 1)[0]
        expected[level] = expected.get(level, 0) + 1

    fresh_result = run_aggregator(decoded)
    assert fresh_result == expected, (
        f"Fresh decoder-to-aggregator output is incorrect: expected {expected}, got {fresh_result}."
    )

    with open(REPORT_PATH, "r") as report_file:
        report = json.load(report_file)
    assert report == fresh_result, (
        f"report.json does not match a fresh authenticated pipeline run: "
        f"report={report}, pipeline={fresh_result}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
