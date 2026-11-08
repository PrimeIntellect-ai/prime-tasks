#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/model_fit.c"
EXECUTABLE = "/home/user/model_fit"
RESULTS = "/home/user/results.json"
GENOME = "/home/user/genome.txt"
AFFINITY = "/home/user/affinity.csv"
REQUIRED_KEYS = [
    "X_s", "mu", "ci_lower", "ci_upper",
    "integral_D1", "integral_D2", "bins_D1", "bins_D2"
]


def compile_program():
    proc = subprocess.run(
        ["gcc", "-O2", "-o", EXECUTABLE, SOURCE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Compilation failed:\n{proc.stdout}{proc.stderr}"
    assert os.path.isfile(EXECUTABLE), "Compilation did not create /home/user/model_fit"
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/model_fit is not executable"


def run_program(expected_genome_bytes, expected_affinity_bytes):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Program execution failed:\n{proc.stdout}{proc.stderr}"
    assert os.path.isfile(RESULTS), "Program did not generate /home/user/results.json"
    with open(GENOME, "rb") as f:
        assert f.read() == expected_genome_bytes, "Program modified genome.txt"
    with open(AFFINITY, "rb") as f:
        assert f.read() == expected_affinity_bytes, "Program modified affinity.csv"


def load_results():
    try:
        with open(RESULTS, "r") as f:
            res = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("results.json is not a valid JSON file.")

    for key in REQUIRED_KEYS:
        assert key in res, f"Key '{key}' is missing from results.json"
    for key in REQUIRED_KEYS[:6]:
        assert isinstance(res[key], (int, float)) and not isinstance(res[key], bool), f"{key} must be numeric"
        assert math.isfinite(res[key]), f"{key} must be finite"
    for key in REQUIRED_KEYS[6:]:
        assert isinstance(res[key], int) and not isinstance(res[key], bool), f"{key} must be an integer"
    return res


def bootstrap_ci(vals):
    assert len(vals) == 50
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.srand.restype = None
    libc.rand.argtypes = []
    libc.rand.restype = ctypes.c_int
    libc.srand(42)
    means = []
    for _ in range(10000):
        total = 0.0
        for _ in range(50):
            total += vals[libc.rand() % 50]
        means.append(total / 50.0)
    means.sort()
    return means[250], means[9750]


def f_val(x, mu, xs):
    return mu * math.exp(-50.0 * (x - xs) ** 2)


def trapz(a, b, n, mu, xs):
    h = (b - a) / n
    total = 0.5 * (f_val(a, mu, xs) + f_val(b, mu, xs))
    for i in range(1, n):
        total += f_val(a + i * h, mu, xs)
    return total * h


def refine(a, b, mu, xs):
    n = 10
    previous = trapz(a, b, n, mu, xs)
    while True:
        n *= 2
        current = trapz(a, b, n, mu, xs)
        if abs(current - previous) < 1e-6:
            return current, n
        previous = current


def verify_results(genome_bytes, affinity_bytes):
    res = load_results()
    genome = genome_bytes.decode().rstrip("\n")
    vals = [float(line.strip()) for line in affinity_bytes.decode().splitlines() if line.strip()]
    assert len(vals) == 50, "affinity.csv must contain 50 values"

    match_index = genome.find("TTAGGCAT")
    assert match_index != -1, "Primer sequence 'TTAGGCAT' not found in genome.txt"
    expected_xs = match_index / len(genome)
    expected_mu = sum(vals) / len(vals)
    expected_lower, expected_upper = bootstrap_ci(vals)

    assert abs(res["X_s"] - expected_xs) < 1e-5, f"Expected X_s approx {expected_xs}, got {res['X_s']}"
    assert abs(res["mu"] - expected_mu) < 1e-5, f"Expected mu approx {expected_mu}, got {res['mu']}"

    # Retain the original range assertions and additionally require the exact
    # deterministic 10,000-resample result, allowing only six-decimal rounding.
    assert expected_mu - 1.0 < res["ci_lower"] < expected_mu, f"ci_lower {res['ci_lower']} out of expected range"
    assert expected_mu < res["ci_upper"] < expected_mu + 1.0, f"ci_upper {res['ci_upper']} out of expected range"
    assert abs(res["ci_lower"] - expected_lower) <= 5.1e-7, f"Expected ci_lower {expected_lower:.6f}, got {res['ci_lower']}"
    assert abs(res["ci_upper"] - expected_upper) <= 5.1e-7, f"Expected ci_upper {expected_upper:.6f}, got {res['ci_upper']}"

    int1, bins1 = refine(0.0, expected_xs, expected_mu, expected_xs)
    int2, bins2 = refine(expected_xs, 1.0, expected_mu, expected_xs)
    assert abs(res["integral_D1"] - int1) < 1e-4, f"Expected integral_D1 approx {int1}, got {res['integral_D1']}"
    assert abs(res["integral_D2"] - int2) < 1e-4, f"Expected integral_D2 approx {int2}, got {res['integral_D2']}"
    assert res["bins_D1"] == bins1, f"Expected bins_D1={bins1}, got {res['bins_D1']}"
    assert res["bins_D2"] == bins2, f"Expected bins_D2={bins2}, got {res['bins_D2']}"


def test_c_source_and_executable_exist_and_run():
    assert os.path.isfile(SOURCE), "/home/user/model_fit.c does not exist or is not a regular file"
    assert os.path.isfile(EXECUTABLE), "Compiled executable /home/user/model_fit does not exist"
    assert os.path.exists(RESULTS), "/home/user/results.json does not exist"

    with open(GENOME, "rb") as f:
        original_genome = f.read()
    with open(AFFINITY, "rb") as f:
        original_affinity = f.read()

    compile_program()
    run_program(original_genome, original_affinity)
    verify_results(original_genome, original_affinity)


def test_program_handles_fresh_inputs():
    with open(GENOME, "rb") as f:
        original_genome = f.read()
    with open(AFFINITY, "rb") as f:
        original_affinity = f.read()

    rng = secrets.SystemRandom()
    prefix_len = rng.randrange(73, 420)
    suffix_len = rng.randrange(211, 760)
    challenge_genome = ("A" * prefix_len + "TTAGGCAT" + "C" * suffix_len).encode()
    challenge_vals = [
        (rng.randrange(1200, 9401) / 1000.0) + ((i % 7) - 3) * 0.013
        for i in range(50)
    ]
    challenge_affinity = "".join(f"{value:.9f}\n" for value in challenge_vals).encode()

    try:
        with open(GENOME, "wb") as f:
            f.write(challenge_genome)
        with open(AFFINITY, "wb") as f:
            f.write(challenge_affinity)
        run_program(challenge_genome, challenge_affinity)
        verify_results(challenge_genome, challenge_affinity)
    finally:
        with open(GENOME, "wb") as f:
            f.write(original_genome)
        with open(AFFINITY, "wb") as f:
            f.write(original_affinity)
        # Leave results.json corresponding to the instructed, original inputs.
        run_program(original_genome, original_affinity)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
