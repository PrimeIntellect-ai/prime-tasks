#!/bin/bash
set -e
mkdir -p /logs/verifier

TMP_DIR=$(mktemp -d)
cp /home/user/raw_chat_logs.csv "$TMP_DIR/raw_chat_logs.csv"
if [ -f /home/user/processed_logs.jsonl ]; then
    cp /home/user/processed_logs.jsonl "$TMP_DIR/processed_logs.jsonl"
    HAD_OUTPUT=1
else
    HAD_OUTPUT=0
fi

cleanup() {
    cp "$TMP_DIR/raw_chat_logs.csv" /home/user/raw_chat_logs.csv
    if [ "$HAD_OUTPUT" -eq 1 ]; then
        cp "$TMP_DIR/processed_logs.jsonl" /home/user/processed_logs.jsonl
    else
        rm -f /home/user/processed_logs.jsonl
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import stat
import subprocess
import sys

SCRIPT_PATH = "/home/user/process_logs.py"
INPUT_PATH = "/home/user/raw_chat_logs.csv"
OUTPUT_PATH = "/home/user/processed_logs.jsonl"


def compute_expected_data(csv_path):
    # Regex for email: preceded and followed by at least one alphanumeric character
    # and consisting of non-whitespace around an @ symbol.
    email_pattern = re.compile(r'[a-zA-Z0-9][^\s]*@[^\s]*[a-zA-Z0-9]')

    def mask_email(text):
        return email_pattern.sub('[EMAIL]', text)

    def get_words(text):
        return set(re.findall(r'[a-zA-Z0-9]+', text.lower()))

    expected = []
    user_prev_words = {}

    with open(csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            masked_msg = mask_email(row['message'])
            words = get_words(masked_msg)

            user_id = row['user_id']
            is_anomaly = False

            if user_id in user_prev_words:
                prev_words = user_prev_words[user_id]
                if not prev_words and not words:
                    jaccard = 1.0
                elif not prev_words or not words:
                    jaccard = 0.0
                else:
                    intersection = len(words.intersection(prev_words))
                    union = len(words.union(prev_words))
                    jaccard = intersection / union if union > 0 else 0.0

                if jaccard >= 0.8:
                    is_anomaly = True

            user_prev_words[user_id] = words

            expected.append({
                'timestamp': row['timestamp'],
                'user_id': user_id,
                'cleaned_message': masked_msg,
                'is_anomaly': is_anomaly
            })

    return expected


def run_submission():
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            raise AssertionError(f"{OUTPUT_PATH} is a directory, not a JSONL file.")
        os.unlink(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_logs.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_processed_logs_exist():
    assert os.path.exists(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."


def assert_processed_logs_format_and_content(input_path=INPUT_PATH):
    assert os.path.exists(input_path), "Input CSV file is missing, cannot verify."

    expected_data = compute_expected_data(input_path)

    actual_data = []
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_data.append(record)
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {OUTPUT_PATH} is not valid JSON."

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        expected_keys = {'timestamp', 'user_id', 'cleaned_message', 'is_anomaly'}
        assert set(actual.keys()) == expected_keys, f"Row {i+1} keys mismatch. Expected {expected_keys}, got {set(actual.keys())}."
        assert actual['timestamp'] == expected['timestamp'], f"Row {i+1} timestamp mismatch."
        assert actual['user_id'] == expected['user_id'], f"Row {i+1} user_id mismatch."
        assert actual['cleaned_message'] == expected['cleaned_message'], f"Row {i+1} cleaned_message mismatch. Expected {repr(expected['cleaned_message'])}, got {repr(actual['cleaned_message'])}."
        assert actual['is_anomaly'] == expected['is_anomaly'], f"Row {i+1} is_anomaly mismatch. Expected {expected['is_anomaly']}, got {actual['is_anomaly']}."


def test_process_script_exists_and_is_regular_python_file():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular file, not a symbolic link."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} is not a regular file."


def test_processed_logs_exist():
    run_submission()
    assert_processed_logs_exist()


def test_processed_logs_format_and_content():
    assert_processed_logs_format_and_content()


def test_submission_processes_altered_input():
    nonce = secrets.token_hex(8)
    rows = [
        ["2024-02-01T09:00:00Z", "A-" + nonce, "Contact first.user@example.com\nfor help"],
        ["2024-02-01T09:01:00Z", "B-" + nonce, "alpha beta gamma delta"],
        ["2024-02-01T09:02:00Z", "A-" + nonce, "Contact second.user@example.net\nfor help!"],
        ["2024-02-01T09:03:00Z", "B-" + nonce, "alpha beta gamma delta epsilon"],
        ["2024-02-01T09:04:00Z", "C-" + nonce, ""],
        ["2024-02-01T09:05:00Z", "C-" + nonce, ""],
        ["2024-02-01T09:06:00Z", "A-" + nonce, "A completely different response without mail"],
        ["2024-02-01T09:07:00Z", "D-" + nonce, "Send admin-test@domain.org the multiline\nreport now."],
    ]

    with open(INPUT_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "user_id", "message"])
        writer.writerows(rows)

    run_submission()
    assert_processed_logs_exist()
    assert_processed_logs_format_and_content()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
