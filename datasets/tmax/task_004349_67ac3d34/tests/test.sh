#!/bin/bash
set -u
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/data/metadata.csv "$backup_dir/metadata.csv"
cp /home/user/data/series.csv "$backup_dir/series.csv"
had_output=0
if [ -e /home/user/closest_pair.txt ]; then
    cp /home/user/closest_pair.txt "$backup_dir/closest_pair.txt"
    had_output=1
fi

cleanup() {
    cp "$backup_dir/metadata.csv" /home/user/data/metadata.csv
    cp "$backup_dir/series.csv" /home/user/data/series.csv
    if [ "$had_output" -eq 1 ]; then
        cp "$backup_dir/closest_pair.txt" /home/user/closest_pair.txt
    else
        rm -f /home/user/closest_pair.txt
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess
from itertools import combinations

import pytest

SOURCE = "/home/user/process.c"
PROGRAM = "/tmp/submitted_process"
OUTPUT = "/home/user/closest_pair.txt"
METADATA = "/home/user/data/metadata.csv"
SERIES = "/home/user/data/series.csv"


@pytest.fixture(scope="session", autouse=True)
def built_program():
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} must be a regular C source file."
    assert not stat.S_ISLNK(source_stat.st_mode), f"{SOURCE} must not be a symbolic link."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", PROGRAM],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "process.c did not compile successfully:\n" + compile_result.stderr
    )
    program_stat = os.stat(PROGRAM)
    assert stat.S_ISREG(program_stat.st_mode) and os.access(PROGRAM, os.X_OK), (
        "Compiling process.c did not produce an executable program."
    )

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_result = subprocess.run(
        [PROGRAM], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert run_result.returncode == 0, (
        "The compiled process.c failed on the supplied datasets:\n" + run_result.stderr
    )
    assert os.path.isfile(OUTPUT), "The compiled process.c did not create closest_pair.txt."
    return PROGRAM


def test_closest_pair_result():
    output_file = "/home/user/closest_pair.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    metadata_file = "/home/user/data/metadata.csv"
    series_file = "/home/user/data/series.csv"

    assert os.path.isfile(metadata_file), "metadata.csv is missing."
    assert os.path.isfile(series_file), "series.csv is missing."

    # 1. Read metadata
    target_exps = set()
    with open(metadata_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['Category'] == 'Target':
                target_exps.add(row['ExpID'])

    # 2. Read and process series
    cleaned_data = {}
    with open(series_file, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            exp_id = row[0]
            if exp_id not in target_exps:
                continue

            raw_vals = row[1:6]
            present_capped = []

            # Cap outliers
            for v in raw_vals:
                if v.strip():
                    val = float(v)
                    if val > 100.0:
                        val = 100.0
                    elif val < 0.0:
                        val = 0.0
                    present_capped.append(val)

            # Compute mean
            mean_val = sum(present_capped) / len(present_capped) if present_capped else 0.0

            # Fill missing
            final_vals = []
            for v in raw_vals:
                if v.strip():
                    val = float(v)
                    if val > 100.0:
                        val = 100.0
                    elif val < 0.0:
                        val = 0.0
                    final_vals.append(val)
                else:
                    final_vals.append(mean_val)

            cleaned_data[exp_id] = final_vals

    # 3. Calculate distances
    min_dist = float('inf')
    best_pair = None

    for expA, expB in combinations(sorted(cleaned_data.keys()), 2):
        vecA = cleaned_data[expA]
        vecB = cleaned_data[expB]
        dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(vecA, vecB)))

        if dist < min_dist:
            min_dist = dist
            best_pair = (expA, expB)

    expected_expA, expected_expB = sorted(best_pair)
    expected_distance_str = f"{min_dist:.4f}"
    expected_output = f"{expected_expA},{expected_expB},{expected_distance_str}"

    # 4. Read student output
    with open(output_file, 'r') as f:
        raw_output = f.read()
    student_output = raw_output.strip()

    assert student_output == expected_output, (
        f"Output in {output_file} does not match expected.\n"
        f"Expected: '{expected_output}'\n"
        f"Got: '{student_output}'"
    )
    assert raw_output in (expected_output, expected_output + "\n"), (
        "closest_pair.txt must contain exactly one correctly formatted line."
    )


def expected_from_files():
    targets = set()
    with open(METADATA, newline="") as f:
        for row in csv.DictReader(f):
            if row["Category"] == "Target":
                targets.add(row["ExpID"])

    cleaned = {}
    with open(SERIES, newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if row[0] not in targets:
                continue
            raw = row[1:6]
            present = [min(100.0, max(0.0, float(v))) for v in raw if v.strip()]
            mean = sum(present) / len(present)
            cleaned[row[0]] = [
                min(100.0, max(0.0, float(v))) if v.strip() else mean
                for v in raw
            ]

    best_pair = None
    best_distance = float("inf")
    for a, b in combinations(sorted(cleaned), 2):
        distance = math.sqrt(sum(
            (x - y) ** 2 for x, y in zip(cleaned[a], cleaned[b])
        ))
        if distance < best_distance:
            best_pair = (a, b)
            best_distance = distance
    assert best_pair is not None
    return f"{best_pair[0]},{best_pair[1]},{best_distance:.4f}"


def write_case(metadata_rows, series_rows):
    with open(METADATA, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["ExpID", "Category"])
        writer.writerows(metadata_rows)
    with open(SERIES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["ExpID", "V1", "V2", "V3", "V4", "V5"])
        writer.writerows(series_rows)


def run_and_check(program):
    expected = expected_from_files()
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [program], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, "Program failed on a valid alternate dataset:\n" + result.stderr
    assert os.path.isfile(OUTPUT), "Program did not regenerate closest_pair.txt."
    with open(OUTPUT) as f:
        raw = f.read()
    assert raw in (expected, expected + "\n"), (
        f"Program produced the wrong result for an alternate dataset.\n"
        f"Expected: '{expected}'\nGot: '{raw.strip()}'"
    )


def test_program_implements_join_clean_and_search(built_program):
    token = secrets.token_hex(4).upper()
    shift = 5 + secrets.randbelow(11)
    a, b, c, d = (f"A{token}", f"B{token}", f"C{token}", f"D{token}")
    metadata_only, series_only = f"M{token}", f"X{token}"

    write_case(
        [
            (d, "Target"), (c, "Ignore"), (metadata_only, "Target"),
            (b, "Target"), (a, "Target"),
        ],
        [
            (series_only, shift, "", shift + 20, 150, shift + 40),
            (c, shift, "", shift + 20, 150, shift + 40),
            (d, -20, 0, "", -5, 0),
            (b, shift + 1, shift + 39, shift + 21, 99, shift + 41),
            (a, shift, "", shift + 20, 150, shift + 40),
        ],
    )
    run_and_check(built_program)

    p, q, r, ignored = (
        f"P{token}", f"Q{token}", f"R{token}", f"Z{token}"
    )
    write_case(
        [(r, "Target"), (ignored, "Ignore"), (q, "Target"), (p, "Target")],
        [
            (ignored, -50, "", 20, 30, 40),
            (r, 90, 90, 90, 90, 90),
            (q, 1, 22, 21, 29, 41),
            (p, -50, "", 20, 30, 40),
        ],
    )
    run_and_check(built_program)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
