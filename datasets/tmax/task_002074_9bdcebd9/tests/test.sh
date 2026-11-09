#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

WRAPPER_SCRIPT = "/home/user/filter_wrapper.py"
VALIDATOR_BIN = "/app/log_validator"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"


def test_wrapper_script_exists_and_executable():
    assert os.path.exists(WRAPPER_SCRIPT), f"Filter script not found at {WRAPPER_SCRIPT}"
    assert os.path.isfile(WRAPPER_SCRIPT), f"Path {WRAPPER_SCRIPT} is not a file"
    assert os.access(WRAPPER_SCRIPT, os.X_OK), f"Filter script at {WRAPPER_SCRIPT} is not executable"


def test_clean_corpus_preserved():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    modified_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            original_content = f.read()

        try:
            result = subprocess.run(
                [WRAPPER_SCRIPT],
                input=original_content,
                capture_output=True,
                timeout=5
            )
            if result.returncode != 0 or result.stdout != original_content:
                modified_files.append(filename)
        except Exception as e:
            modified_files.append(f"{filename} (error: {e})")

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean files modified/failed. Offending files: {', '.join(modified_files[:10])}"


_line_crash_cache = {}


def line_crashes(line):
    if line not in _line_crash_cache:
        result = subprocess.run(
            [VALIDATOR_BIN],
            input=line,
            capture_output=True,
            timeout=5
        )
        _line_crash_cache[line] = result.returncode != 0
    return _line_crash_cache[line]


def preserves_all_safe_lines(original_content, filtered_content):
    """Match each safe input line exactly and each crashing line to zero or one output line."""
    original_lines = original_content.splitlines(keepends=True)
    output_lines = filtered_content.splitlines(keepends=True)
    positions = {0}

    for line in original_lines:
        next_positions = set()
        crashing = line_crashes(line)
        for pos in positions:
            if crashing:
                # A crashing line may be removed or replaced by one safe line.
                next_positions.add(pos)
                if pos < len(output_lines):
                    next_positions.add(pos + 1)
            elif pos < len(output_lines) and output_lines[pos] == line:
                next_positions.add(pos + 1)
        positions = next_positions
        if not positions:
            return False

    return len(output_lines) in positions


def test_evil_corpus_sanitized():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    bypassed_files = []
    modified_safe_lines = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            original_content = f.read()

        try:
            wrapper_result = subprocess.run(
                [WRAPPER_SCRIPT],
                input=original_content,
                capture_output=True,
                timeout=5
            )

            if wrapper_result.returncode != 0:
                bypassed_files.append(filename)
                continue

            validator_result = subprocess.run(
                [VALIDATOR_BIN],
                input=wrapper_result.stdout,
                capture_output=True,
                timeout=5
            )

            if validator_result.returncode != 0:
                bypassed_files.append(filename)

            if not preserves_all_safe_lines(original_content, wrapper_result.stdout):
                modified_safe_lines.append(filename)

        except Exception as e:
            bypassed_files.append(f"{filename} (error: {e})")

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter and crashed the validator. Offending files: {', '.join(bypassed_files[:10])}"
    assert not modified_safe_lines, f"{len(modified_safe_lines)} of {len(evil_files)} evil files lost, changed, reordered, or added non-crashing lines. Offending files: {', '.join(modified_safe_lines[:10])}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
