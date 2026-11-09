#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_decay.py
import csv
import math
import os
import random
import re
import shutil
import subprocess

SOURCE = "/home/user/simulate_decay.cpp"
DATA = "/home/user/rna_data.csv"
OUTPUT = "/home/user/ci_results.csv"
BINARY = "/tmp/simulate_decay_verifier"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def rk4_final(seq):
    k_base, k_A, k_U, k_G, k_C = 0.010, 0.025, 0.015, 0.030, 0.040
    n = len(seq)
    require(n > 0, "Encountered an empty RNA sequence")
    k = k_base + (
        seq.count("A") * k_A
        + seq.count("U") * k_U
        + seq.count("G") * k_G
        + seq.count("C") * k_C
    ) / n
    c = 100.0
    dt = 0.1
    for _ in range(200):
        def f(x):
            return -k * x - 0.002 * x * x
        k1 = f(c)
        k2 = f(c + 0.5 * dt * k1)
        k3 = f(c + 0.5 * dt * k2)
        k4 = f(c + dt * k3)
        c += dt * (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0
    return c


def percentile(sorted_values, percentage):
    position = (len(sorted_values) - 1) * percentage
    lo = int(math.floor(position))
    hi = int(math.ceil(position))
    if lo == hi:
        return sorted_values[lo]
    fraction = position - lo
    return sorted_values[lo] * (1.0 - fraction) + sorted_values[hi] * fraction


def bootstrap_reference(values):
    # Independently perform the instructed 2,000-iteration bootstrap.
    rng = random.Random(0x5EEDC1)
    n = len(values)
    bootstrap_means = []
    for _ in range(2000):
        total = 0.0
        for _ in range(n):
            total += values[rng.randrange(n)]
        bootstrap_means.append(total / n)
    bootstrap_means.sort()
    return (
        sum(values) / n,
        percentile(bootstrap_means, 0.025),
        percentile(bootstrap_means, 0.975),
    )


def read_result():
    require(os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}")
    with open(OUTPUT, "r", newline="") as f:
        raw = f.read()
    lines = raw.splitlines()
    require(len(lines) == 2, "ci_results.csv must contain exactly one header and one data row")
    require(lines[0] == "Mean,Lower95,Upper95", "CSV header must be exactly Mean,Lower95,Upper95")
    rows = list(csv.DictReader(lines))
    require(len(rows) == 1, "ci_results.csv must contain exactly one result row")
    try:
        result = tuple(float(rows[0][name]) for name in ("Mean", "Lower95", "Upper95"))
    except Exception as exc:
        raise AssertionError(f"Could not parse the three result fields: {exc}")
    require(all(math.isfinite(x) for x in result), "All output values must be finite")
    require(result[0] >= result[1] and result[0] <= result[2], "Mean must lie within the confidence interval")
    return result


def run_submission():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run(
        ["runuser", "-u", "user", "--", BINARY],
        check=True,
        timeout=90,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return read_result()


def write_dataset(sequences):
    with open(DATA, "w", newline="") as f:
        f.write("Sequence\n")
        for seq in sequences:
            f.write(seq + "\n")
    os.chmod(DATA, 0o666)


def main():
    require(os.path.isfile(SOURCE), f"Required C++ source is missing: {SOURCE}")
    require(os.path.isfile(DATA), f"Input data file missing at {DATA}")
    require(not os.path.islink(SOURCE), "simulate_decay.cpp must be a real source file, not a symlink")

    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    require(re.search(r"#\s*pragma\s+omp\s+parallel\b", source, re.I),
            "Source does not contain an OpenMP parallel region")
    require(re.search(r"#\s*pragma\s+omp\s+(?:parallel\s+[^\n]*\s+)?for\b", source, re.I),
            "Source does not use an OpenMP work-sharing loop")
    lower_source = source.lower()
    require("2000" in lower_source, "Source does not specify 2,000 bootstrap iterations")
    require(re.search(r"mt19937|default_random_engine|minstd_rand|random_device|\brand\s*\(", lower_source),
            "Source does not contain random sampling for the bootstrap")
    require(re.search(r"sort\s*\(|percentile|quantile", lower_source),
            "Source does not calculate bootstrap percentile bounds")

    compile_result = subprocess.run(
        ["g++", "-O3", "-fopenmp", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    require(compile_result.returncode == 0,
            "Compilation with -O3 -fopenmp failed:\n" + compile_result.stderr[-4000:])
    symbols = subprocess.run(["nm", "-D", BINARY], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, check=True).stdout
    require(re.search(r"\b(?:GOMP_|omp_)", symbols),
            "Compiled program does not reference the OpenMP runtime")

    with open(DATA, "rb") as f:
        original_data = f.read()
    try:
        # A homogeneous derived input has a degenerate bootstrap CI and verifies
        # that the compiled artifact, rather than a pre-existing CSV, is used.
        homogeneous = ["A" * 50] * 5000
        write_dataset(homogeneous)
        got = run_submission()
        expected_value = rk4_final(homogeneous[0])
        for name, actual in zip(("Mean", "Lower95", "Upper95"), got):
            require(abs(actual - expected_value) <= 0.00075,
                    f"{name} is incorrect on a derived homogeneous input: got {actual}, expected {expected_value}")

        # Restore and execute the required workflow on the supplied population.
        with open(DATA, "wb") as f:
            f.write(original_data)
        os.chmod(DATA, 0o666)
        with open(DATA, "r", newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        require(rows and rows[0] == ["Sequence"], "Input CSV header is not Sequence")
        sequences = [row[0] for row in rows[1:] if row]
        require(len(sequences) == 5000, "Expected exactly 5,000 RNA sequences")

        actual = run_submission()
        concentrations = [rk4_final(seq) for seq in sequences]
        expected = bootstrap_reference(concentrations)
        tolerances = (0.00075, 0.001, 0.001)
        for name, got_value, expected_value, tolerance in zip(
                ("Mean", "Lower95", "Upper95"), actual, expected, tolerances):
            require(abs(got_value - expected_value) <= tolerance,
                    f"{name} differs from the independently computed 2,000-sample bootstrap result: "
                    f"got {got_value:.8f}, expected {expected_value:.8f}, tolerance {tolerance}")
        require(actual[2] - actual[1] > 0.002,
                "Bootstrap interval is implausibly degenerate for the supplied population")
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        os.chmod(DATA, 0o666)


if __name__ == "__main__":
    main()
PY

if python3 /tmp/verify_decay.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
