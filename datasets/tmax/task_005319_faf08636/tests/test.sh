#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess

SCRIPT = "/home/user/etl_check.sh"
SOURCE_A = "/home/user/sourceA.csv"
SOURCE_B = "/home/user/sourceB.csv"
INVALID = "/home/user/invalid_ids.txt"
CLEAN = "/home/user/clean_joined.csv"

ORIGINAL_A = [
    ("1", "A", "10"),
    ("2", "B", "20"),
    ("3", "C", "30"),
    ("4", "D", "40"),
    ("5", "E", "50"),
    ("6", "F", "60"),
    ("7", "G", "70"),
    ("8", "H", "80"),
]
ORIGINAL_B = [
    ("1", "A", "100"),
    ("2", "B", "200.0"),
    ("3", "C", ""),
    ("4", "D", "400"),
    ("5", "E", "-500"),
    ("6", "F", "600.5"),
    ("7", "G", "700"),
    ("8", "H", ""),
]


def write_sources(rows_a, rows_b):
    with open(SOURCE_A, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "f1", "f2"])
        writer.writerows(rows_a)
    with open(SOURCE_B, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "f3", "pred"])
        writer.writerows(rows_b)


def run_script(rows_a, rows_b):
    write_sources(rows_a, rows_b)
    for path in (INVALID, CLEAN):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def nonempty_lines(path):
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"Output path {path} is not a regular file."
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/env bash"), \
        "etl_check.sh must be a standalone Bash script with a Bash shebang."


def test_invalid_ids_content():
    run_script(ORIGINAL_A, ORIGINAL_B)
    lines = nonempty_lines(INVALID)
    expected_ids = ["2", "3", "6", "8"]
    assert lines == expected_ids, (
        f"Contents of {INVALID} do not match the expected invalid IDs. "
        f"Expected {expected_ids}, got {lines}."
    )


def test_clean_joined_content():
    run_script(ORIGINAL_A, ORIGINAL_B)
    expected_content = [
        "id,f1,f2,pred",
        "1,A,10,100",
        "4,D,40,400",
        "5,E,50,-500",
        "7,G,70,700",
    ]
    lines = nonempty_lines(CLEAN)
    assert lines == expected_content, \
        f"Contents of {CLEAN} do not match the expected clean joined data."


def expected_outputs(rows_a, rows_b):
    a_by_id = {row[0]: row[1:] for row in rows_a}
    b_by_id = {row[0]: row[1:] for row in rows_b}
    joined_ids = sorted(set(a_by_id) & set(b_by_id), key=int)

    correlated = all(a_by_id[i][0] == b_by_id[i][0] for i in joined_ids)
    invalid_ids = [
        i for i in joined_ids
        if re.fullmatch(r"-?[0-9]+", b_by_id[i][1]) is None
    ]

    if correlated:
        clean_lines = ["id,f1,f2,pred"]
    else:
        clean_lines = ["id,f1,f2,f3,pred"]

    for i in joined_ids:
        f1, f2 = a_by_id[i]
        f3, pred = b_by_id[i]
        if re.fullmatch(r"-?[0-9]+", pred) is None:
            continue
        if correlated:
            clean_lines.append(",".join((i, f1, f2, pred)))
        else:
            clean_lines.append(",".join((i, f1, f2, f3, pred)))

    return invalid_ids, clean_lines


def exercise_generated_case(correlated):
    rng = secrets.SystemRandom()
    base = secrets.randbelow(900000) + 10000
    ids = [str(base + n) for n in (41, 3, 120, 18, 77, 9)]
    f1_values = [f"feature_{secrets.token_hex(3)}" for _ in ids]
    preds = ["42", "17.0", "", "-9", "not_an_integer", "0"]

    rows_a = [
        (row_id, f1, str((index + 1) * 13))
        for index, (row_id, f1) in enumerate(zip(ids, f1_values))
    ]
    rows_b = [
        (row_id, f1, pred)
        for row_id, f1, pred in zip(ids, f1_values, preds)
    ]
    if not correlated:
        changed = list(rows_b[3])
        changed[1] = "different_feature_value"
        rows_b[3] = tuple(changed)

    rng.shuffle(rows_a)
    rng.shuffle(rows_b)
    expected_invalid, expected_clean = expected_outputs(rows_a, rows_b)
    run_script(rows_a, rows_b)

    assert nonempty_lines(INVALID) == expected_invalid
    assert nonempty_lines(CLEAN) == expected_clean


def test_script_processes_runtime_inputs_and_correlation_layout():
    exercise_generated_case(correlated=True)
    exercise_generated_case(correlated=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
