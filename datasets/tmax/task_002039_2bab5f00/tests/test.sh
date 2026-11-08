#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/spectral_fit")
FASTA = Path("/home/user/sequence.fasta")
RESULT = Path("/home/user/spectral_result.json")
CANONICAL_FASTA = ">seq1\nACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDEACDE\n"


def run_program():
    if RESULT.exists():
        RESULT.unlink()
    completed = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "The Rust program failed to run.\nstdout:\n"
        + completed.stdout
        + "\nstderr:\n"
        + completed.stderr
    )
    assert os.path.isfile(RESULT), (
        f"File {RESULT} is missing. The Rust program did not create the output file."
    )
    try:
        with RESULT.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULT} does not contain valid JSON.")


def expected_for(sequence):
    values = [float(ord(ch)) for ch in sequence]
    n = len(values)
    mean = sum(values) / n
    centered = [value - mean for value in values]
    transforms = []
    for k in range(1, n // 2):
        xk = sum(
            value * cmath.exp(-2j * math.pi * k * index / n)
            for index, value in enumerate(centered)
        )
        transforms.append((abs(xk), k, xk))
    _, k, xk = max(transforms, key=lambda item: item[0])
    amplitude = 2.0 * abs(xk) / n
    phase = math.atan2(xk.imag, xk.real)
    return {"k": k, "A": round(amplitude, 2), "phi": round(phase, 2)}


def assert_result(data, expected):
    assert "k" in data, "The JSON result is missing the 'k' key."
    assert "A" in data, "The JSON result is missing the 'A' key."
    assert "phi" in data, "The JSON result is missing the 'phi' key."
    assert data["k"] == expected["k"], (
        f"Expected k to be {expected['k']}, but got {data['k']}."
    )
    assert abs(data["A"] - expected["A"]) < 1e-3, (
        f"Expected A to be {expected['A']}, but got {data['A']}."
    )
    assert abs(data["phi"] - expected["phi"]) < 1e-3, (
        f"Expected phi to be {expected['phi']}, but got {data['phi']}."
    )


def test_rust_spectral_program():
    assert PROJECT.is_dir(), "The Cargo project /home/user/spectral_fit is missing."
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing."
    assert (PROJECT / "src" / "main.rs").is_file(), "src/main.rs is missing."

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--format-version=1", "--no-deps"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert metadata_run.returncode == 0, "The directory is not a valid Cargo project."
    metadata = json.loads(metadata_run.stdout)
    assert metadata.get("packages"), "The Cargo project contains no package."
    assert any(
        "bin" in target.get("kind", [])
        for package in metadata["packages"]
        for target in package.get("targets", [])
    ), "The Cargo project has no Rust binary target."
    assert any(
        dependency.get("name") == "rustfft"
        for package in metadata["packages"]
        for dependency in package.get("dependencies", [])
    ), "rustfft must be declared as a Cargo dependency."

    rust_sources = list(PROJECT.rglob("*.rs"))
    assert rust_sources, "The project contains no Rust source files."
    assert any("rustfft" in source.read_text(errors="ignore") for source in rust_sources), (
        "The Rust source does not use rustfft."
    )

    original_fasta = FASTA.read_bytes() if FASTA.exists() else None
    try:
        # Preserve the original verifier's assertions, but require the program to
        # regenerate the result from the canonical input.
        FASTA.write_text(CANONICAL_FASTA)
        canonical = run_program()
        assert_result(canonical, {"k": 16, "A": 1.80, "phi": 2.55})

        # Use an unpredictable valid FASTA input so hardcoded JSON cannot pass.
        alphabet = "ACDEFGHIKLMNPQRSTVWY"
        while True:
            sequence = "".join(secrets.choice(alphabet) for _ in range(68))
            expected = expected_for(sequence)
            # Avoid exceptionally close peak ties and rounding boundaries.
            values = [float(ord(ch)) for ch in sequence]
            mean = sum(values) / len(values)
            magnitudes = []
            for k in range(1, len(values) // 2):
                xk = sum(
                    (value - mean) * cmath.exp(-2j * math.pi * k * i / len(values))
                    for i, value in enumerate(values)
                )
                magnitudes.append(abs(xk))
            ordered = sorted(magnitudes, reverse=True)
            if ordered[0] > ordered[1] * 1.02:
                break

        FASTA.write_text(">random_sequence\n" + sequence + "\n")
        dynamic = run_program()
        assert_result(dynamic, expected)
    finally:
        if original_fasta is None:
            FASTA.unlink(missing_ok=True)
        else:
            FASTA.write_bytes(original_fasta)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
