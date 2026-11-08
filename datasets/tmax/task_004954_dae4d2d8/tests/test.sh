#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

SRC_PATH = "/home/user/process_pdb.c"
EXE_PATH = "/home/user/process_pdb"
OUT_PATH = "/home/user/output.txt"


def test_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(SRC_PATH), f"C source file {SRC_PATH} is missing."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} is missing. Did you compile the code?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."


def test_output_file_exists_and_correct():
    """Preserve the original check of the required run on input.pdb."""
    assert os.path.isfile(OUT_PATH), f"Output file {OUT_PATH} is missing. Did you run the program?"

    with open(OUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, "output.txt should contain at least 2 lines (one for Left domain, one for Right domain)."

    left_line = lines[-2]
    right_line = lines[-1]
    pattern = r"Domain (Left|Right):\s*N_atoms=(\d+),\s*det=([0-9\.\-eE]+),\s*status=(OK|SINGULAR)"

    match_left = re.match(pattern, left_line)
    assert match_left, f"Left domain line format is incorrect. Got: '{left_line}'"
    assert match_left.group(1) == "Left", f"Expected 'Left' domain, got '{match_left.group(1)}'"
    assert match_left.group(2) == "4", f"Expected N_atoms=4 for Left domain, got {match_left.group(2)}"
    det_left = float(match_left.group(3))
    assert math.isclose(det_left, 0.0, abs_tol=1e-4), f"Left domain determinant incorrect. Expected ~0.0, got {det_left}"
    assert match_left.group(4) == "SINGULAR", f"Expected status=SINGULAR for Left domain, got {match_left.group(4)}"

    match_right = re.match(pattern, right_line)
    assert match_right, f"Right domain line format is incorrect. Got: '{right_line}'"
    assert match_right.group(1) == "Right", f"Expected 'Right' domain, got '{match_right.group(1)}'"
    assert match_right.group(2) == "4", f"Expected N_atoms=4 for Right domain, got {match_right.group(2)}"
    det_right = float(match_right.group(3))
    assert math.isclose(det_right, 8.109375, rel_tol=1e-3, abs_tol=1e-3), f"Right domain determinant incorrect. Expected ~8.109375, got {det_right}"
    assert match_right.group(4) == "OK", f"Expected status=OK for Right domain, got {match_right.group(4)}"


def covariance_det(points):
    n = len(points)
    means = [sum(p[i] for p in points) / n for i in range(3)]
    cov = [[sum((p[i] - means[i]) * (p[j] - means[j]) for p in points) / n
            for j in range(3)] for i in range(3)]
    return (cov[0][0] * (cov[1][1] * cov[2][2] - cov[1][2] * cov[2][1])
            - cov[0][1] * (cov[1][0] * cov[2][2] - cov[1][2] * cov[2][0])
            + cov[0][2] * (cov[1][0] * cov[2][1] - cov[1][1] * cov[2][0]))


def expected_results(points):
    xmin = min(p[0] for p in points)
    xmax = max(p[0] for p in points)
    midpoint = (xmin + xmax) / 2.0
    left = [p for p in points if p[0] < midpoint]
    right = [p for p in points if p[0] >= midpoint]
    return [("Left", len(left), covariance_det(left)),
            ("Right", len(right), covariance_det(right))]


def write_pdb(path, points):
    shuffled = list(points)
    random.SystemRandom().shuffle(shuffled)
    with open(path, "w") as f:
        f.write("REMARK this line must be ignored\n")
        f.write("HETATM 9000  CA  ALA A 9000    9999.000 9999.000 9999.000  1.00  0.00 C\n")
        f.write("ATOMX 9001 CA ALA A 9001 -9999.000 -9999.000 -9999.000 1.00 0.00 C\n")
        for serial, (x, y, z) in enumerate(shuffled, 1):
            f.write(f"ATOM  {serial:5d}  CA  ALA A{serial:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n")


def read_lines():
    assert os.path.isfile(OUT_PATH), "Program did not create /home/user/output.txt"
    with open(OUT_PATH) as f:
        return [line.strip() for line in f if line.strip()]


def assert_result_lines(lines, expected):
    assert len(lines) == 2, f"Each execution must append exactly two nonempty lines; got {lines!r}"
    pattern = re.compile(r"Domain (Left|Right): N_atoms=(\d+), det=(-?\d+\.\d{6}), status=(OK|SINGULAR)")
    for line, (domain, count, determinant) in zip(lines, expected):
        match = pattern.fullmatch(line)
        assert match, f"Output does not exactly match the required format: {line!r}"
        assert match.group(1) == domain
        assert int(match.group(2)) == count, f"Incorrect atom count in {domain}: {line!r}"
        actual_det = float(match.group(3))
        assert math.isclose(actual_det, determinant, rel_tol=1e-6, abs_tol=2e-5), \
            f"Incorrect population covariance determinant in {domain}: expected {determinant}, got {actual_det}"
        expected_status = "SINGULAR" if determinant < 0.1 else "OK"
        assert match.group(4) == expected_status, \
            f"Incorrect status in {domain}: determinant={determinant}, line={line!r}"


def make_random_full_rank_dataset(rng):
    while True:
        left_n = rng.choice([4, 5, 6])
        right_n = rng.choice([5, 6, 7])
        if left_n == right_n:
            right_n = 7 if right_n != 7 else 5
        left = [(-30.0 + i, float(rng.randint(-15, 15)), float(rng.randint(-15, 15)))
                for i in range(left_n)]
        right = [(12.0 + i, float(rng.randint(-15, 15)), float(rng.randint(-15, 15)))
                 for i in range(right_n)]
        points = left + right
        results = expected_results(points)
        if all(det > 0.25 for _, _, det in results):
            return points


def test_program_on_unseen_inputs_and_compiled_source():
    rng = random.SystemRandom()

    # One singular domain and one randomly generated full-rank domain.
    left = [(x, 2.0 * x + 3.0, -3.0 * x + 1.0) for x in (-15.0, -13.0, -11.0, -9.0, -7.0)]
    while True:
        right = [(x, float(rng.randint(-12, 12)), float(rng.randint(-12, 12)))
                 for x in (7.0, 9.0, 11.0, 13.0, 15.0, 17.0)]
        first_points = left + right
        first_expected = expected_results(first_points)
        if first_expected[0][2] < 0.1 and first_expected[1][2] > 0.25:
            break

    second_points = make_random_full_rank_dataset(rng)
    second_expected = expected_results(second_points)
    first_pdb = "/tmp/verifier_first.pdb"
    second_pdb = "/tmp/verifier_second.pdb"
    rebuilt_exe = "/tmp/process_pdb_from_source"
    write_pdb(first_pdb, first_points)
    write_pdb(second_pdb, second_points)

    # Compile the submitted C source so both the source and requested executable
    # must implement the behavior, rather than merely existing.
    subprocess.run(["gcc", "-std=c99", SRC_PATH, "-o", rebuilt_exe, "-lm"],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)

    subprocess.run([EXE_PATH, first_pdb], check=True, timeout=10,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    first_lines = read_lines()
    assert_result_lines(first_lines, first_expected)

    subprocess.run([rebuilt_exe, second_pdb], check=True, timeout=10,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    all_lines = read_lines()
    assert len(all_lines) == 4, "The second run must append two lines rather than overwrite output.txt"
    assert all_lines[:2] == first_lines, "The second run changed existing output instead of appending"
    assert_result_lines(all_lines[2:], second_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
