#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import time

HOME = "/home/user"
SOURCE = f"{HOME}/process.c"
SCRIPT = f"{HOME}/pipeline.sh"
INPUT = f"{HOME}/sensors.csv"
OUTPUT = f"{HOME}/sampled_output.csv"


def process_lines(rows):
    lines = []
    for x, y, z in rows:
        dist = math.sqrt(x ** 2 + y ** 2 + z ** 2)
        stratum = int(dist) % 3
        h = int(x) ^ int(y) ^ int(z)
        lines.append(f"{stratum},{h},{x:.2f},{y:.2f},{z:.2f}")
    return lines


def sampled_lines(rows):
    seen_hashes = set()
    stratum_counts = {0: 0, 1: 0, 2: 0}
    records = []

    for x, y, z in rows:
        dist = math.sqrt(x ** 2 + y ** 2 + z ** 2)
        stratum = int(dist) % 3
        h = int(x) ^ int(y) ^ int(z)

        if h in seen_hashes:
            continue
        seen_hashes.add(h)

        if stratum_counts[stratum] < 2:
            stratum_counts[stratum] += 1
            records.append((stratum, f"{stratum},{h},{x:.2f},{y:.2f},{z:.2f}"))

    records.sort(key=lambda item: item[0])
    return [record for _, record in records]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def test_process_c_exists():
    assert os.path.isfile(SOURCE), "The C program /home/user/process.c is missing."


def test_pipeline_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."


def test_sampled_output():
    assert os.path.isfile(INPUT), f"Input file {INPUT} is missing."
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."

    seen_hashes = set()
    stratum_counts = {0: 0, 1: 0, 2: 0}
    expected_records = []

    with open(INPUT, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
            dist = math.sqrt(x**2 + y**2 + z**2)
            int_dist = int(dist)
            stratum = int_dist % 3
            h = int(x) ^ int(y) ^ int(z)

            if h in seen_hashes:
                continue
            seen_hashes.add(h)

            if stratum_counts[stratum] < 2:
                stratum_counts[stratum] += 1
                formatted_record = f"{stratum},{h},{x:.2f},{y:.2f},{z:.2f}"
                expected_records.append((stratum, formatted_record))

    expected_records.sort(key=lambda item: item[0])
    expected_lines = [item[1] for item in expected_records]
    expected_content = "\n".join(expected_lines) + "\n"

    with open(OUTPUT, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {OUTPUT} does not match expected output.\n"
        f"Expected:\n{expected_content.strip()}\n\n"
        f"Actual:\n{actual_content.strip()}"
    )


def test_compiled_program_and_pipeline_on_unseen_input():
    rng = secrets.SystemRandom()

    # Build a runtime-randomized input with more than two unique records in each
    # stratum. Fractional parts are exactly representable, avoiding formatter
    # differences while still testing integer casts.
    by_stratum = {0: [], 1: [], 2: []}
    used_hashes = set()
    attempts = 0
    while any(len(by_stratum[s]) < 4 for s in range(3)):
        attempts += 1
        assert attempts < 10000, "Could not construct randomized test data"
        row = (rng.randrange(0, 81) + 0.25,
               rng.randrange(0, 81) + 0.25,
               rng.randrange(0, 81) + 0.25)
        x, y, z = row
        h = int(x) ^ int(y) ^ int(z)
        stratum = int(math.sqrt(x*x + y*y + z*z)) % 3
        if h in used_hashes or len(by_stratum[stratum]) >= 4:
            continue
        used_hashes.add(h)
        by_stratum[stratum].append(row)

    rows = by_stratum[0] + by_stratum[1] + by_stratum[2]
    rng.shuffle(rows)

    # Add a distinct row with the same integer-cast coordinates, hence the same
    # hash, after its original. Correct deduplication must retain the first row.
    base_index = rng.randrange(len(rows))
    bx, by, bz = rows[base_index]
    collision = (int(bx) + 0.75, int(by) + 0.75, int(bz) + 0.75)
    rows.insert(base_index + 1, collision)

    input_text = "".join(f"{x},{y},{z}\n" for x, y, z in rows)

    # Compile and execute process.c independently so a dummy source file cannot
    # be hidden behind a precomputed sampled_output.csv.
    compiled = "/tmp/submission_process"
    subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-lm", "-o", compiled],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    result = subprocess.run(
        [compiled], input=input_text, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10
    )
    assert result.stdout.splitlines() == process_lines(rows), (
        "The compiled process.c produced incorrect records on unseen input.\n"
        f"Expected:\n{os.linesep.join(process_lines(rows))}\n"
        f"Actual:\n{result.stdout}"
    )

    original_input = open(INPUT, "rb").read()
    try:
        with open(INPUT, "w") as f:
            f.write(input_text)

        # Force pipeline.sh to create process itself rather than relying on an
        # executable left behind by this verifier or by the agent.
        process_path = f"{HOME}/process"
        if os.path.lexists(process_path):
            os.remove(process_path)
        started = time.time()

        subprocess.run(
            [SCRIPT], cwd=HOME, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

        assert os.path.isfile(process_path), "pipeline.sh did not create /home/user/process."
        assert os.access(process_path, os.X_OK), "The process created by pipeline.sh is not executable."
        assert os.path.getmtime(process_path) >= started - 1, "pipeline.sh did not freshly create process."
        with open(process_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The process created by pipeline.sh is not a compiled executable."

        # Exercise the executable produced by the pipeline as well.
        generated = subprocess.run(
            [process_path], input=input_text, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10
        )
        assert generated.stdout.splitlines() == process_lines(rows), (
            "The process executable produced by pipeline.sh behaves incorrectly."
        )

        assert os.path.isfile(OUTPUT), "pipeline.sh did not create sampled_output.csv."
        actual = read_nonempty_lines(OUTPUT)
        expected = sampled_lines(rows)
        assert actual == expected, (
            "pipeline.sh produced incorrect output on unseen input.\n"
            f"Expected:\n{os.linesep.join(expected)}\n\n"
            f"Actual:\n{os.linesep.join(actual)}"
        )
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
