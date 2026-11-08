#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

SOURCE = "/home/user/pcr_sim.cpp"
BINARY = "/home/user/simulate_fixed"
REBUILT = "/tmp/simulate_rebuilt"
FASTA = "/home/user/target.fasta"
LOG = "/home/user/stability.log"


def primer_gc_ratio():
    with open(FASTA, "r") as f:
        sequence = "".join(line.strip() for line in f if line.strip() and not line.startswith(">"))
    primer = sequence[:20].upper()
    assert len(primer) == 20, "target.fasta does not contain a 20-base primer."
    return sum(base in "GC" for base in primer) / 20.0


def expected_distance(gc_ratio):
    c = 0.1
    for _ in range(100):
        c += 0.05 * c * (1.0 - c) * gc_ratio

    # Match the explicitly permitted deterministic sequential accumulation.
    total = 0.0
    for _ in range(100000):
        total += c

    return abs(total - 50000.0)


def expected_output(gc_ratio):
    return f"{expected_distance(gc_ratio):.10f}"


def run_binary(path, gc_ratio, threads=4):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_DYNAMIC"] = "FALSE"
    result = subprocess.run(
        [path, format(gc_ratio, ".17g")],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    assert result.stderr == "", f"{path} wrote unexpected stderr: {result.stderr}"
    lines = result.stdout.splitlines()
    assert len(lines) == 1, f"{path} must print exactly one output line, got {lines!r}."
    return lines[0]


@pytest.fixture(scope="session", autouse=True)
def rebuild_submission():
    assert os.path.exists(SOURCE), f"File {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"Path {SOURCE} is not a file."

    with open(SOURCE, "r") as f:
        source_text = f.read()
    uncommented = re.sub(r"/\*.*?\*/", "", source_text, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    assert re.search(r"#\s*pragma\s+omp\s+parallel\b", uncommented), \
        "The submitted source does not retain an OpenMP parallel region."
    assert len(re.findall(r"\bsimulate_droplet\s*\(", uncommented)) >= 2, \
        "simulate_droplet is not called by the submitted program."

    result = subprocess.run(
        ["g++", "-O2", "-fopenmp", SOURCE, "-o", REBUILT],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"The submitted source does not compile: {result.stderr}"
    yield
    try:
        os.remove(REBUILT)
    except FileNotFoundError:
        pass


def test_simulate_fixed_executable():
    path = BINARY
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_stability_log():
    path = LOG
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {path}, found {len(lines)}."

    first_line = lines[0]
    for i, line in enumerate(lines):
        assert line == first_line, f"Line {i+1} ('{line}') differs from the first line ('{first_line}'). Non-determinism is still present."

    gc_ratio = primer_gc_ratio()
    expected_str = expected_output(gc_ratio)
    assert first_line == expected_str, f"The logged distance '{first_line}' does not match the expected deterministic value '{expected_str}'."

    # Execute the requested artifact five times and ensure the log reflects its output.
    actual = [run_binary(BINARY, gc_ratio, threads=4) for _ in range(5)]
    assert actual == lines, f"The five logged values do not match five executions of {BINARY}."


def test_submission_behavior_on_derived_inputs():
    gc_ratio = primer_gc_ratio()
    for ratio in (gc_ratio, 0.20, 0.70):
        expected = expected_output(ratio)
        installed = run_binary(BINARY, ratio, threads=3)
        rebuilt = run_binary(REBUILT, ratio, threads=3)
        assert installed == expected, f"{BINARY} produced '{installed}' for GC ratio {ratio}, expected '{expected}'."
        assert rebuilt == expected, f"Recompiled pcr_sim.cpp produced '{rebuilt}' for GC ratio {ratio}, expected '{expected}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
