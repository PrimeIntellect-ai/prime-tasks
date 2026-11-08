#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
import tempfile
import uuid

PROGRAM = "/home/user/parse_dataset.c"
EXECUTABLE = "/tmp/parse_dataset_verifier"
DATASET = "/home/user/dataset"
RESULTS = "/home/user/results.csv"


def read_csv(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def run_program():
    subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        check=True,
        timeout=8,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_dataset_extracted():
    """Verify that the complete dataset was extracted to the correct directory."""
    assert os.path.isdir(DATASET), "Directory /home/user/dataset does not exist."
    assert os.path.isfile(f"{DATASET}/run_A/exp1.log"), "/home/user/dataset/run_A/exp1.log is missing."
    assert os.path.isfile(f"{DATASET}/run_B/exp2.log"), "/home/user/dataset/run_B/exp2.log is missing."
    assert os.path.isfile(f"{DATASET}/run_C/nested/exp3.log"), "/home/user/dataset/run_C/nested/exp3.log is missing."
    assert os.path.isfile(f"{DATASET}/run_B/notes.txt"), "/home/user/dataset/run_B/notes.txt is missing."
    assert os.path.islink(f"{DATASET}/run_A/loop_link2"), "run_A/loop_link2 was not extracted as a symlink."
    assert os.path.islink(f"{DATASET}/run_C/nested/loop_link"), "run_C/nested/loop_link was not extracted as a symlink."


def test_c_program_exists():
    """Verify that the C program was created."""
    assert os.path.isfile(PROGRAM), "/home/user/parse_dataset.c does not exist."


def test_program_compiles_and_generates_original_results():
    """Compile and execute the submitted program against the extracted archive."""
    subprocess.run(
        ["gcc", "-std=gnu11", "-O2", PROGRAM, "-o", EXECUTABLE],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if os.path.lexists(RESULTS):
        os.unlink(RESULTS)
    run_program()
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist after running the program."


def test_results_csv_contents():
    """Verify that results.csv contains the correct original data in the correct order."""
    expected_rows = [
        ["Experiment", "Result"],
        ["EXP-002", "99.1"],
        ["EXP-003", "45.2"],
        ["EXP-004", "12.8"],
    ]
    rows = read_csv(RESULTS)
    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in results.csv, but found {len(rows)}."
    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def test_program_handles_unseen_records_and_symlink_loops():
    """Exercise the compiled program on verifier-generated records and loops."""
    holder = tempfile.mkdtemp(prefix="dataset-verifier-", dir="/home/user")
    original_dataset = os.path.join(holder, "original_dataset")
    old_results = None
    if os.path.isfile(RESULTS):
        with open(RESULTS, "rb") as f:
            old_results = f.read()

    ids = [f"DYN-{uuid.uuid4().hex[:12]}" for _ in range(3)]
    values = ["731.125", "4.875", "208.0625"]

    try:
        os.rename(DATASET, original_dataset)
        os.makedirs(f"{DATASET}/branch/deeper")

        with open(f"{DATASET}/branch/mixed.log", "w") as f:
            f.write(
                "BEGIN RECORD\n"
                f"Experiment: {ids[2]}\n"
                "Status: SUCCESS\n"
                f"Result: {values[2]}\n"
                "END RECORD\n"
                "BEGIN RECORD\n"
                f"Experiment: IGNORED-{uuid.uuid4().hex[:8]}\n"
                "Status: FAILED\n"
                "Result: 9999.0\n"
                "END RECORD\n"
                "BEGIN RECORD\n"
                f"Experiment: {ids[0]}\n"
                "Status: SUCCESS\n"
                f"Result: {values[0]}\n"
                "END RECORD\n"
            )

        with open(f"{DATASET}/branch/deeper/other.log", "w") as f:
            f.write(
                "BEGIN RECORD\n"
                f"Experiment: {ids[1]}\n"
                "Status: SUCCESS\n"
                f"Result: {values[1]}\n"
                "END RECORD\n"
            )

        with open(f"{DATASET}/branch/deeper/ignored.log.bak", "w") as f:
            f.write(
                "BEGIN RECORD\nExperiment: SHOULD-NOT-APPEAR\n"
                "Status: SUCCESS\nResult: 1.0\nEND RECORD\n"
            )
        with open(f"{DATASET}/notes.txt", "w") as f:
            f.write("not a log\n")

        os.symlink("..", f"{DATASET}/branch/deeper/loop_to_branch")
        os.symlink(".", f"{DATASET}/root_loop")

        if os.path.lexists(RESULTS):
            os.unlink(RESULTS)
        run_program()

        expected_data = sorted(zip(ids, values), key=lambda item: item[0])
        expected = [["Experiment", "Result"]] + [[key, value] for key, value in expected_data]
        assert os.path.isfile(RESULTS), "Program did not generate results.csv for the verifier dataset."
        assert read_csv(RESULTS) == expected, "Program output was incorrect for verifier-generated records."
    finally:
        if os.path.lexists(DATASET):
            shutil.rmtree(DATASET)
        if os.path.exists(original_dataset):
            os.rename(original_dataset, DATASET)
        if old_results is None:
            if os.path.lexists(RESULTS):
                os.unlink(RESULTS)
        else:
            with open(RESULTS, "wb") as f:
                f.write(old_results)
        shutil.rmtree(holder, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
