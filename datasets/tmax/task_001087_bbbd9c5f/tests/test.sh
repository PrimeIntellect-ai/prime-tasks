#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/gc_bootstrap")
MAIN_RS = PROJECT / "src" / "main.rs"
RESULT = Path("/home/user/result.txt")
FASTA = Path("/home/user/sequences.fasta")

TRUTH_MAIN_RS = r'''use rand::{SeedableRng, Rng};
use rand_chacha::ChaCha8Rng;
use rayon::prelude::*;
use std::fs;

fn main() {
    let fasta = fs::read_to_string("/home/user/sequences.fasta").expect("Unable to read fasta");
    let mut gc_contents: Vec<f64> = Vec::new();

    for line in fasta.lines() {
        if !line.starts_with('>') && !line.is_empty() {
            let gc = line.chars().filter(|&c| c == 'G' || c == 'C').count() as f64;
            gc_contents.push(gc / line.len() as f64);
        }
    }

    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let mut bootstrap_means = Vec::new();

    let n = gc_contents.len();
    for _ in 0..1000 {
        let sample: Vec<f64> = (0..n).map(|_| {
            let idx = rng.gen_range(0..n);
            gc_contents[idx]
        }).collect();

        // Fixed: Sequential reduction
        let sum: f64 = sample.iter().sum();
        bootstrap_means.push(sum / n as f64);
    }

    let overall_mean: f64 = bootstrap_means.iter().sum::<f64>() / bootstrap_means.len() as f64;
    println!("{:.10}", overall_mean);
}
'''

TRUTH_CARGO_TOML = '''[package]
name = "gc_bootstrap_truth"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
rand_chacha = "0.3"
rayon = "1.10.0"
'''


def run_command(command, env=None, timeout=240):
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        env=env,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(map(str, command))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert re.fullmatch(r"-?\d+\.\d{10}\n?", result.stdout), (
        f"Program must print exactly one floating-point number with 10 decimal places; "
        f"got {result.stdout!r}"
    )
    return result.stdout.strip()


def test_result_exists():
    path = "/home/user/result.txt"
    assert os.path.exists(path), f"Missing {path}"
    assert os.path.isfile(path), f"{path} is not a file"


def test_main_rs_fixed():
    path = "/home/user/gc_bootstrap/src/main.rs"
    assert os.path.exists(path), f"Missing {path}"
    assert os.path.isfile(path), f"{path} is not a file"

    with open(path, "r") as f:
        content = f.read()

    assert "sample.par_iter().sum()" not in content, (
        "The non-deterministic parallel reduction `sample.par_iter().sum()` "
        "is still present in main.rs"
    )


def test_correct_output(tmp_path):
    # Build an independent known-correct implementation for expected outputs.
    truth_dir = tmp_path / "gc_bootstrap_truth"
    (truth_dir / "src").mkdir(parents=True)
    (truth_dir / "Cargo.toml").write_text(TRUTH_CARGO_TOML)
    (truth_dir / "src" / "main.rs").write_text(TRUTH_MAIN_RS)

    build_truth = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", str(truth_dir / "Cargo.toml")],
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert build_truth.returncode == 0, (
        "Failed to compile the truth Rust code\n"
        f"stdout:\n{build_truth.stdout}\nstderr:\n{build_truth.stderr}"
    )
    truth_binary = truth_dir / "target" / "release" / "gc_bootstrap_truth"

    expected_output = run_command([str(truth_binary)])

    # Compile and execute the student's actual project. Varying Rayon thread counts
    # also ensures the submitted program is reproducible rather than retaining a
    # parallel floating-point reduction with altered spelling.
    student_outputs = []
    for threads in ("1", "2", "4"):
        env = os.environ.copy()
        env["RAYON_NUM_THREADS"] = threads
        student_outputs.append(run_command([
            "cargo", "run", "--quiet", "--release",
            "--manifest-path", str(PROJECT / "Cargo.toml"),
        ], env=env))

    assert all(output == expected_output for output in student_outputs), (
        f"The submitted program did not produce the sequential reference output. "
        f"Expected {expected_output!r}, got {student_outputs!r}"
    )

    with open(RESULT, "r") as f:
        raw_student_result = f.read()
    student_output = raw_student_result.strip()

    assert student_output == expected_output, (
        f"Incorrect value in result.txt. Expected '{expected_output}', "
        f"got '{student_output}'"
    )
    assert re.fullmatch(r"-?\d+\.\d{10}\n?", raw_student_result), (
        "result.txt must contain only the single floating-point number exactly "
        f"as printed; got {raw_student_result!r}"
    )

    # Exercise both implementations on additional verifier-generated FASTA data
    # so a hard-coded output or a nonfunctional source file cannot pass.
    original_fasta = FASTA.read_bytes()
    probes = []
    for count, offset in ((73, 11), (137, 29)):
        lines = []
        alphabet = "ACGT"
        for i in range(count):
            length = 31 + ((i * 17 + offset) % 113)
            seq = "".join(alphabet[(i * 7 + j * 13 + j * j + offset) % 4] for j in range(length))
            lines.extend((f">probe_{offset}_{i}", seq))
        probes.append("\n".join(lines) + "\n")

    try:
        for probe in probes:
            FASTA.write_text(probe)
            expected_probe = run_command([str(truth_binary)])
            env = os.environ.copy()
            env["RAYON_NUM_THREADS"] = "4"
            actual_probe = run_command([
                "cargo", "run", "--quiet", "--release",
                "--manifest-path", str(PROJECT / "Cargo.toml"),
            ], env=env)
            assert actual_probe == expected_probe, (
                "The submitted program failed a verifier-generated FASTA input: "
                f"expected {expected_probe!r}, got {actual_probe!r}"
            )
    finally:
        FASTA.write_bytes(original_fasta)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
