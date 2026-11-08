#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
import pytest

BUG_REPORT = "/home/user/bug_report.txt"
PIPELINE_OUTPUT = "/home/user/pipeline_output.txt"
PIPELINE_DIR = "/home/user/pipeline"
PARSER_PY = os.path.join(PIPELINE_DIR, "parser.py")
LARGE_INPUT = os.path.join(PIPELINE_DIR, "large_input.txt")
EXPECTED_MALFORMED_LINE = "2023-10-14 10:22:14 [WARN] Connection timeout <data>partial_payload_missing_closing_tag"


def test_bug_report_content():
    assert os.path.isfile(BUG_REPORT), f"{BUG_REPORT} does not exist."
    with open(BUG_REPORT, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_MALFORMED_LINE, f"{BUG_REPORT} does not contain the correct isolated log line."


def test_parser_loop_termination():
    assert os.path.isfile(PARSER_PY), f"{PARSER_PY} does not exist."

    try:
        process = subprocess.run(
            ["python3", PARSER_PY],
            input=EXPECTED_MALFORMED_LINE + "\n",
            capture_output=True,
            text=True,
            timeout=2.0
        )
        assert process.returncode == 0, "parser.py crashed or returned non-zero exit code."
    except subprocess.TimeoutExpired:
        pytest.fail("parser.py still hangs on the malformed input line (infinite loop not fixed).")


def test_parser_extracts_valid_payloads_and_skips_malformed_lines():
    assert os.path.isfile(PARSER_PY), f"{PARSER_PY} does not exist."

    nonce = uuid.uuid4().hex
    expected_payloads = [
        f"first_{nonce}",
        f"second_{nonce}",
        f"third_{nonce}",
        f"after_malformed_{nonce}",
    ]
    test_input = "\n".join([
        f"prefix <data>{expected_payloads[0]}</data> suffix",
        f"<data>{expected_payloads[1]}</data> middle <data>{expected_payloads[2]}</data>",
        f"broken record <data>incomplete_{nonce}",
        "ordinary untagged log line",
        f"next record <data>{expected_payloads[3]}</data>",
        "",
    ])

    try:
        process = subprocess.run(
            ["python3", PARSER_PY],
            input=test_input,
            capture_output=True,
            text=True,
            timeout=2.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("parser.py hung while processing mixed valid and malformed records.")

    assert process.returncode == 0, (
        f"parser.py returned {process.returncode}: {process.stderr}"
    )
    assert process.stdout.splitlines() == expected_payloads, (
        "parser.py did not extract all valid payloads exactly, or emitted output "
        "for malformed/untagged records."
    )


def test_pipeline_output_correctness():
    assert os.path.isfile(LARGE_INPUT), f"{LARGE_INPUT} does not exist."
    assert os.path.isfile(PIPELINE_OUTPUT), f"{PIPELINE_OUTPUT} does not exist."

    expected_payloads = []
    with open(LARGE_INPUT, "r") as f:
        for line in f:
            line = line.strip()
            remain = line
            while "<data>" in remain:
                start = remain.find("<data>") + 6
                end = remain.find("</data>", start)
                if end != -1:
                    expected_payloads.append(remain[start:end])
                    remain = remain[end+7:]
                else:
                    break

    with open(PIPELINE_OUTPUT, "r") as f:
        actual_payloads = [line.strip() for line in f if line.strip()]

    assert len(actual_payloads) == len(expected_payloads), f"Expected {len(expected_payloads)} payloads, but found {len(actual_payloads)} in {PIPELINE_OUTPUT}."
    assert actual_payloads == expected_payloads, f"The contents of {PIPELINE_OUTPUT} do not match the expected extracted data payloads."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
