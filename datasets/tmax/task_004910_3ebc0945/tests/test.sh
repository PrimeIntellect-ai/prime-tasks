#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze.sh"
CSV_PATH = "/home/user/data/benchmarks.csv"
RESULT_PATH = "/home/user/result.txt"


def get_expected_correlation(csv_path):
    n = 0
    sum_x = 0.0
    sum_y = 0.0
    sum_xy = 0.0
    sum_x2 = 0.0
    sum_y2 = 0.0

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row:
                continue
            if float(row[3]) > 50.0:
                x = float(row[1])
                y = float(row[2])
                sum_x += x
                sum_y += y
                sum_xy += x * y
                sum_x2 += x * x
                sum_y2 += y * y
                n += 1

    if n == 0:
        return "0.0000"

    numerator = n * sum_xy - sum_x * sum_y
    denominator_sq = ((n * sum_x2 - sum_x * sum_x) *
                      (n * sum_y2 - sum_y * sum_y))
    if denominator_sq <= 0:
        return "0.0000"
    denominator = math.sqrt(denominator_sq)
    if denominator == 0:
        return "0.0000"
    return f"{numerator / denominator:.4f}"


def run_analyzer(csv_path):
    completed = subprocess.run(
        [SCRIPT_PATH, csv_path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        env={
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "LC_ALL": "C",
            "LANG": "C",
            "HOME": "/tmp",
        },
    )
    assert completed.returncode == 0, (
        f"analyze.sh failed for {csv_path} with exit code "
        f"{completed.returncode}: {completed.stderr}"
    )
    assert re.fullmatch(r"[+-]?[0-9]+\.[0-9]{4}\n?", completed.stdout), (
        "analyze.sh must print exactly one number with four decimal places; "
        f"got {completed.stdout!r}"
    )
    return completed.stdout.strip()


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["model_id", "inference_time_ms", "accuracy", "cpu_utilization"])
        writer.writerows(rows)


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        source_bytes = f.read()
    assert b"\x00" not in source_bytes, "analyze.sh must be a text Bash script."
    source = source_bytes.decode("utf-8")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.fullmatch(r"#!\s*(?:/usr/bin/env\s+)?(?:/bin/|/usr/bin/)?bash\s*", first_line), (
        "analyze.sh must have a Bash shebang."
    )

    forbidden_command = re.compile(
        r"(?im)(?:^|[;&|`(]|\b(?:if|then|elif|while|until|do|exec|command|env|sudo|xargs)\s+)"
        r"\s*(?:['\"]?/[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*/)?"
        r"(?:python[0-9.]*|perl|ruby|rscript|node(?:js)?|php|lua)\b"
    )
    assert not forbidden_command.search(source), (
        "analyze.sh invokes a forbidden non-Bash/non-awk scripting language."
    )


def test_result_txt_content():
    assert os.path.isfile(CSV_PATH), f"Data file {CSV_PATH} is missing."
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."

    expected_val = get_expected_correlation(CSV_PATH)
    with open(RESULT_PATH, "r") as f:
        actual_val = f.read().strip()

    assert actual_val == expected_val, (
        f"Expected correlation {expected_val}, but found {actual_val} in {RESULT_PATH}."
    )


def test_script_produces_original_result():
    expected = get_expected_correlation(CSV_PATH)
    actual = run_analyzer(CSV_PATH)
    assert actual == expected, f"Expected {expected}, but analyze.sh printed {actual}."


def test_script_argument_filtering_and_zero_division():
    cases = [
        [
            ["excluded_low", "100", "0.01", "49.9"],
            ["excluded_equal", "200", "0.99", "50.0"],
            ["a", "10", "0.20", "50.1"],
            ["b", "20", "0.40", "75.0"],
            ["c", "30", "0.80", "90.0"],
        ],
        [
            ["a", "5", "0.2", "51"],
            ["b", "5", "0.6", "70"],
            ["c", "5", "0.9", "80"],
            ["excluded", "99", "0.1", "50"],
        ],
        [
            ["a", "1", "0.1", "50.0"],
            ["b", "2", "0.2", "10.0"],
        ],
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        for index, rows in enumerate(cases):
            path = os.path.join(tmpdir, f"case_{index}.csv")
            write_csv(path, rows)
            expected = get_expected_correlation(path)
            actual = run_analyzer(path)
            assert actual == expected, (
                f"For generated case {index}, expected {expected}, got {actual}."
            )


def test_script_on_unpredictable_inputs():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory() as tmpdir:
        for case_index in range(3):
            rows = []
            count = rng.randint(18, 36)
            for i in range(count):
                x = round(rng.uniform(-40.0, 250.0), 3)
                y = round(rng.uniform(-1.5, 2.5) + 0.003 * x, 6)
                if i == 0:
                    cpu = 50.0
                elif i == 1:
                    cpu = 50.001
                else:
                    cpu = round(rng.uniform(20.0, 90.0), 3)
                rows.append([f"random_{case_index}_{i}", x, y, cpu])

            path = os.path.join(tmpdir, f"random_{case_index}_{secrets.token_hex(6)}.csv")
            write_csv(path, rows)
            expected = get_expected_correlation(path)
            actual = run_analyzer(path)
            assert actual == expected, (
                f"For an unpredictable input, expected {expected}, got {actual}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
