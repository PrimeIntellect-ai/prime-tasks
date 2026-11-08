#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import pytest

PIPELINE = "/home/user/pipeline.sh"
WEIGHTS = "/home/user/weights.tsv"
RAW_DATA = "/home/user/raw_data.jsonl"
CLEANED_DATA = "/home/user/cleaned_data.jsonl"

ORIGINAL_DATA = '''{"id": 1, "text": "short text", "summary": "short"}
{"id": 2, "text": "This is a sufficiently long text to pass the threshold.", "summary": "A good summary."}
{"id": "3", "text": "Invalid id type", "summary": "drop"}
{"id": 4, "text": "Another perfectly fine text that should definitely be included in the output.", "summary": "Included."}
{"id": 5, "text": "This is a sufficiently long text to pass the threshold.", "summary": "Duplicate text."}
{"id": 6, "text": "Valid text but missing summary"}
{"id": 7, "text": "Extremely long text that goes on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on.", "summary": "Way too long."}
{"id": 8, "text": "A valid row", "summary": "Valid row summary.", "extra": "field"}
{"id": 9, "text": "Final valid text for the test case.", "summary": "Final summary."}
'''

ADDITIONAL_DATA = '''{"id":10,"text":"abcdefghij","summary":"12345"}
{"id":11,"text":"abcdefghij","summary":"this duplicate must be removed"}
not valid json
{"id":true,"text":"boolean id is invalid","summary":"12345"}
{"id":12,"text":"tiny","summary":"x"}
{"id":13,"text":"tiny","summary":"abcdefghijk"}
{"id":14,"text":"valid exact schema","summary":"and valid score","extra":0}
{"id":15,"text":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefgh","summary":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx"}
'''

CASES = [
    ("0.5\t1.2\n", ORIGINAL_DATA),
    ("1.0\t1.0\n", ADDITIONAL_DATA),
]


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def derive_expected(weights_content, raw_content):
    w_text_str, w_summary_str = weights_content.strip().split("\t")
    w_text = float(w_text_str)
    w_summary = float(w_summary_str)
    expected_lines = []
    seen_texts = set()

    for line in raw_content.splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue

        if not isinstance(row, dict) or set(row.keys()) != {"id", "text", "summary"}:
            continue
        if not isinstance(row["id"], int) or isinstance(row["id"], bool):
            continue
        if not isinstance(row["text"], str):
            continue
        if not isinstance(row["summary"], str):
            continue

        score = w_text * len(row["text"]) + w_summary * len(row["summary"])
        if not 15.0 <= score <= 100.0:
            continue
        if row["text"] in seen_texts:
            continue

        seen_texts.add(row["text"])
        expected_lines.append(row)

    return expected_lines


def test_pipeline_output():
    assert os.path.isfile(PIPELINE), f"Missing {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable"

    for weights_content, raw_content in CASES:
        expected_lines = derive_expected(weights_content, raw_content)

        remove_path(WEIGHTS)
        remove_path(RAW_DATA)
        remove_path(CLEANED_DATA)
        with open(WEIGHTS, "w", encoding="utf-8") as f:
            f.write(weights_content)
        with open(RAW_DATA, "w", encoding="utf-8") as f:
            f.write(raw_content)

        result = subprocess.run(
            [PIPELINE],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Pipeline failed with exit code {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

        assert os.path.exists(WEIGHTS), f"Missing {WEIGHTS}"
        assert os.path.exists(RAW_DATA), f"Missing {RAW_DATA}"
        assert os.path.exists(CLEANED_DATA), (
            f"Missing {CLEANED_DATA} - pipeline script may not have run or failed."
        )

        actual_lines = []
        with open(CLEANED_DATA, "r", encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    actual_lines.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Output file {CLEANED_DATA} contains invalid JSON: {line}")

        assert actual_lines == expected_lines, (
            f"Cleaned data does not match expected output.\n"
            f"Expected: {expected_lines}\nActual: {actual_lines}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
