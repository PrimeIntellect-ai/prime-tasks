#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

ROOT = "/home/user/seq_analyzer"
BINARY = os.path.join(ROOT, "seq_analyzer")
LOG_PATH = "/home/user/results/analysis.log"
READS = "/home/user/data/reads.fasta"


def test_analysis_log_exists():
    assert os.path.isfile(LOG_PATH), f"The file {LOG_PATH} does not exist."


def test_compiled_artifact_exists_and_is_executable():
    assert os.path.isfile(BINARY), f"{BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."


def test_analysis_log_contents():
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    blocks = content.split("---")
    assert len(blocks) == 2, "analysis.log must contain exactly two sequence blocks separated by '---'."

    read_a_block = blocks[0].strip()
    assert "Sequence: read_A" in read_a_block, "Sequence read_A not found in the first block."
    period_match_a = re.search(r"Dominant Period:\s*(\d+)", read_a_block)
    assert period_match_a, "Dominant Period not found for read_A."
    assert int(period_match_a.group(1)) == 6, f"Expected Dominant Period 6 for read_A, got {period_match_a.group(1)}."
    gc_match_a = re.search(r"GC Posterior Mean:\s*([\d.]+)", read_a_block)
    assert gc_match_a, "GC Posterior Mean not found for read_A."
    gc_val_a = float(gc_match_a.group(1))
    assert abs(gc_val_a - 0.67) <= 0.02, f"Expected GC Posterior Mean ~0.67 for read_A, got {gc_val_a}."

    read_b_block = blocks[1].strip()
    assert "Sequence: read_B" in read_b_block, "Sequence read_B not found in the second block."
    period_match_b = re.search(r"Dominant Period:\s*(\d+)", read_b_block)
    assert period_match_b, "Dominant Period not found for read_B."
    assert int(period_match_b.group(1)) == 30, f"Expected Dominant Period 30 for the all-zero length-30 signal read_B, got {period_match_b.group(1)}."
    gc_match_b = re.search(r"GC Posterior Mean:\s*([\d.]+)", read_b_block)
    assert gc_match_b, "GC Posterior Mean not found for read_B."
    gc_val_b = float(gc_match_b.group(1))
    assert abs(gc_val_b - 0.03) <= 0.02, f"Expected GC Posterior Mean ~0.03 for read_B, got {gc_val_b}."


def test_log_is_actual_program_output():
    result = subprocess.run(
        [BINARY, READS], cwd=ROOT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"seq_analyzer failed: {result.stderr}"
    with open(LOG_PATH, "r") as f:
        saved = f.read()
    assert saved == result.stdout, "analysis.log is not the exact stdout produced by seq_analyzer on reads.fasta."


def test_regression_tests_pass():
    script_path = os.path.join(ROOT, "run_tests.sh")
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    expected_path = "/home/user/expected/test.out"
    with open(expected_path, "rb") as f:
        original_expected = f.read()

    corrected_expected = (
        "Sequence: test_seq1\n"
        "Dominant Period: 4\n"
        "GC Posterior Mean: 0.50\n"
    )
    try:
        with open(expected_path, "w") as f:
            f.write(corrected_expected)
        result = subprocess.run(
            [script_path], cwd=ROOT, capture_output=True, text=True, timeout=30
        )
    finally:
        with open(expected_path, "wb") as f:
            f.write(original_expected)

    assert result.returncode == 0, f"Regression tests failed. Output: {result.stdout}\n{result.stderr}"
    assert "Tests passed!" in result.stdout, "Expected 'Tests passed!' in output of run_tests.sh."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
