#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import secrets
import subprocess
import sys

import pytest


def test_bug_report_content():
    report_path = "/home/user/bug_report.txt"
    assert os.path.isfile(report_path), f"Bug report file missing at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected = "Faulty ID: BAD-999-LEAK"
    assert content == expected, f"Expected bug report to contain '{expected}', but got '{content}'"


def test_pytest_suite_passes():
    test_file = "/home/user/app/tests/test_consumer.py"
    assert os.path.isfile(test_file), f"Test file missing at {test_file}"

    result = subprocess.run(
        [sys.executable, "-m", "pytest", test_file],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        f"pytest failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def load_consumer():
    consumer_path = "/home/user/app/consumer.py"
    assert os.path.isfile(consumer_path), f"consumer.py missing at {consumer_path}"

    app_dir = "/home/user/app"
    if app_dir not in sys.path:
        sys.path.insert(0, app_dir)

    try:
        import consumer
    except ImportError as e:
        pytest.fail(f"Failed to import consumer.py: {e}")
    return consumer


def test_consumer_memory_leak_fixed():
    consumer = load_consumer()

    # Preserve the original edge-case assertion.
    consumer.ERROR_HISTORY = []
    payload = '{"date": "2023/10/24"}'
    initial_len = len(consumer.ERROR_HISTORY)
    result = consumer.process_payload(payload)

    assert len(consumer.ERROR_HISTORY) == initial_len, (
        "consumer.py still appends to ERROR_HISTORY for the YYYY/MM/DD format "
        "(memory leak not fixed)"
    )
    assert result == "2023-10-24T00:00:00", (
        "process_payload did not return the expected ISO format string for "
        f"YYYY/MM/DD format, got: {result}"
    )


def test_parser_handles_derived_payload_variations_without_leaking():
    consumer = load_consumer()

    # Generate dates at verification time so a fixed-result implementation cannot pass.
    base = datetime.date(1995, 1, 1)
    dates = {
        base + datetime.timedelta(days=secrets.randbelow(20000))
        for _ in range(16)
    }
    dates.update({
        datetime.date(2000, 2, 29),
        datetime.date(2024, 2, 29),
        datetime.date(2031, 12, 31),
    })

    for date_value in dates:
        expected = datetime.datetime.combine(date_value, datetime.time()).isoformat()
        for separator in ("-", "/"):
            formatted = date_value.strftime(f"%Y{separator}%m{separator}%d")
            payload = json.dumps({
                "source": secrets.token_hex(5),
                "date": formatted,
                "sequence": secrets.randbelow(1000000),
            })

            consumer.ERROR_HISTORY = []
            initial_len = len(consumer.ERROR_HISTORY)
            result = consumer.process_payload(payload)

            assert type(result) is str, (
                f"process_payload returned a non-string for valid date {formatted}: {result!r}"
            )
            assert result == expected, (
                f"Incorrect parse result for valid date {formatted}: "
                f"expected {expected!r}, got {result!r}"
            )
            assert len(consumer.ERROR_HISTORY) == initial_len, (
                f"Valid date format {formatted} was recorded in ERROR_HISTORY"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
