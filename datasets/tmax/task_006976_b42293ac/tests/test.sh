#!/bin/bash
set +e
mkdir -p /logs/verifier
score=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/seq_analyzer"
BINARY = os.path.join(PROJECT, "target", "debug", "seq_analyzer")
OUTPUT = "/home/user/kl_divergence.txt"


def reference_profile(seq):
    profile = [0.0] * 10
    pos = 0
    window_size = 10
    step = 4

    while pos + window_size <= len(seq):
        window = seq[pos:pos + window_size]
        a_count = window.count("A")

        if a_count > 5:
            step = max(1, step // 2)
        elif a_count < 2:
            step += 1

        for k in range(10):
            re = 0.0
            im = 0.0
            for n, base in enumerate(window):
                val = {"A": 1.0, "C": 2.0, "G": 3.0, "T": 4.0}.get(base, 0.0)
                angle = -2.0 * math.pi * k * n / window_size
                re += val * math.cos(angle)
                im += val * math.sin(angle)
            profile[k] += re * re + im * im

        pos += step

    total = sum(profile)
    if total > 0.0:
        return [value / total for value in profile]
    return [0.1] * 10


def reference_kl(seq1, seq2):
    p = reference_profile(seq1)
    q = reference_profile(seq2)
    return sum(
        p_i * math.log(p_i / q_i)
        for p_i, q_i in zip(p, q)
        if p_i > 0.0 and q_i > 0.0
    )


def run_binary(seq1, seq2):
    with tempfile.TemporaryDirectory() as directory:
        first = os.path.join(directory, "first.txt")
        second = os.path.join(directory, "second.txt")
        with open(first, "w") as handle:
            handle.write(seq1 + "\n")
        with open(second, "w") as handle:
            handle.write(seq2 + "\n")

        try:
            result = subprocess.run(
                [BINARY, first, second],
                cwd=PROJECT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The compiled program timed out on a repetitive sequence; the adaptive step still stalls.")

        assert result.returncode == 0, f"Compiled program failed: {result.stderr}"
        text = result.stdout.strip()
        try:
            value = float(text)
        except ValueError:
            pytest.fail(f"Program output {text!r} is not a floating-point number.")
        assert math.isfinite(value), f"Program produced a non-finite value: {text}"
        return value


def test_compiled_artifact_exists():
    assert os.path.isfile(BINARY), "cargo build did not produce the seq_analyzer executable."
    assert os.access(BINARY, os.X_OK), "The compiled seq_analyzer artifact is not executable."


def test_kl_divergence_file_exists():
    path = OUTPUT
    assert os.path.isfile(path), f"Output file {path} does not exist. Did you save the output of the fixed program?"


def test_kl_divergence_value():
    path = OUTPUT
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {path} ('{content}') as a floating-point number.")

    expected_val = 0.003926
    tolerance = 1e-4
    assert abs(val - expected_val) < tolerance, (
        f"Computed KL divergence {val} is not within {tolerance} of the expected value {expected_val}. "
        "Check your step-size clamping logic."
    )


def test_saved_output_matches_compiled_program():
    with open(OUTPUT, "r") as handle:
        saved = float(handle.read().strip())
    with open(os.path.join(PROJECT, "data", "seqA.txt")) as handle:
        seq1 = handle.read().strip()
    with open(os.path.join(PROJECT, "data", "seqB.txt")) as handle:
        seq2 = handle.read().strip()
    actual = run_binary(seq1, seq2)
    assert abs(saved - actual) < 1e-9, "kl_divergence.txt is not the output of the compiled program on the provided sequences."


def test_adaptive_step_clamps_to_one_on_derived_inputs():
    alphabet = "ACGT"
    random_tail_1 = "".join(secrets.choice(alphabet) for _ in range(53))
    random_tail_2 = "".join(secrets.choice(alphabet) for _ in range(57))
    cases = [
        ("A" * 24 + random_tail_1, "A" * 18 + "CGTACGTA" + random_tail_2),
        ("AAAAAACAAAAAGAAAAATTTCCCGGGATCGATCG", "AAAAAAGAAAAAACCCCCGTGTGTATATCGCGC"),
    ]

    for seq1, seq2 in cases:
        expected = reference_kl(seq1, seq2)
        actual = run_binary(seq1, seq2)
        assert abs(actual - expected) < 1e-5, (
            f"Compiled program returned {actual}, but clamping the adaptive step to 1 gives {expected}."
        )


def test_main_rs_modified():
    path = "/home/user/seq_analyzer/src/main.rs"
    assert os.path.isfile(path), f"Source file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "fn compute_spectral_profile" in content, "main.rs seems to be heavily modified or missing the target function."
TEST_EOF

if cd /home/user/seq_analyzer \
   && cargo build --quiet \
   && timeout 15s ./regression_test.sh; then
    if cd / && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        score=1
    fi
fi

echo "$score" > /logs/verifier/reward.txt
exit 0
