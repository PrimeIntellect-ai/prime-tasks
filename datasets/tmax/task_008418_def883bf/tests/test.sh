#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess

SCRIPT = "/home/user/compare_matrices.sh"
REPORT = "/home/user/report.txt"
REF_DIR = "/home/user/data/ref_serial"
RUN_DIR = "/home/user/data/run_parallel"
ALGOS = ["svd", "lu", "qr", "cholesky"]


def run_script():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def report_lines():
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
    with open(REPORT, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def awk_default_number(value):
    if value == 0:
        return "0"
    return format(value, ".6g")


def expected_from_current_files():
    results = []
    for algo in ALGOS:
        with open(os.path.join(REF_DIR, f"{algo}_matrix.txt")) as f:
            ref_rows = [[float(x) for x in line.split()] for line in f if line.strip()]
        with open(os.path.join(RUN_DIR, f"{algo}_matrix.txt")) as f:
            run_rows = [[float(x) for x in line.split()] for line in f if line.strip()]

        assert len(ref_rows) == len(run_rows)
        differences = []
        for ref_row, run_row in zip(ref_rows, run_rows):
            assert len(ref_row) == len(run_row)
            differences.extend(abs(a - b) for a, b in zip(ref_row, run_row))
        results.append((algo, max(differences)))

    results.sort(key=lambda item: item[1], reverse=True)
    return [
        f"Algorithm: {algo}, Max Diff: {awk_default_number(diff)}"
        for algo, diff in results
    ]


def write_matrix(path, rows):
    with open(path, "w") as f:
        for row in rows:
            f.write(" ".join(format(value, ".12g") for value in row) + "\n")


def test_script_exists_and_executable():
    """Test that the script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), f"Script {SCRIPT} is not executable."


def test_report_exists_and_correct():
    """Execute the script and test the report against the supplied dataset."""
    run_script()
    lines = report_lines()
    expected = [
        "Algorithm: qr, Max Diff: 0.045",
        "Algorithm: svd, Max Diff: 0.015",
        "Algorithm: lu, Max Diff: 0.002",
        "Algorithm: cholesky, Max Diff: 0"
    ]
    assert len(lines) == len(expected), f"Expected {len(expected)} lines in the report, but got {len(lines)}."
    for i, (act, exp) in enumerate(zip(lines, expected)):
        assert act == exp, f"Line {i+1} mismatch. Expected '{exp}', got '{act}'."


def test_script_computes_results_from_matrix_files():
    paths = [
        os.path.join(directory, f"{algo}_matrix.txt")
        for directory in (REF_DIR, RUN_DIR)
        for algo in ALGOS
    ]
    originals = {}
    for path in paths:
        with open(path, "rb") as f:
            originals[path] = f.read()

    rng = random.SystemRandom()
    try:
        # Unpredictable integer-valued case with a different unique maximum for
        # every algorithm and with maxima appearing at different elements.
        integer_maxima = rng.sample(range(7, 90), len(ALGOS))
        for index, (algo, maximum) in enumerate(zip(ALGOS, integer_maxima)):
            base = rng.randint(-500, 500)
            ref = [
                [base, base + 11, base - 17],
                [base + 23, base - 31, base + 41],
            ]
            offsets = [0, 1, -(maximum - 1), 2, maximum, -3]
            rng.shuffle(offsets)
            run = [
                [ref[r][c] + offsets[r * 3 + c] for c in range(3)]
                for r in range(2)
            ]
            write_matrix(os.path.join(REF_DIR, f"{algo}_matrix.txt"), ref)
            write_matrix(os.path.join(RUN_DIR, f"{algo}_matrix.txt"), run)

        expected = expected_from_current_files()
        run_script()
        assert report_lines() == expected

        # A second case checks fractional differences, zero differences, and a
        # newly determined descending order.
        maxima = [0.03125, 0.0625, 0.125, 0.25]
        rng.shuffle(maxima)
        for algo, maximum in zip(ALGOS, maxima):
            base = rng.randint(-50, 50)
            ref = [[float(base), float(base + 2)], [float(base - 3), float(base + 5)]]
            if algo == ALGOS[0]:
                # Whether this is the zero case is randomized by assigning the
                # shuffled maxima below; all values still come from the files.
                pass
            run = [[ref[0][0], ref[0][1] - maximum / 2],
                   [ref[1][0] + maximum, ref[1][1]]]
            write_matrix(os.path.join(REF_DIR, f"{algo}_matrix.txt"), ref)
            write_matrix(os.path.join(RUN_DIR, f"{algo}_matrix.txt"), run)

        # Force one randomly selected algorithm to be exactly equal so that
        # zero formatting is also exercised.
        zero_algo = rng.choice(ALGOS)
        ref_path = os.path.join(REF_DIR, f"{zero_algo}_matrix.txt")
        run_path = os.path.join(RUN_DIR, f"{zero_algo}_matrix.txt")
        with open(ref_path, "rb") as src, open(run_path, "wb") as dst:
            dst.write(src.read())

        expected = expected_from_current_files()
        run_script()
        assert report_lines() == expected
    finally:
        for path, contents in originals.items():
            with open(path, "wb") as f:
                f.write(contents)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
