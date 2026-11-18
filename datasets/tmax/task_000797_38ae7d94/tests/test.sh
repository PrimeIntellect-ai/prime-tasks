#!/bin/bash
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

ORIGINAL_PDB=/tmp/verifier_original_input.pdb
cp /home/user/data/input.pdb "$ORIGINAL_PDB" || fail
trap 'cp "$ORIGINAL_PDB" /home/user/data/input.pdb 2>/dev/null || true' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import pytest

MAIN_GO = "/home/user/profiler/main.go"
OUTPUT = "/home/user/output.txt"
BINARY = "/tmp/profiler_submission"
PDB = "/home/user/data/input.pdb"


def read_output():
    assert os.path.exists(OUTPUT), f"The file {OUTPUT} is missing. Did your Go program write to it?"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def parse_output(lines):
    assert len(lines) == 2, f"Expected exactly 2 lines in {OUTPUT}, found {len(lines)}."

    integral_match = re.match(r"^Integral:\s*([0-9\.\-]+)$", lines[0])
    assert integral_match, f"Line 1 does not match the expected format 'Integral: [value]'. Found: '{lines[0]}'"

    tstat_match = re.match(r"^t-stat:\s*([0-9\.\-]+)$", lines[1])
    assert tstat_match, f"Line 2 does not match the expected format 't-stat: [value]'. Found: '{lines[1]}'"

    return float(integral_match.group(1)), float(tstat_match.group(1))


def test_go_main_exists():
    assert os.path.exists(MAIN_GO), f"The file {MAIN_GO} is missing."
    assert os.path.isfile(MAIN_GO), f"{MAIN_GO} is not a file."


def test_output_file_exists():
    assert os.path.exists(OUTPUT), f"The file {OUTPUT} is missing. Did your Go program write to it?"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."


def test_output_contents():
    lines = read_output()
    integral_val, tstat_val = parse_output(lines)

    # Preserve the original checks for the supplied PDB data.
    assert integral_val == pytest.approx(4.6079, abs=1e-3), \
        f"Expected Integral to be approximately 4.6079, but got {integral_val}"
    assert tstat_val == pytest.approx(3.8730, abs=1e-3), \
        f"Expected t-stat to be approximately 3.8730, but got {tstat_val}"

    assert re.fullmatch(r"Integral: -?\d+\.\d{4}", lines[0]), "Integral must be formatted to 4 decimal places."
    assert re.fullmatch(r"t-stat: -?\d+\.\d{4}", lines[1]), "t-stat must be formatted to 4 decimal places."


def invert3(matrix):
    aug = [matrix[i][:] + [1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda row: abs(aug[row][col]))
        assert abs(aug[pivot][col]) > 1e-14
        aug[col], aug[pivot] = aug[pivot], aug[col]
        scale = aug[col][col]
        aug[col] = [value / scale for value in aug[col]]
        for row in range(3):
            if row != col:
                factor = aug[row][col]
                aug[row] = [aug[row][k] - factor * aug[col][k] for k in range(6)]
    return [row[3:] for row in aug]


def expected_values(points):
    n = len(points)
    means = [sum(point[j] for point in points) / n for j in range(3)]
    covariance = [
        [sum((point[i] - means[i]) * (point[j] - means[j]) for point in points) / (n - 1)
         for j in range(3)]
        for i in range(3)
    ]

    total = 0.0
    intervals = 1000
    step = (1.0 - 0.1) / intervals
    for k in range(intervals + 1):
        lam = 0.1 + k * step
        regularized = [row[:] for row in covariance]
        for i in range(3):
            regularized[i][i] += lam
        inverse = invert3(regularized)
        trace = sum(inverse[i][i] for i in range(3))
        total += (0.5 if k in (0, intervals) else 1.0) * trace
    integral = total * step

    x_mean = means[0]
    x_sd = math.sqrt(sum((point[0] - x_mean) ** 2 for point in points) / (n - 1))
    t_stat = x_mean / (x_sd / math.sqrt(n))
    return integral, t_stat


def write_pdb(points):
    with open(PDB, "w") as f:
        for i, (x, y, z) in enumerate(points, 1):
            f.write(
                f"ATOM  {i:5d}  CA  ALA A{i:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
            )


def run_submission(points):
    write_pdb(points)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user/profiler", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"Program failed: {result.stderr}"
    lines = read_output()
    actual_integral, actual_t = parse_output(lines)
    expected_integral, expected_t = expected_values(points)

    assert lines[0] == f"Integral: {expected_integral:.4f}", \
        f"Incorrect integral for verifier-generated PDB: got {actual_integral}, expected {expected_integral:.4f}"
    assert lines[1] == f"t-stat: {expected_t:.4f}", \
        f"Incorrect t-stat for verifier-generated PDB: got {actual_t}, expected {expected_t:.4f}"


def test_program_computes_results_for_changed_pdb_data():
    cases = [
        [(-3.0, 1.0, -7.0), (0.0, 2.0, -2.0), (2.0, -1.0, 5.0),
         (5.0, 4.0, 6.0), (8.0, 0.0, 16.0)],
        [(-9.0, 3.0, -15.0), (-5.0, -2.0, -8.0), (-2.0, 4.0, -8.0),
         (1.0, 1.0, 1.0), (4.0, -3.0, 11.0), (7.0, 2.0, 12.0)],
    ]
    for points in cases:
        run_submission(points)
TEST_EOF

# Build the submitted Go program, rather than trusting a pre-created output file.
if ! timeout 120s bash -c 'cd /home/user/profiler && go build -o /tmp/profiler_submission .'; then
    fail
fi

# Run it once against the original supplied PDB before applying the original assertions.
rm -f /home/user/output.txt
if ! timeout 20s /tmp/profiler_submission; then
    fail
fi

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
