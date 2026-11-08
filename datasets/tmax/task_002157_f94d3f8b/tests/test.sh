#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess


def test_script_exists():
    script_path = "/home/user/clean_data.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_cleaned_feedback_content():
    raw_path = "/home/user/raw_feedback.txt"
    cleaned_path = "/home/user/cleaned_feedback.txt"

    assert os.path.exists(cleaned_path), f"The output file {cleaned_path} does not exist."

    expected_lines = []
    seen_feedback = set()

    with open(raw_path, "r") as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            parts = line.split('|')
            if len(parts) != 4:
                continue
            row_id, email, timestamp, feedback = parts

            if feedback in seen_feedback:
                continue
            seen_feedback.add(feedback)

            email_hash = hashlib.md5(email.encode('utf-8')).hexdigest()[:8]
            domain = email.split('@')[1] if '@' in email else ""
            anon_email = f"{email_hash}@{domain}"
            word_count = len(feedback.split())
            expected_lines.append(
                f"{row_id}|{anon_email}|{timestamp}|{feedback}|{word_count}\n"
            )

    expected_content = "".join(expected_lines)

    with open(cleaned_path, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"The content of {cleaned_path} is incorrect."


def test_report_content():
    raw_path = "/home/user/raw_feedback.txt"
    cleaned_path = "/home/user/cleaned_feedback.txt"
    report_path = "/home/user/report.md"

    assert os.path.exists(report_path), f"The report file {report_path} does not exist."

    with open(raw_path, "r") as f:
        raw_rows = sum(1 for line in f if line.rstrip('\n'))

    with open(cleaned_path, "r") as f:
        cleaned_rows = sum(1 for line in f if line.rstrip('\n'))

    expected_report = (
        f"# Data Cleaning Report\nOriginal rows: {raw_rows}\n"
        f"Cleaned rows: {cleaned_rows}\n"
    )

    with open(report_path, "r") as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), f"The content of {report_path} is incorrect."


def expected_outputs(raw_content):
    expected_lines = []
    seen_feedback = set()
    raw_lines = raw_content.splitlines()

    for line in raw_lines:
        if not line:
            continue
        parts = line.split('|')
        if len(parts) != 4:
            continue
        row_id, email, timestamp, feedback = parts
        if feedback in seen_feedback:
            continue
        seen_feedback.add(feedback)

        email_hash = hashlib.md5(email.encode("utf-8")).hexdigest()[:8]
        domain = email.split("@", 1)[1] if "@" in email else ""
        word_count = len(feedback.split())
        expected_lines.append(
            f"{row_id}|{email_hash}@{domain}|{timestamp}|{feedback}|{word_count}\n"
        )

    cleaned = "".join(expected_lines)
    report = (
        f"# Data Cleaning Report\nOriginal rows: {len(raw_lines)}\n"
        f"Cleaned rows: {len(expected_lines)}\n"
    )
    return cleaned, report


def test_script_is_valid_and_reusable_pipeline():
    script_path = "/home/user/clean_data.sh"
    raw_path = "/home/user/raw_feedback.txt"
    cleaned_path = "/home/user/cleaned_feedback.txt"
    report_path = "/home/user/report.md"

    syntax = subprocess.run(
        ["bash", "-n", script_path], capture_output=True, text=True, timeout=10
    )
    assert syntax.returncode == 0, f"clean_data.sh is not valid Bash: {syntax.stderr}"

    paths = [raw_path, cleaned_path, report_path]
    saved = {}
    for path in paths:
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    nonce = secrets.token_hex(8)
    fixtures = [
        (
            f"101|alpha-{nonce}@example.com|2026-01-01|Fresh {nonce} feedback\n"
            f"102|beta-{nonce}@work.org|2026-01-02|A short response\n"
            f"103|gamma-{nonce}@test.net|2026-01-03|Fresh {nonce} feedback\n"
            f"104|delta-{nonce}@sub.example.net|2026-01-04|fresh {nonce} feedback\n"
            f"105|epsilon-{nonce}@secure.io|2026-01-05|One\n"
        ),
        (
            f"201|one-{nonce}@domain.test|2026-02-01|Second run {nonce}\n"
            f"202|two-{nonce}@another.test|2026-02-02|Count these three words\n"
            f"203|three-{nonce}@domain.test|2026-02-03|Second run {nonce}\n"
        ),
    ]

    try:
        for raw_content in fixtures:
            with open(raw_path, "w") as f:
                f.write(raw_content)

            result = subprocess.run(
                ["bash", script_path],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, (
                f"clean_data.sh failed when executed. stdout: {result.stdout!r}; "
                f"stderr: {result.stderr!r}"
            )
            assert os.path.isfile(cleaned_path), "The script did not create cleaned_feedback.txt."
            assert os.path.isfile(report_path), "The script did not create report.md."

            expected_cleaned, expected_report = expected_outputs(raw_content)
            with open(cleaned_path, "r") as f:
                actual_cleaned = f.read()
            with open(report_path, "r") as f:
                actual_report = f.read()

            assert actual_cleaned == expected_cleaned, (
                "Executing clean_data.sh did not produce the required cleaned data."
            )
            assert actual_report.strip() == expected_report.strip(), (
                "Executing clean_data.sh did not produce the required report."
            )
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
