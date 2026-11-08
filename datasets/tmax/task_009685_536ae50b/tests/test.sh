#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/freq_svd"
FASTA_FILE = "/home/user/data/sequences.fasta"
OUTPUT_FILE = "/home/user/output.txt"


def test_rust_project_structure():
    """Verify that the Rust project directory and essential files exist."""
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")

    assert os.path.isdir(PROJECT_DIR), f"Rust project directory not found at {PROJECT_DIR}"
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found at {cargo_toml}"
    assert os.path.isfile(main_rs), f"src/main.rs not found at {main_rs}"


def test_cargo_toml_dependencies():
    """Verify that nalgebra is listed as a real Cargo dependency."""
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")

    with open(cargo_toml, "r") as f:
        content = f.read()

    assert "nalgebra" in content, "The 'nalgebra' crate is missing from Cargo.toml dependencies"

    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Cargo metadata failed:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    packages = [p for p in metadata["packages"] if p["manifest_path"] == cargo_toml]
    assert packages, "Cargo.toml does not describe a valid Cargo package"
    assert any(d["name"] == "nalgebra" for d in packages[0]["dependencies"]), \
        "The nalgebra text is present, but nalgebra is not a Cargo dependency"


def test_output_file_contents():
    """Verify the initially produced output for the provided FASTA file."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"

    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    expected_value = "13.435"
    assert content == expected_value, \
        f"Expected output file to contain '{expected_value}', but found '{content}'"


def largest_singular_value(rows):
    """Compute sqrt(max eigenvalue(A^T A)) using Jacobi rotations."""
    matrix = [[sum(float(row[i] * row[j]) for row in rows) for j in range(4)]
              for i in range(4)]

    for _ in range(100):
        p, q = max(((i, j) for i in range(4) for j in range(i + 1, 4)),
                   key=lambda pair: abs(matrix[pair[0]][pair[1]]))
        apq = matrix[p][q]
        if abs(apq) < 1e-13:
            break

        app = matrix[p][p]
        aqq = matrix[q][q]
        tau = (aqq - app) / (2.0 * apq)
        t = math.copysign(1.0, tau) / (abs(tau) + math.sqrt(1.0 + tau * tau))
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c

        for k in range(4):
            if k == p or k == q:
                continue
            akp = matrix[k][p]
            akq = matrix[k][q]
            matrix[k][p] = matrix[p][k] = c * akp - s * akq
            matrix[k][q] = matrix[q][k] = s * akp + c * akq

        matrix[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        matrix[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        matrix[p][q] = matrix[q][p] = 0.0

    return math.sqrt(max(0.0, max(matrix[i][i] for i in range(4))))


def make_case(rng):
    rows = []
    fasta_parts = []
    for index in range(rng.randint(3, 8)):
        counts = [rng.randint(0, 24) for _ in range(4)]
        if sum(counts) == 0:
            counts[rng.randrange(4)] = 1
        rows.append(counts)

        bases = []
        for base, count in zip("ACGT", counts):
            bases.extend(base.lower() if rng.randrange(2) else base for _ in range(count))
        bases.extend(list("N-x?"))
        rng.shuffle(bases)
        sequence = "".join(bases)
        lines = []
        while sequence:
            width = rng.randint(1, 13)
            lines.append(sequence[:width])
            sequence = sequence[width:]
        fasta_parts.append(f">random_{index}_ACGT_in_header\n" + "\n".join(lines) + "\n")

    return "".join(fasta_parts), rows


def run_program():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--bin", "freq_svd"],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"The Rust project failed to compile or run:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(OUTPUT_FILE), "Running the Rust program did not create /home/user/output.txt"
    with open(OUTPUT_FILE, "r") as f:
        value = f.read().strip()
    assert re.fullmatch(r"[0-9]+\.[0-9]{3}", value), \
        f"Output must contain only a nonnegative number with exactly 3 decimals, found {value!r}"
    return value


def test_compiled_program_parses_fasta_and_computes_svd():
    """Compile and execute the submission on verifier-generated FASTA matrices."""
    with open(FASTA_FILE, "rb") as f:
        original_fasta = f.read()

    try:
        # Re-run on the supplied input so a prewritten output cannot pass.
        assert run_program() == "13.435"

        rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
        checked = 0
        while checked < 3:
            fasta, rows = make_case(rng)
            singular = largest_singular_value(rows)
            # Avoid the exceedingly rare cross-language half-rounding boundary.
            if abs((singular * 1000.0) % 1.0 - 0.5) < 1e-7:
                continue
            expected = f"{singular:.3f}"
            with open(FASTA_FILE, "w") as f:
                f.write(fasta)
            actual = run_program()
            assert actual == expected, \
                f"For a verifier-generated FASTA matrix, expected {expected}, found {actual}"
            checked += 1
    finally:
        with open(FASTA_FILE, "wb") as f:
            f.write(original_fasta)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
