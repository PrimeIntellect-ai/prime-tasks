#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import secrets
import subprocess
import tempfile

import pytest

DATA_PATH = "/home/user/data.csv"
SOURCE_PATH = "/home/user/stats_calc.c"
BINARY_PATH = "/home/user/stats_calc"
RESULTS_PATH = "/home/user/results.txt"
N = 100
B = 10000


def read_data():
    assert os.path.isfile(DATA_PATH), "data.csv is missing."
    with open(DATA_PATH, "r") as f:
        data = [int(line.strip()) for line in f if line.strip()]
    assert len(data) == N, "data.csv should have 100 values."
    return data


def expected_output(data):
    # Use the same libc PRNG required by the C program, while deriving all
    # expected statistics independently from the current test data.
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.argtypes = []
    libc.rand.restype = ctypes.c_int
    libc.srand(42)

    boot_means = []
    for _ in range(B):
        total = 0
        for _ in range(N):
            total += data[libc.rand() % N]
        boot_means.append(total / float(N))
    boot_means.sort()

    orig_mean = sum(data) / float(N)
    post_mean = (50.0 / 25.0 + N * orig_mean / 100.0) / (1.0 / 25.0 + N / 100.0)
    return (
        f"Bootstrap 95% CI: [{boot_means[250]:.3f}, {boot_means[9749]:.3f}\n"
        f"Posterior Mean: {post_mean:.3f}\n"
    )


def run_program(path):
    completed = subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert completed.returncode == 0, (
        f"{path} exited with status {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout


def strip_c_comments_and_literals(source):
    token = re.compile(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        re.DOTALL,
    )
    return token.sub(" ", source)


def test_results_txt_exists():
    assert os.path.isfile(RESULTS_PATH), "/home/user/results.txt does not exist."


def test_posterior_mean_correct():
    with open(RESULTS_PATH, "r") as f:
        content = f.read()

    match = re.search(r"Posterior Mean:\s*([0-9.]+)", content)
    assert match is not None, "Could not find 'Posterior Mean: <value>' in results.txt."
    post_mean = float(match.group(1))

    data = read_data()
    orig_mean = sum(data) / 100.0
    expected_post_mean = (50.0 / 25.0 + 100 * orig_mean / 100.0) / (1.0 / 25.0 + 100 / 100.0)
    assert math.isclose(post_mean, expected_post_mean, abs_tol=0.002), \
        f"Expected Posterior Mean to be ~{expected_post_mean:.3f}, but found {post_mean:.3f}."


def test_bootstrap_ci_not_truncated():
    with open(RESULTS_PATH, "r") as f:
        content = f.read()

    match = re.search(r"Bootstrap 95% CI:\s*\[([0-9.]+),\s*([0-9.]+)\]", content)
    assert match is not None, "Could not find 'Bootstrap 95% CI: [lower, upper]' in results.txt."
    lower_bound, upper_bound = match.groups()
    assert "." in lower_bound and "." in upper_bound, "CI bounds must be floats."
    lower_frac = lower_bound.split(".")[1]
    upper_frac = upper_bound.split(".")[1]
    assert lower_frac != "000" or upper_frac != "000", \
        "CI bounds end in .000, which indicates the integer division bug is likely still present."


def test_c_code_fixed_and_seeded():
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert re.search(r"boot_means\[i\]\s*=\s*sum\s*/\s*N\s*;", content) is None, \
        "The integer division bug 'sum / N' is still present in stats_calc.c."

    code = strip_c_comments_and_literals(content)
    seed_calls = list(re.finditer(r"\bsrand\s*\(\s*42\s*\)\s*;", code))
    all_srand_calls = list(re.finditer(r"\bsrand\s*\(", code))
    assert len(seed_calls) == 1 and len(all_srand_calls) == 1, \
        "stats_calc.c must call srand(42); exactly once."
    first_rand = re.search(r"\brand\s*\(", code)
    assert first_rand is not None and seed_calls[0].start() < first_rand.start(), \
        "srand(42); must occur before bootstrap sampling begins."

    assert os.path.isfile(BINARY_PATH), "The compiled binary stats_calc is missing."
    assert os.access(BINARY_PATH, os.X_OK), "The compiled stats_calc is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "stats_calc must be a compiled executable."


def test_program_execution_and_bootstrap_values():
    original_bytes = open(DATA_PATH, "rb").read()
    original_data = read_data()
    with open(RESULTS_PATH, "r") as f:
        saved_results = f.read()

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "stats_calc")
        compile_result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt, "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"stats_calc.c does not compile: {compile_result.stderr}"

        try:
            expected = expected_output(original_data)
            assert saved_results == expected, \
                "results.txt does not contain the exact recomputed bootstrap CI and posterior output."
            assert run_program(BINARY_PATH) == expected, \
                "The submitted compiled program's output does not match results.txt/statistics."
            assert run_program(rebuilt) == expected, \
                "A fresh compilation of stats_calc.c does not produce the required statistics."

            # Exercise both the submitted executable and freshly compiled source
            # on unpredictable datasets so fixed, fabricated bounds cannot pass.
            rng = secrets.SystemRandom()
            cases = [
                [rng.randrange(5, 106) for _ in range(N)],
                [rng.randrange(120, 321) for _ in range(N)],
                [rng.randrange(1, 40) + (i % 9) * 17 for i in range(N)],
            ]
            for data in cases:
                with open(DATA_PATH, "w") as f:
                    f.write("".join(f"{value}\n" for value in data))
                expected = expected_output(data)
                assert run_program(BINARY_PATH) == expected, \
                    "The submitted executable failed a verifier-generated bootstrap dataset."
                assert run_program(rebuilt) == expected, \
                    "stats_calc.c failed a verifier-generated bootstrap dataset."
        finally:
            with open(DATA_PATH, "wb") as f:
                f.write(original_bytes)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
