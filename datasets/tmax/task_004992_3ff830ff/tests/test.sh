#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess

import nbformat
import pytest

BINARY = "/home/user/mutator/target/release/mutator"
SOURCE = "/home/user/mutator/src/main.rs"
FASTA = "/home/user/data/sequence.fasta"
OUTPUT = "/home/user/results/output.txt"
SUMMARY = "/home/user/results/summary.txt"
NOTEBOOK = "/home/user/workflow.ipynb"


def parse_p_value(path):
    with open(path, "r") as f:
        content = f.read().strip()
    match = re.search(r"p_value:\s*([0-9.]+)", content)
    assert match is not None, f"Could not parse a numeric p_value from {path}."
    try:
        return float(match.group(1)), content
    except ValueError:
        pytest.fail(f"Parsed p_value '{match.group(1)}' is not a valid float.")


def run_binary(sequence):
    with open(FASTA, "w") as f:
        f.write(">verification_sequence\n" + sequence + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([BINARY], check=True, timeout=10)
    assert os.path.isfile(OUTPUT), "The Rust binary did not create output.txt."
    return parse_p_value(OUTPUT)[0]


def test_binary_exists():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"The compiled Rust binary was not found at {binary_path}. Did you run 'cargo build --release'?"
    assert os.access(binary_path, os.X_OK), "The release artifact is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not an ELF binary."


def test_summary_file_exists():
    summary_path = SUMMARY
    assert os.path.isfile(summary_path), f"The summary file was not found at {summary_path}. Did you execute the Jupyter notebook?"


def test_summary_content_and_p_value():
    summary_path = SUMMARY
    with open(summary_path, "r") as f:
        content = f.read().strip()

    assert "Workflow Complete" in content, "The summary text does not contain 'Workflow Complete'."
    assert "p_value:" in content, "The summary text does not contain 'p_value:'."

    match = re.search(r"p_value:\s*([0-9.]+)", content)
    assert match is not None, "Could not parse a numeric p_value from summary.txt."

    try:
        p_val = float(match.group(1))
    except ValueError:
        pytest.fail(f"Parsed p_value '{match.group(1)}' is not a valid float.")

    assert p_val != 1.0, "p_value is exactly 1.0. The RNG or file reading is likely still inside the loop."
    assert p_val != 0.0, "p_value is exactly 0.0. The RNG or file reading is likely still inside the loop."
    assert 0.0 < p_val < 1.0, f"p_value {p_val} is out of expected statistical bounds."


def test_source_moves_io_and_rng_outside_loop():
    assert os.path.isfile(SOURCE), "src/main.rs is missing."
    source = open(SOURCE, "r").read()
    # Remove comments so commented-out fixes cannot satisfy these checks.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)

    loop_match = re.search(r"for\s+[A-Za-z_][A-Za-z0-9_]*\s+in\s+0\s*\.\.\s*iterations\s*\{", code)
    assert loop_match, "Could not find the required simulation loop over iterations."

    start = loop_match.end() - 1
    depth = 0
    end = None
    for pos in range(start, len(code)):
        if code[pos] == "{":
            depth += 1
        elif code[pos] == "}":
            depth -= 1
            if depth == 0:
                end = pos
                break
    assert end is not None, "The simulation loop is malformed."

    prefix = code[:loop_match.start()]
    body = code[start + 1:end]
    assert re.search(r"iterations\s*=\s*10_?000\s*;", code), "The iteration count must remain 10000."
    assert re.search(r"\[\s*42\s*;\s*32\s*\]", code), "The seed must remain [42; 32]."
    assert "read_to_string" in prefix, "The FASTA file must be read before the simulation loop."
    assert re.search(r"original_seq\s*:", prefix) or re.search(r"original_seq\s*=", prefix), "The FASTA sequence must be parsed before the simulation loop."
    assert "ChaCha8Rng::from_seed" in prefix, "ChaCha8Rng must be instantiated before the simulation loop."
    assert "read_to_string" not in body, "FASTA file reading is still inside the simulation loop."
    assert "ChaCha8Rng::from_seed" not in body, "The RNG is still being reset inside the simulation loop."


def test_notebook_was_executed_and_runs_pipeline():
    nb = nbformat.read(NOTEBOOK, as_version=4)
    code_cells = [cell for cell in nb.cells if cell.cell_type == "code"]
    assert code_cells, "workflow.ipynb has no code cell."
    assert any(cell.get("execution_count") is not None for cell in code_cells), "workflow.ipynb was not executed in place."
    notebook_code = "\n".join(cell.source for cell in code_cells)
    assert BINARY in notebook_code and "subprocess.run" in notebook_code, "The notebook no longer runs the Rust release binary."
    assert OUTPUT in notebook_code and SUMMARY in notebook_code, "The notebook no longer processes output.txt into summary.txt."


def test_compiled_program_behavior_and_fresh_notebook_execution():
    with open(FASTA, "r") as f:
        original_fasta = f.read()
    try:
        # These answers are derived directly from the supplied sequences: replacing
        # a character with A always increases the count for all-C and never does for all-A.
        assert run_binary("C" * 101) == 1.0
        assert run_binary("A" * 101) == 0.0

        mixed = "C" * 73 + "A" * 28
        mixed_p = run_binary(mixed)
        expected = 73.0 / 101.0
        assert abs(mixed_p - expected) < 0.04, f"Monte Carlo result {mixed_p} is inconsistent with the input-derived expectation {expected}."
    finally:
        with open(FASTA, "w") as f:
            f.write(original_fasta)

    for path in (OUTPUT, SUMMARY):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run(
        ["jupyter", "nbconvert", "--execute", "--to", "notebook", "--inplace", NOTEBOOK],
        check=True,
        timeout=60,
    )
    assert os.path.isfile(OUTPUT), "Fresh notebook execution did not create output.txt."
    assert os.path.isfile(SUMMARY), "Fresh notebook execution did not create summary.txt."
    output_p, _ = parse_p_value(OUTPUT)
    summary_p, summary_content = parse_p_value(SUMMARY)
    assert "Workflow Complete" in summary_content
    assert output_p == summary_p, "The notebook summary does not report the Rust binary's output."
    assert 0.0 < summary_p < 1.0, "The corrected workflow must produce a fractional p-value."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
