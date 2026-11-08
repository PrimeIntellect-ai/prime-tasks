#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

C_FILE = "/home/user/analyze.c"
INPUT_FILE = "/home/user/input.fasta"
RESULTS_FILE = "/home/user/results.txt"
BINARY = "/tmp/analyze_submission"


def test_analyze_c_exists():
    """Test that the C source code file exists."""
    assert os.path.exists(C_FILE), f"Missing required file: {C_FILE}"
    assert os.path.isfile(C_FILE), f"Expected {C_FILE} to be a file."


def test_results_txt_exists():
    """Test that the results.txt file was generated."""
    assert os.path.exists(RESULTS_FILE), f"Missing required file: {RESULTS_FILE}"
    assert os.path.isfile(RESULTS_FILE), f"Expected {RESULTS_FILE} to be a file."


def test_results_txt_content():
    """Test that the results.txt file contains the correct output."""
    with open(RESULTS_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {RESULTS_FILE}, found {len(lines)}"
    assert lines[0] == "2", f"Expected first line of {RESULTS_FILE} to be '2', but got '{lines[0]}'"
    assert lines[1] == "5", f"Expected second line of {RESULTS_FILE} to be '5', but got '{lines[1]}'"


def expected_result(sequence):
    chunk_size = len(sequence) // 5
    chunks = [sequence[i * chunk_size:(i + 1) * chunk_size] for i in range(5)]
    gc_counts = [chunk.count("G") + chunk.count("C") for chunk in chunks]
    selected = max(range(5), key=lambda i: gc_counts[i])
    refined = chunks[selected]
    midpoint = len(refined) // 2

    def motif_count(part):
        return sum(part[i:i + 3] == "CGT" for i in range(len(part) - 2))

    return selected, motif_count(refined[:midpoint]) + motif_count(refined[midpoint:])


def write_fasta(sequence, path):
    # Include multiple sequence lines and an additional header line; all header
    # lines must be ignored and all sequence lines concatenated.
    widths = (7, 13, 5, 19, 11)
    lines = [">generated_primary"]
    pos = 0
    n = 0
    while pos < len(sequence):
        width = widths[n % len(widths)]
        lines.append(sequence[pos:pos + width])
        pos += width
        n += 1
        if n == 3:
            lines.append(">generated_continuation")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def read_exact_result():
    assert os.path.isfile(RESULTS_FILE), f"Program did not create {RESULTS_FILE}"
    with open(RESULTS_FILE, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULTS_FILE}, found {len(lines)}"
    assert all(line.strip() == line and line for line in lines), "Result lines must be nonempty values"
    try:
        return int(lines[0]), int(lines[1])
    except ValueError as exc:
        raise AssertionError("Both result lines must be integers") from exc


def run_and_check(sequence):
    write_fasta(sequence, INPUT_FILE)
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    subprocess.run([BINARY], check=True, timeout=5, cwd="/home/user")
    assert read_exact_result() == expected_result(sequence)


def test_compile_and_execute_c_implementation():
    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()

    subprocess.run(["gcc", C_FILE, "-o", BINARY], check=True, timeout=20)

    try:
        # Verify the lowest-index tie rule.
        run_and_check("AT" * 50)

        # Use unpredictable cases so fixed output files or hardcoded answers do
        # not satisfy the verifier. The selected chunk also contains motifs in
        # each half and one motif crossing the half boundary.
        for _ in range(4):
            chunk_size = secrets.choice((40, 50, 60))
            selected = secrets.randbelow(5)
            chunks = []
            for index in range(5):
                if index == selected:
                    chunk = [secrets.choice("GC") for _ in range(chunk_size)]
                    half = chunk_size // 2
                    chunk[3:6] = "CGT"
                    chunk[half + 4:half + 7] = "CGT"
                    chunk[half - 1:half + 2] = "CGT"  # must not be counted
                    chunks.append("".join(chunk))
                else:
                    chunks.append("".join(secrets.choice("AT") for _ in range(chunk_size)))
            run_and_check("".join(chunks))
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)

    # Execute once more on the task's original input and leave its generated
    # results in place.
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    subprocess.run([BINARY], check=True, timeout=5, cwd="/home/user")
    assert read_exact_result() == (2, 5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
