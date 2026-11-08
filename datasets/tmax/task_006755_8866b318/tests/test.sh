#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/analyze_matrices.sh"
CSV_PATH = "/home/user/input/matrices.csv"
REPORT_PATH = "/home/user/report.txt"


def process_matrices(csv_path):
    total = 0
    unstable = 0
    stable_accurate = 0
    stable_inaccurate = 0

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            total += 1
            a = float(row[1])
            b = float(row[2])
            c = float(row[3])
            d = float(row[4])

            det = a * d - b * c
            if abs(det) < 1e-6:
                unstable += 1
            else:
                inv_a = d / det
                inv_b = -b / det
                inv_c = -c / det
                inv_d = a / det

                p11 = a * inv_a + b * inv_c
                p12 = a * inv_b + b * inv_d
                p21 = c * inv_a + d * inv_c
                p22 = c * inv_b + d * inv_d

                max_err = max(abs(p11 - 1.0), abs(p12), abs(p21), abs(p22 - 1.0))
                if max_err > 1e-9:
                    stable_inaccurate += 1
                else:
                    stable_accurate += 1

    return total, unstable, stable_accurate, stable_inaccurate


def expected_lines(csv_path):
    total, unstable, stable_accurate, stable_inaccurate = process_matrices(csv_path)
    return [
        f"Total Matrices: {total}",
        f"Unstable: {unstable}",
        f"Stable Accurate: {stable_accurate}",
        f"Stable Inaccurate: {stable_inaccurate}",
    ]


def run_script():
    subprocess.run([SCRIPT_PATH], cwd="/home/user", check=True, timeout=15)


def assert_report(csv_path):
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        report_content = f.read().strip().splitlines()

    expected = expected_lines(csv_path)
    assert len(report_content) == 4, (
        f"The report should have exactly 4 lines, but found {len(report_content)} lines."
    )
    for i, expected_line in enumerate(expected):
        actual = report_content[i].strip()
        assert actual == expected_line, (
            f"Line {i+1} of report is incorrect.\n"
            f"Expected: '{expected_line}'\nActual: '{actual}'"
        )


def matrix_error(a, b, c, d):
    det = a * d - b * c
    if not math.isfinite(det) or abs(det) < 1e-6:
        return None
    inv_a, inv_b, inv_c, inv_d = d / det, -b / det, -c / det, a / det
    values = (
        abs((a * inv_a + b * inv_c) - 1.0),
        abs(a * inv_b + b * inv_d),
        abs(c * inv_a + d * inv_c),
        abs((c * inv_b + d * inv_d) - 1.0),
    )
    return max(values)


def find_inaccurate_matrix():
    rng = secrets.SystemRandom()
    for _ in range(20000):
        scale = 10.0 ** rng.uniform(8.0, 14.0)
        a = scale * rng.uniform(0.5, 2.0)
        b = scale * rng.uniform(0.5, 2.0)
        c = scale * rng.uniform(0.5, 2.0)
        base_d = b * c / a
        direction = math.inf if rng.randrange(2) else -math.inf
        d = math.nextafter(base_d, direction)
        err = matrix_error(a, b, c, d)
        if err is not None and math.isfinite(err) and err > 1e-7:
            return a, b, c, d
    raise AssertionError("Verifier could not construct a stable inaccurate test matrix")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), (
        f"The script {SCRIPT_PATH} is not executable. Run 'chmod +x {SCRIPT_PATH}'."
    )
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline(256)
    assert first_line.startswith(b"#!") and b"bash" in first_line.lower(), (
        "analyze_matrices.sh must be an executable Bash script"
    )


def test_report_content():
    assert os.path.isfile(CSV_PATH), f"The input file {CSV_PATH} is missing."
    run_script()
    assert_report(CSV_PATH)


def test_script_processes_changed_input():
    assert os.path.isfile(CSV_PATH), f"The input file {CSV_PATH} is missing."
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    rng = secrets.SystemRandom()
    rows = []
    next_id = 1000 + rng.randrange(1000000)

    # Exact singular matrices with randomized values.
    for _ in range(1 + rng.randrange(5)):
        x = rng.randrange(1, 1000)
        rows.append((next_id, float(x), float(2*x), float(3*x), float(6*x)))
        next_id += 1

    # Well-conditioned diagonal matrices whose analytical products are accurate.
    for _ in range(1 + rng.randrange(5)):
        a = rng.randrange(1, 10000) / 8.0
        d = rng.randrange(1, 10000) / 16.0
        rows.append((next_id, a, 0.0, 0.0, d))
        next_id += 1

    # Numerically ill-conditioned but non-singular matrices that exercise the
    # STABLE_INACCURATE branch.
    inaccurate = find_inaccurate_matrix()
    for _ in range(1 + rng.randrange(3)):
        rows.append((next_id,) + inaccurate)
        next_id += 1

    rng.shuffle(rows)

    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            for row in rows:
                writer.writerow([row[0]] + [format(value, ".17g") for value in row[1:]])

        run_script()
        assert_report(CSV_PATH)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        # Restore the report corresponding to the supplied dataset.
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
