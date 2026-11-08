#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

import pytest


def test_report_2023_10_contents():
    """Verify the contents of the October 2023 report."""
    file_path = "/home/user/reports/report_2023-10.md"
    assert os.path.isfile(file_path), f"Expected report file {file_path} is missing."

    expected_content = (
        "## Feedback Entry\n"
        "**Date:** 2023-10-01T08:00:00Z\n"
        "**User:** c***@domain.com\n"
        "**Comment:** Standard feedback, all good!\n"
        "---\n"
        "## Feedback Entry\n"
        "**Date:** 2023-10-15T14:30:00Z\n"
        "**User:** a***@example.com\n"
        "**Comment:** This has an\n"
        "embedded newline.\n"
        "---\n"
    )

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert content == expected_content, f"The content of {file_path} does not match the expected output format and data."


def test_report_2023_11_contents():
    """Verify the contents of the November 2023 report."""
    file_path = "/home/user/reports/report_2023-11.md"
    assert os.path.isfile(file_path), f"Expected report file {file_path} is missing."

    expected_content = (
        "## Feedback Entry\n"
        "**Date:** 2023-11-05T09:15:00Z\n"
        "**User:** b***@test.org\n"
        "**Comment:** Invalid chars ?? here.\n"
        "---\n"
        "## Feedback Entry\n"
        "**Date:** 2023-11-20T11:00:00Z\n"
        "**User:** d***@company.net\n"
        "**Comment:** Multiple\n"
        "newlines\n"
        "???\n"
        "---\n"
    )

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert content == expected_content, f"The content of {file_path} does not match the expected output format and data."


def make_case(tag):
    records = [
        (f"2025-07-03T04:05:{tag[:2]}Z", f"z{tag}@example.net", b"Comma, value " + tag.encode() + b"\nsecond line \xff"),
        (f"2025-07-19T10:11:{tag[2:4]}Z", "q@test.org", b"Plain " + tag.encode()),
        (f"2026-02-01T22:33:{tag[4:6]}Z", f"m{tag}@company.com", b"Bytes \x80\xe2\x82\xac\nmore"),
    ]
    return records


def expected_reports(records):
    reports = {}
    for timestamp, email, feedback in records:
        local, domain = email.split('@', 1)
        masked = local[0] + '***@' + domain
        sanitized = bytes((b if b <= 127 else ord('?')) for b in feedback).decode('ascii')
        entry = (
            "## Feedback Entry\n"
            f"**Date:** {timestamp}\n"
            f"**User:** {masked}\n"
            f"**Comment:** {sanitized}\n"
            "---\n"
        )
        name = f"report_{timestamp[:7]}.md"
        reports[name] = reports.get(name, '') + entry
    return reports


def install_input(records):
    with open('/home/user/feedback.csv', 'wb') as f:
        for timestamp, email, feedback in records:
            f.write(timestamp.encode('ascii') + b',' + email.encode('ascii') + b',"' + feedback + b'"\n')

    reports_dir = Path('/home/user/reports')
    if reports_dir.exists():
        shutil.rmtree(reports_dir)
    reports_dir.mkdir(parents=True)


def assert_reports(records):
    reports_dir = Path('/home/user/reports')
    expected = expected_reports(records)
    actual_names = {p.name for p in reports_dir.iterdir() if p.is_file()}
    assert actual_names == set(expected), f"Unexpected report set: {actual_names}"
    for name, content in expected.items():
        assert (reports_dir / name).read_text(encoding='utf-8') == content


def run_case(executable, records):
    install_input(records)
    result = subprocess.run([executable], cwd='/home/user', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, result.stderr.decode('utf-8', errors='replace')
    assert_reports(records)


def test_c_source_and_executable_process_unseen_input():
    source = Path('/home/user/clean_feedback.c')
    executable = Path('/home/user/clean_feedback')

    assert source.exists() and not source.is_symlink()
    assert stat.S_ISREG(source.stat().st_mode), 'clean_feedback.c must be a regular file'
    assert executable.exists() and not executable.is_symlink()
    assert stat.S_ISREG(executable.stat().st_mode), 'clean_feedback must be a regular file'
    assert os.access(executable, os.X_OK), 'clean_feedback is not executable'
    assert executable.read_bytes()[:4] == b'\x7fELF', 'clean_feedback is not a compiled ELF executable'

    run_case(str(executable), make_case(secrets.token_hex(3)))

    rebuilt = '/tmp/clean_feedback_rebuilt'
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(source), '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compile_result.returncode == 0, compile_result.stderr.decode('utf-8', errors='replace')
    run_case(rebuilt, make_case(secrets.token_hex(3)))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
