#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SEQUENCE_PATH = "/home/user/sequence.txt"
OUTPUT_PATH = "/home/user/integral.txt"
ORIGINAL_SEQUENCE = "ACGCGCATAT"


def compute_expected_integral(sequence: str) -> float:
    N = len(sequence)
    if N < 2:
        return 0.0

    S = []
    for char in sequence:
        if char in ('G', 'C'):
            S.append(1.0)
        elif char in ('A', 'T'):
            S.append(-1.0)
        else:
            S.append(0.0)

    u = [0.0] * N
    dt = 0.1
    alpha = 0.5

    for _ in range(2):
        u_next = [0.0] * N
        for i in range(1, N - 1):
            laplacian = u[i+1] - 2 * u[i] + u[i-1]
            u_next[i] = u[i] + dt * (alpha * laplacian + S[i])
        u = u_next

    return sum(u)


def test_sequence_fixture_unchanged():
    assert os.path.exists(SEQUENCE_PATH), f"The file {SEQUENCE_PATH} is missing. It should not be deleted."
    assert os.path.isfile(SEQUENCE_PATH), f"The path {SEQUENCE_PATH} is not a file."
    with open(SEQUENCE_PATH, "r") as f:
        sequence = f.read()
    assert sequence == ORIGINAL_SEQUENCE, "The provided DNA sequence was modified."


def test_integral_file_exists():
    """Test that the integral.txt file exists."""
    file_path = OUTPUT_PATH
    assert os.path.exists(file_path), f"The file {file_path} is missing. Did your C program write the output?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_integral_value():
    """Test that the integral.txt file contains the correct computed value."""
    seq_path = SEQUENCE_PATH
    assert os.path.exists(seq_path), f"The file {seq_path} is missing. It should not be deleted."

    with open(seq_path, "r") as f:
        sequence = f.read().strip()

    expected_integral = compute_expected_integral(sequence)
    expected_str = f"{expected_integral:.4f}"

    out_path = OUTPUT_PATH
    assert os.path.exists(out_path), f"The output file {out_path} is missing."

    with open(out_path, "r") as f:
        output_content = f.read().strip()

    assert output_content == expected_str, (
        f"Expected integral value '{expected_str}', but got '{output_content}'. "
        "Check your finite-difference implementation, boundary conditions, and trapezoidal rule."
    )


def find_c_sources():
    sources = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if name.lower().endswith(".c") and os.path.isfile(path):
                sources.append(path)
    return sorted(sources)


def compile_candidates(sources):
    source_groups = []
    if len(sources) > 1:
        source_groups.append(sources)
    source_groups.extend([[source] for source in sources])

    executables = []
    errors = []
    seen = set()
    for index, group in enumerate(source_groups):
        key = tuple(group)
        if key in seen:
            continue
        seen.add(key)
        executable = f"/tmp/submission_program_{index}"
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", *group, "-o", executable, "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        if result.returncode == 0 and os.path.isfile(executable):
            executables.append(executable)
        else:
            errors.append(f"{group}: {result.stderr[-1000:]}")
    return executables, errors


def exercise_program(executable, cases):
    for sequence in cases:
        with open(SEQUENCE_PATH, "w") as f:
            f.write(sequence)
        if os.path.lexists(OUTPUT_PATH):
            if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
                return False, f"{OUTPUT_PATH} is a directory"
            os.unlink(OUTPUT_PATH)

        try:
            result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            return False, f"timed out for sequence {sequence!r}"

        if result.returncode != 0:
            return False, f"exited with status {result.returncode} for sequence {sequence!r}"
        if not os.path.isfile(OUTPUT_PATH):
            return False, f"did not create {OUTPUT_PATH} for sequence {sequence!r}"

        with open(OUTPUT_PATH, "r") as f:
            actual = f.read().strip()
        expected = f"{compute_expected_integral(sequence):.4f}"
        if actual != expected:
            return False, f"for sequence {sequence!r}, expected {expected!r} but got {actual!r}"

    return True, ""


def test_c_program_compiles_and_runs_on_additional_inputs():
    sources = find_c_sources()
    assert sources, "No C source file was found under /home/user."

    executables, compile_errors = compile_candidates(sources)
    assert executables, "No submitted C source could be compiled. " + " | ".join(compile_errors)

    rng = random.SystemRandom()
    cases = [
        "GC",
        "GCG",
        "ATA",
        "GCAATCG",
        "TGGCCATAACGT",
        "GC" + "ATGC" * 8 + "AT",
    ]
    for length in (9, 17, 31, 53, 73):
        cases.append("".join(rng.choice("ACGT") for _ in range(length)))

    failures = []
    for executable in executables:
        passed, reason = exercise_program(executable, cases)
        if passed:
            return
        failures.append(f"{executable}: {reason}")

    assert False, "No compiled C program produced correct results when executed. " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
