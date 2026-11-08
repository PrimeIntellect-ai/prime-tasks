#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
for name in experiments.csv results.csv pipeline.c; do
    if [ -e "/home/user/$name" ]; then
        cp -a "/home/user/$name" "$BACKUP_DIR/$name"
    fi
done
cleanup() {
    for name in experiments.csv results.csv pipeline.c; do
        if [ -e "$BACKUP_DIR/$name" ]; then
            cp -a "$BACKUP_DIR/$name" "/home/user/$name"
        else
            rm -f "/home/user/$name"
        fi
    done
    rm -rf "$BACKUP_DIR" /tmp/pipeline_verified
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "pipeline.c")
INPUT = os.path.join(HOME, "experiments.csv")
OUTPUT = os.path.join(HOME, "results.csv")
VERIFIER_BINARY = "/tmp/pipeline_verified"


def test_results_csv_exists_and_correct():
    results_path = "/home/user/results.csv"
    assert os.path.isfile(results_path), f"File {results_path} is missing. Did you run the compiled C program?"

    with open(results_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 4, f"Expected header and 3 data rows in {results_path}, found {len(rows)} rows."

    header = rows[0]
    assert header == ["QueryID", "ClosestReferenceID", "Distance"], f"Header in {results_path} is incorrect. Got {header}"

    data = rows[1:]
    assert len(data) == 3, f"Expected exactly 3 data rows, got {len(data)}"

    expected_results = {
        "8": {"closest": "1", "dist": 0.3536},
        "9": {"closest": "3", "dist": 0.7071},
        "10": {"closest": "4", "dist": 0.0707},
    }

    for row in data:
        assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
        q_id, closest_id, dist_str = row
        assert q_id in expected_results, f"Unexpected QueryID {q_id} in results."
        expected = expected_results[q_id]
        assert closest_id == expected["closest"], f"For QueryID {q_id}, expected ClosestReferenceID {expected['closest']}, got {closest_id}."
        dist_val = float(dist_str)
        assert math.isclose(dist_val, expected["dist"], abs_tol=0.0001), \
            f"For QueryID {q_id}, expected Distance {expected['dist']}, got {dist_val}. Data leakage might not be fully fixed."


def test_pipeline_c_fixed():
    file_path = "/home/user/pipeline.c"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    init_idx = content.find("float min_f1")
    assert init_idx != -1, "Could not find min/max initialization in pipeline.c"

    loop_idx = content.find("for", init_idx)
    assert loop_idx != -1, "Could not find the min/max calculation loop in pipeline.c"

    loop_condition = content[loop_idx:content.find("{", loop_idx)]
    assert "TOTAL_ROWS" not in loop_condition, "The min/max calculation loop still iterates over TOTAL_ROWS, causing data leakage."
    assert "NUM_REF" in loop_condition or "7" in loop_condition, "The min/max calculation loop should iterate over NUM_REF."


def nearest(rows, fit_count):
    fit = rows[:fit_count]
    min1 = min(r[1] for r in fit)
    max1 = max(r[1] for r in fit)
    min2 = min(r[2] for r in fit)
    max2 = max(r[2] for r in fit)
    assert max1 > min1 and max2 > min2

    scaled = []
    for ident, f1, f2 in rows:
        scaled.append((ident, (f1 - min1) / (max1 - min1), (f2 - min2) / (max2 - min2)))

    answers = []
    margins = []
    for query in scaled[7:]:
        distances = []
        for ref in scaled[:7]:
            distance = math.hypot(query[1] - ref[1], query[2] - ref[2])
            distances.append((distance, ref[0]))
        distances.sort()
        answers.append((query[0], distances[0][1], distances[0][0]))
        margins.append(distances[1][0] - distances[0][0])
    return answers, margins


def make_cases():
    rng = random.Random(secrets.randbits(128))
    cases = []
    while len(cases) < 5:
        ids = rng.sample(range(1000, 9000), 10)
        rows = []
        for i in range(7):
            rows.append((ids[i], round(rng.uniform(10, 90), 6), round(rng.uniform(10, 90), 6)))
        # Queries deliberately include values outside the reference ranges so fitting
        # on all ten rows produces observably different scaling parameters.
        rows.extend([
            (ids[7], round(rng.uniform(-80, 5), 6), round(rng.uniform(95, 180), 6)),
            (ids[8], round(rng.uniform(95, 180), 6), round(rng.uniform(-80, 5), 6)),
            (ids[9], round(rng.uniform(-60, 170), 6), round(rng.uniform(-60, 170), 6)),
        ])
        expected, margins = nearest(rows, 7)
        leaked, _ = nearest(rows, 10)
        distinguishable = any(
            a[1] != b[1] or abs(a[2] - b[2]) > 0.01
            for a, b in zip(expected, leaked)
        )
        if min(margins) > 0.002 and distinguishable:
            cases.append((rows, expected))
    return cases


CASES = make_cases()


def write_input(rows):
    with open(INPUT, "w", newline="") as f:
        for ident, f1, f2 in rows:
            f.write(f"{ident},{f1:.6f},{f2:.6f}\n")
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass


def check_output(expected):
    assert os.path.isfile(OUTPUT), "The executable did not create /home/user/results.csv"
    with open(OUTPUT, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["QueryID", "ClosestReferenceID", "Distance"], \
        f"Incorrect results header: {rows[0] if rows else 'missing'}"
    assert len(rows) == 4, f"Expected exactly one header and three result rows, got {len(rows)} rows"

    expected_by_id = {str(qid): (str(refid), distance) for qid, refid, distance in expected}
    assert len({row[0] for row in rows[1:] if row}) == 3, "Query rows must not be duplicated"
    for row in rows[1:]:
        assert len(row) == 3, f"Malformed result row: {row}"
        qid, refid, distance_text = row
        assert qid in expected_by_id, f"Unexpected or hardcoded QueryID {qid}"
        expected_ref, expected_distance = expected_by_id[qid]
        assert refid == expected_ref, f"For query {qid}, expected reference {expected_ref}, got {refid}"
        assert re.fullmatch(r"[0-9]+\.[0-9]{4}", distance_text), \
            f"Distance must be printed to four decimal places, got {distance_text!r}"
        actual_distance = float(distance_text)
        assert math.isfinite(actual_distance)
        assert abs(actual_distance - expected_distance) <= 0.00011, \
            f"For query {qid}, expected distance {expected_distance:.4f}, got {distance_text}"


def exercise(executable):
    for rows, expected in CASES:
        write_input(rows)
        completed = subprocess.run(
            [executable], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=5
        )
        assert completed.returncode == 0, \
            f"Executable {executable} failed with code {completed.returncode}: {completed.stderr}"
        check_output(expected)


def test_fixed_source_compiles_and_behaves_on_unseen_inputs():
    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", VERIFIER_BINARY, SOURCE, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, f"pipeline.c does not compile: {completed.stderr}"
    exercise(VERIFIER_BINARY)


def submitted_elf_executables():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if path in (SOURCE, INPUT, OUTPUT):
                continue
            try:
                if not os.path.isfile(path) or not os.access(path, os.X_OK):
                    continue
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        candidates.append(path)
            except OSError:
                pass
    return candidates


def test_agent_compiled_and_ran_a_working_executable():
    candidates = submitted_elf_executables()
    assert candidates, "No compiled ELF executable was found under /home/user"

    failures = []
    for executable in candidates:
        try:
            exercise(executable)
            return
        except Exception as exc:
            failures.append(f"{executable}: {exc}")
    raise AssertionError("No submitted compiled executable implements the pipeline correctly. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
