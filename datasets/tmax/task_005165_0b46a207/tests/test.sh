#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/sanitize.sh"
EVIL_DIR = "/app/tests/evil"
CLEAN_DIR = "/app/tests/clean"
PATHFINDER = "/app/pathfinder"
HEADER = "source_node,target_node,max_latency\n"


def get_expected_output(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    if not lines:
        return ""

    expected_lines = [lines[0]]  # Header
    for line in lines[1:]:
        if "_STALE_" not in line:
            expected_lines.append(line)

    return "".join(expected_lines)


def run_script_on_file(filepath):
    result = subprocess.run(
        ["bash", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True
    )
    return result.stdout


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_clean_corpus():
    if not os.path.exists(CLEAN_DIR):
        pytest.skip(f"Clean corpus dir {CLEAN_DIR} not found")

    failed_files = []
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        expected = get_expected_output(filepath)
        actual = run_script_on_file(filepath)

        if actual.strip() != expected.strip():
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified or incorrectly processed: {', '.join(failed_files)}"


def test_evil_corpus():
    if not os.path.exists(EVIL_DIR):
        pytest.skip(f"Evil corpus dir {EVIL_DIR} not found")

    failed_files = []
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        expected = get_expected_output(filepath)
        actual = run_script_on_file(filepath)

        if actual.strip() != expected.strip():
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed or incorrectly processed: {', '.join(failed_files)}"


def oracle_says_safe(row, tmp_path, index):
    query_path = tmp_path / f"oracle_query_{index}.csv"
    query_path.write_text(HEADER + row, encoding="utf-8")
    result = subprocess.run(
        [PATHFINDER, "--explain", "--graph", "/app/data/graph.csv", "--query", str(query_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"pathfinder failed while deriving expected output: {result.stderr}"
    valid = "[INFO] INDEX_STATE: VALID" in result.stdout
    corrupted = "[WARN] INDEX_STATE: CORRUPTED" in result.stdout
    assert valid != corrupted, f"Unexpected pathfinder explanation: {result.stdout!r}"
    return valid


def test_generated_clean_evil_and_headerless_inputs(tmp_path):
    token = secrets.token_hex(12)
    safe_a = f"{token}_A,{token}_B,10\n"
    safe_b = f"{token}_C,{token}_D,25\n"
    evil_source = f"{token}_STALE_A,{token}_E,30\n"
    evil_target = f"{token}_F,{token}_STALE_B,40\n"

    cases = [
        (True, [safe_a, safe_b]),
        (True, [evil_source, safe_a, evil_target, safe_b]),
        (True, [evil_source, evil_target]),
        (False, [evil_target, safe_a, evil_source, safe_b]),
        (True, []),
        (False, []),
    ]

    oracle_index = 0
    for case_index, (has_header, rows) in enumerate(cases):
        kept = []
        for row in rows:
            if oracle_says_safe(row, tmp_path, oracle_index):
                kept.append(row)
            oracle_index += 1

        expected = (HEADER if has_header else "") + "".join(kept)
        input_text = (HEADER if has_header else "") + "".join(rows)
        input_path = tmp_path / f"generated_input_{case_index}.csv"
        input_path.write_text(input_text, encoding="utf-8")

        result = subprocess.run(
            ["bash", SCRIPT_PATH, str(input_path)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"sanitize.sh failed for generated case {case_index}: {result.stderr}"
        assert result.stdout == expected, (
            f"Incorrect output for generated case {case_index}: "
            f"expected {expected!r}, got {result.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
