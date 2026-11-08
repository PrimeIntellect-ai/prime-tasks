#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import re
import stat
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

CANONICAL_INPUT = """[2023-10-01 10:05:12] U001: Hello, my email is alice.smith@example.com and my phone is 555-123-4567.
[2023-10-01 10:06:00] U002: I need help with my account.
[2023-10-01 10:07:30] U001: Can you also update my secondary email to alice2@work.net?
[2023-10-01 10:08:15] U003: Call me at 999-888-7777 ASAP!
[2023-10-01 10:10:05] U002: Thanks, that fixed it.
[2023-10-01 10:12:00] U001: Great, thanks.
[2023-10-01 10:15:22] U003: Also my wife's number is 111-222-3333 and her email is wife@home.org.
"""


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    script = Path('/home/user/process_logs.py')
    assert script.exists(), f"Expected script {script} was not created."
    assert not script.is_symlink(), f"Expected {script} to be a regular Python file, not a symlink."
    assert stat.S_ISREG(script.stat().st_mode), f"Expected {script} to be a regular file."

    input_file = Path('/home/user/chat_logs.txt')
    input_file.write_text(CANONICAL_INPUT, encoding='utf-8')

    for output in ('/home/user/anonymized_logs.txt', '/home/user/user_stats.json'):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            ['runuser', '-u', 'user', '--', 'python3', str(script)],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {script} did not finish within 30 seconds.")

    assert result.returncode == 0, (
        f"Script {script} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert input_file.exists(), "The script removed /home/user/chat_logs.txt."
    assert input_file.read_text(encoding='utf-8') == CANONICAL_INPUT, (
        "The script modified /home/user/chat_logs.txt."
    )


def compute_expected():
    # Derive expectations from the verifier-owned canonical fixture rather than
    # from the agent-writable file.
    lines = io.StringIO(CANONICAL_INPUT).readlines()

    anonymized_lines = []
    stats = defaultdict(lambda: {"total_messages": 0, "total_words": 0, "total_pii_masked": 0})

    email_pattern = re.compile(r'\S+@\S+\.\S+')
    phone_pattern = re.compile(r'\d{3}-\d{3}-\d{4}')

    for line in lines:
        if not line.strip():
            continue

        match = re.match(r'^(\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]) ([^:]+): (.*)$', line)
        if not match:
            anonymized_lines.append(line)
            continue

        timestamp, user_id, message = match.groups()

        word_count = len(message.split())
        emails = email_pattern.findall(message)
        phones = phone_pattern.findall(message)
        pii_count = len(emails) + len(phones)

        masked_message = email_pattern.sub('[EMAIL]', message)
        masked_message = phone_pattern.sub('[PHONE]', masked_message)

        anonymized_lines.append(f"{timestamp} {user_id}: {masked_message}\n")

        stats[user_id]["total_messages"] += 1
        stats[user_id]["total_words"] += word_count
        stats[user_id]["total_pii_masked"] += pii_count

    final_stats = {}
    for uid, s in stats.items():
        avg_words = round(s["total_words"] / s["total_messages"], 2)
        final_stats[uid] = {
            "total_messages": s["total_messages"],
            "average_word_count": avg_words,
            "total_pii_masked": s["total_pii_masked"]
        }

    return anonymized_lines, final_stats


def test_anonymized_logs_created_and_correct():
    expected_lines, _ = compute_expected()
    output_file = '/home/user/anonymized_logs.txt'

    assert os.path.exists(output_file), f"Expected output file {output_file} was not created."

    with open(output_file, 'r') as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in anonymized logs, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected.strip(), f"Mismatch on line {i+1} of anonymized logs.\nExpected: {expected.strip()}\nActual: {actual.strip()}"


def test_user_stats_json_created_and_correct():
    _, expected_stats = compute_expected()
    output_file = '/home/user/user_stats.json'

    assert os.path.exists(output_file), f"Expected output file {output_file} was not created."

    with open(output_file, 'r') as f:
        try:
            actual_stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} is not valid JSON.")

    assert isinstance(actual_stats, dict), f"Expected JSON root to be a dictionary, got {type(actual_stats).__name__}."

    assert set(actual_stats.keys()) == set(expected_stats.keys()), f"User IDs in JSON do not match expected. Expected {list(expected_stats.keys())}, got {list(actual_stats.keys())}."

    for uid, expected_data in expected_stats.items():
        actual_data = actual_stats[uid]
        assert actual_data.get("total_messages") == expected_data["total_messages"], f"Mismatch in total_messages for user {uid}."
        assert actual_data.get("average_word_count") == expected_data["average_word_count"], f"Mismatch in average_word_count for user {uid}. Expected {expected_data['average_word_count']}, got {actual_data.get('average_word_count')}."
        assert actual_data.get("total_pii_masked") == expected_data["total_pii_masked"], f"Mismatch in total_pii_masked for user {uid}. Expected {expected_data['total_pii_masked']}, got {actual_data.get('total_pii_masked')}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
