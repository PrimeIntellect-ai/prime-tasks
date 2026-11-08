#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/filter.sh"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"

def run_filter_script(input_text: bytes) -> bytes:
    """Helper to run the user's script with given input bytes."""
    process = subprocess.run(
        ["bash", SCRIPT_PATH],
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    return process.stdout

def expected_filter(input_text: bytes) -> bytes:
    """Derive the required per-line filtering and consecutive deduplication result."""
    output = []
    previous_valid_line = None
    for line in input_text.splitlines(keepends=True):
        body = line[:-1] if line.endswith(b"\n") else line
        invalid = (
            b"FORBIDDEN_KEY_77X" in body
            or b"critical_failure" in body.lower()
        )
        if invalid:
            continue
        if line != previous_valid_line:
            output.append(line)
            previous_valid_line = line
    return b"".join(output)

def test_script_exists():
    """Ensure the user created the filter script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

def test_evil_corpus_rejected():
    """Ensure all files in the evil corpus are completely rejected (0 bytes output)."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in the evil corpus."

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()

        output_data = run_filter_script(input_data)

        if len(output_data.strip()) > 0:
            bypassed_files.append(filename)

    assert len(bypassed_files) == 0, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter. Offending files: {', '.join(bypassed_files)}"

def test_clean_corpus_preserved():
    """Ensure all files in the clean corpus are completely preserved."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in the clean corpus."

    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()

        output_data = run_filter_script(input_data)

        if output_data != input_data:
            modified_files.append(filename)

    assert len(modified_files) == 0, f"{len(modified_files)} of {len(clean_files)} clean files modified by the filter. Offending files: {', '.join(modified_files)}"

def test_deduplication():
    """Ensure consecutive identical lines are collapsed into a single line."""
    input_text = b"line1\nline1\nline1\nline2\nline3\nline3\nline1\n"
    expected_output = b"line1\nline2\nline3\nline1\n"

    output_data = run_filter_script(input_text)

    assert output_data == expected_output, f"Deduplication failed. Expected {expected_output}, got {output_data}"

def test_mixed_streams_filter_individual_lines():
    """Valid lines in streams containing rejected lines must still be preserved."""
    critical_spellings = [
        b"critical_failure",
        b"CRITICAL_FAILURE",
        b"CrItIcAl_FaIlUrE",
        b"Critical_Failure",
    ]

    for _ in range(10):
        tag = secrets.token_hex(16).encode("ascii")
        a = b"valid alpha " + tag + b"\n"
        b = b"valid beta " + tag + b"\n"
        c = b"valid gamma " + tag + b"\n"
        d = b"valid delta " + tag + b"\n"
        critical = critical_spellings[secrets.randbelow(len(critical_spellings))]

        lines = [
            a,
            a,
            b"reject this FORBIDDEN_KEY_77X now " + tag + b"\n",
            b,
            b,
            b"a " + critical + b" occurred " + tag + b"\n",
            c,
            b"FORBIDDEN_KEY_77X " + tag + b"\n",
            a,
            d,
        ]
        rotation = secrets.randbelow(len(lines))
        lines = lines[rotation:] + lines[:rotation]
        input_text = b"".join(lines)
        expected_output = expected_filter(input_text)

        assert expected_output, "Generated mixed-stream expectation must contain valid lines"
        output_data = run_filter_script(input_text)
        assert output_data == expected_output, (
            f"Mixed-stream filtering failed. Expected {expected_output!r}, got {output_data!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
