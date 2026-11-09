#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/bio_divergence"
CARGO_TOML = os.path.join(PROJECT_DIR, "Cargo.toml")
MAIN_RS = os.path.join(PROJECT_DIR, "src", "main.rs")
FASTA_PATH = "/home/user/input.fasta"
CSV_PATH = "/home/user/background.csv"
OUTPUT_PATH = "/home/user/kl_divergence.txt"
STD_AAS = "ACDEFGHIKLMNPQRSTVWY"


def expected_kl():
    std_aas = set(STD_AAS)
    counts = {aa: 1 for aa in std_aas}

    with open(FASTA_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(">"):
                for char in line:
                    if char in std_aas:
                        counts[char] += 1

    total_count = sum(counts.values())
    p = {aa: count / total_count for aa, count in counts.items()}

    q = {}
    with open(CSV_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                parts = line.split(",")
                aa = parts[0].strip()
                prob = float(parts[1].strip())
                if aa in std_aas:
                    q[aa] = prob

    kl = 0.0
    for aa in std_aas:
        if p[aa] > 0 and q[aa] > 0:
            kl += p[aa] * math.log(p[aa] / q[aa])
    return f"{kl:.4f}"


def run_project():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "HOME=/home/user",
            "cargo", "run", "--quiet", "--manifest-path", CARGO_TOML,
        ],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "Rust project failed to compile or run.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "Running the Rust project did not create the output file"

    with open(OUTPUT_PATH, "r") as f:
        actual = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", actual), (
        f"Output must contain one value rounded to exactly 4 decimal places, got {actual!r}"
    )
    return actual


def write_random_fixture(case_number):
    rng = secrets.SystemRandom()

    # Include zero-count amino acids, ignored symbols, gaps, and amino-acid
    # letters in headers. Values are generated only after the agent has run.
    selected = rng.sample(list(STD_AAS), 7 + case_number * 3)
    sequence = []
    for aa in selected:
        sequence.extend([aa] * (1 + secrets.randbelow(12)))
    sequence.extend(list("X-BZ*?"))
    rng.shuffle(sequence)

    split1 = max(1, len(sequence) // 3)
    split2 = max(split1 + 1, 2 * len(sequence) // 3)
    with open(FASTA_PATH, "w") as f:
        f.write(">header_ACDEFGHIKLMNPQRSTVWY_should_not_be_counted\n")
        f.write("".join(sequence[:split1]) + "\n")
        f.write("".join(sequence[split1:split2]) + "\n")
        f.write(">another_sequence\n")
        f.write("".join(sequence[split2:]) + "\n")

    weights = [1 + secrets.randbelow(10000) for _ in STD_AAS]
    total = sum(weights)
    with open(CSV_PATH, "w") as f:
        for aa, weight in zip(STD_AAS, weights):
            f.write(f"{aa},{weight / total:.12f}\n")


def test_rust_project_exists():
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory is missing at {PROJECT_DIR}"
    assert os.path.isfile(CARGO_TOML), f"Cargo.toml is missing in {PROJECT_DIR}, ensuring it is a valid Rust project"
    assert os.path.isfile(MAIN_RS), f"Rust source file is missing at {MAIN_RS}"


def test_kl_divergence_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"
    expected_val = expected_kl()
    with open(OUTPUT_PATH, "r") as f:
        actual_val = f.read().strip()
    assert actual_val == expected_val, f"Expected KL divergence to be '{expected_val}', but got '{actual_val}'"


def test_compiles_runs_and_processes_runtime_inputs():
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    try:
        # First ensure the submitted Cargo project itself regenerates the result.
        expected = expected_kl()
        actual = run_project()
        assert actual == expected, f"Executed project produced '{actual}', expected '{expected}'"

        # Exercise fresh, unpredictable fixtures so a prewritten fixed answer cannot pass.
        for case_number in range(2):
            write_random_fixture(case_number)
            expected = expected_kl()
            actual = run_project()
            assert actual == expected, (
                f"Runtime fixture {case_number + 1}: expected '{expected}', got '{actual}'"
            )
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if original_output is not None:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
