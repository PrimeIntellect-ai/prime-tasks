#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import subprocess
import tempfile
import glob
import pytest

FILTER_BIN = "/home/user/filter"
REBUILT_BIN = "/app/src/filter"
SOURCE_DIR = "/app/src"
SOURCE_FILE = "/app/src/main.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
THRESHOLD = 42.15


def run_filter(binary, path):
    return subprocess.run(
        [binary, path], capture_output=True, timeout=10
    ).returncode


def oracle(path):
    with open(path, "r", encoding="utf-8") as f:
        tokens = f.read().split()
    count = int(tokens[0])
    assert len(tokens) == 1 + 6 * count
    values = [float(x) for x in tokens[1:]]
    for i in range(count):
        x, y, z, vx, vy, vz = values[6*i:6*i+6]
        energy = 0.5 * (vx*vx + vy*vy + vz*vz) + 0.5 * (x*x + y*y + z*z)
        if energy > THRESHOLD:
            return 1
    return 0


def particle_with_energy(rng, energy):
    while True:
        direction = [rng.uniform(-1.0, 1.0) for _ in range(6)]
        norm2 = sum(v*v for v in direction)
        if norm2 > 0.01:
            break
    scale = math.sqrt((2.0 * energy) / norm2)
    return [v * scale for v in direction]


@pytest.fixture(scope="session")
def rebuilt_binary():
    result = subprocess.run(
        ["make", "clean"], cwd=SOURCE_DIR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, result.stdout + result.stderr
    result = subprocess.run(
        ["make", "filter"], cwd=SOURCE_DIR, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(REBUILT_BIN)
    assert os.access(REBUILT_BIN, os.X_OK)
    return REBUILT_BIN


@pytest.fixture(scope="session")
def generated_cases():
    rng = random.SystemRandom()
    directory = tempfile.mkdtemp(prefix="trajectory-check-")
    cases = []
    labels = [0] * 7 + [1] * 7
    rng.shuffle(labels)

    for label in labels:
        count = 2048
        particles = [particle_with_energy(rng, rng.uniform(0.01, 41.5)) for _ in range(count)]
        chosen = rng.randrange(count)
        if label == 0:
            particles[chosen] = particle_with_energy(rng, rng.uniform(41.9, 42.14))
        else:
            particles[chosen] = particle_with_energy(rng, rng.uniform(42.16, 95.0))

        path = os.path.join(directory, secrets.token_hex(16) + ".bin")
        with open(path, "w", encoding="utf-8") as f:
            f.write(str(count) + "\n")
            for values in particles:
                f.write(" ".join(format(v, ".17g") for v in values) + "\n")
        cases.append((path, oracle(path)))

    assert {expected for _, expected in cases} == {0, 1}
    rng.shuffle(cases)
    return cases


def assert_openmp_linked(binary):
    result = subprocess.run(["ldd", binary], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run ldd on {binary}"
    assert "omp" in result.stdout.lower(), "Executable does not appear to be linked with OpenMP (-fopenmp)"

    symbols = subprocess.run(["nm", "-D", binary], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Failed to inspect dynamic symbols in {binary}"
    assert re.search(r"GOMP_parallel(?:_loop)?|__kmpc_fork_call", symbols.stdout), \
        "Executable links OpenMP but contains no OpenMP parallel-region call"


def test_executable_exists():
    assert os.path.isfile(FILTER_BIN), f"Executable not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"File at {FILTER_BIN} is not executable"


def test_openmp_linked():
    assert_openmp_linked(FILTER_BIN)


def test_validate_particles_contains_openmp_loop(rebuilt_binary):
    result = subprocess.run(
        ["gcc", "-fopenmp", "-E", SOURCE_FILE],
        cwd=SOURCE_DIR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, result.stdout + result.stderr

    lines = []
    for line in result.stdout.splitlines():
        if line.lstrip().startswith("#") and not re.match(r"\s*#\s*pragma\s+omp\b", line):
            continue
        lines.append(line)
    source = "\n".join(lines)

    match = re.search(r"\bint\s+validate_particles\s*\([^)]*\)\s*\{", source)
    assert match, "validate_particles definition was not found"
    start = match.start()
    brace = source.find("{", match.start())
    depth = 0
    end = None
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    assert end is not None, "Could not parse validate_particles body"
    body = source[start:end]

    combined = re.search(
        r"#\s*pragma\s+omp\s+parallel\s+for\b[^\n]*\n\s*for\s*\(", body, re.I
    )
    separate = (
        re.search(r"#\s*pragma\s+omp\s+parallel\b", body, re.I)
        and re.search(r"#\s*pragma\s+omp\s+for\b[^\n]*\n\s*for\s*\(", body, re.I)
    )
    assert combined or separate, "validate_particles does not contain an OpenMP-parallelized for loop"
    assert_openmp_linked(rebuilt_binary)


def test_generated_trajectories(generated_cases, rebuilt_binary):
    for path, expected in generated_cases:
        final_result = run_filter(FILTER_BIN, path)
        rebuilt_result = run_filter(rebuilt_binary, path)
        assert final_result == expected, f"Final filter misclassified generated trajectory {os.path.basename(path)}"
        assert rebuilt_result == expected, f"Source-built filter misclassified generated trajectory {os.path.basename(path)}"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([FILTER_BIN, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([FILTER_BIN, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msg = []
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_msg, " | ".join(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
