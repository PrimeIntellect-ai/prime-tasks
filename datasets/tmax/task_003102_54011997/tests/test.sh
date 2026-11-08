#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import subprocess

SOURCE = "/home/user/mcmc_mapper.cpp"
EXECUTABLE = "/home/user/mcmc_mapper"
READS = "/home/user/reads.csv"
MESH_OUTPUT = "/home/user/mesh_stats.txt"
MEAN_OUTPUT = "/home/user/posterior_mean.txt"

ORIGINAL_ROWS = [
    (5.5, 10), (15.0, 20), (25.2, 50), (35.1, 150),
    (41.2, 300), (43.5, 400), (44.8, 200), (47.5, 100),
    (55.0, 80), (65.0, 30), (75.0, 10), (85.0, 5), (95.0, 2),
]


def write_reads(rows):
    with open(READS, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["location", "count"])
        writer.writerows(rows)


def clear_outputs():
    for path in (MESH_OUTPUT, MEAN_OUTPUT):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f"Expected output path {path} is a file, not a directory.")
            os.unlink(path)


def run_mapper(path):
    clear_outputs()
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_outputs():
    assert os.path.exists(MESH_OUTPUT), f"The output file {MESH_OUTPUT} is missing."
    with open(MESH_OUTPUT, "r") as f:
        mesh_content = f.read().strip()

    assert os.path.exists(MEAN_OUTPUT), f"The output file {MEAN_OUTPUT} is missing."
    with open(MEAN_OUTPUT, "r") as f:
        mean_content = f.read().strip()

    match = re.match(r"^Mean mu:\s*([0-9.]+)$", mean_content)
    assert match is not None, (
        f"The format of {MEAN_OUTPUT} is incorrect. "
        f"Expected 'Mean mu: <value>', got '{mean_content}'."
    )
    mean_val = float(match.group(1))
    assert math.isfinite(mean_val)
    return mesh_content, mean_val


def expected_for(rows):
    initial = [[] for _ in range(10)]
    for location, count in rows:
        index = 9 if location == 100.0 else int(location // 10.0)
        assert 0 <= index < 10
        initial[index].append((location, count))

    final_weighted_sum = 0.0
    total_count = 0
    final_bins = 0
    for index, entries in enumerate(initial):
        bin_count = sum(count for _, count in entries)
        left = index * 10.0
        if bin_count > 500:
            final_bins += 2
            split = left + 5.0
            lower = sum(count for location, count in entries if location < split)
            upper = sum(count for location, count in entries if location >= split)
            final_weighted_sum += lower * (left + 2.5)
            final_weighted_sum += upper * (left + 7.5)
        else:
            final_bins += 1
            final_weighted_sum += bin_count * (left + 5.0)
        total_count += bin_count

    return final_bins, final_weighted_sum / total_count


def assert_dynamic_outputs(rows, executable, tolerance=0.35):
    expected_bins, expected_mean = expected_for(rows)
    write_reads(rows)
    run_mapper(executable)
    mesh_content, mean_val = read_outputs()
    assert mesh_content == f"Final bins: {expected_bins}", (
        f"Expected 'Final bins: {expected_bins}' for generated input, "
        f"but got '{mesh_content}'."
    )
    assert abs(mean_val - expected_mean) <= tolerance, (
        f"For generated input, expected posterior mean near {expected_mean:.4f}, "
        f"but got {mean_val}."
    )


def test_complete_mapper_behavior():
    # Preserve the original artifact assertions.
    assert os.path.exists(SOURCE), f"The source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a regular file."

    assert os.path.exists(EXECUTABLE), f"The executable {EXECUTABLE} is missing. Did you compile the code?"
    assert os.path.isfile(EXECUTABLE), f"The path {EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The executable {EXECUTABLE} is not a compiled ELF program."

    # Execute the submitted artifact on the original data and retain the
    # original verifier's exact output assertions.
    write_reads(ORIGINAL_ROWS)
    run_mapper(EXECUTABLE)
    mesh_content, mean_val = read_outputs()
    assert mesh_content == "Final bins: 11", (
        f"Expected 'Final bins: 11' in {MESH_OUTPUT}, but got '{mesh_content}'."
    )
    assert 42.30 <= mean_val <= 42.55, (
        f"Expected posterior mean to be around 42.42, but got {mean_val}."
    )

    # Rebuild the submitted source so a stale or unrelated executable cannot
    # satisfy the behavioral checks.
    rebuilt = "/tmp/mcmc_mapper_rebuilt"
    compile_result = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"The submitted C++ source did not compile.\n{compile_result.stderr}"
    )

    rng = random.Random(secrets.randbits(128))

    # Generated mesh case: a runtime-random subset of initial bins must split.
    refined = set(rng.sample(range(10), rng.randint(2, 6)))
    mesh_rows = []
    for index in range(10):
        if index in refined:
            counts = (rng.randint(260, 420), rng.randint(260, 420))
        else:
            counts = (rng.randint(20, 120), rng.randint(20, 120))
        mesh_rows.append((index * 10.0 + 1.3, counts[0]))
        mesh_rows.append((index * 10.0 + 8.7, counts[1]))
    assert_dynamic_outputs(mesh_rows, EXECUTABLE)

    # Generated posterior case: choose one of two well-separated expression
    # origins and validate the binary rebuilt from the submitted source.
    target_bin = rng.choice([2, 7])
    posterior_rows = []
    for index in range(10):
        if index == target_bin:
            lower = rng.randint(650, 900)
            upper = rng.randint(350, 500)
        else:
            lower = rng.randint(2, 5)
            upper = rng.randint(2, 5)
        posterior_rows.append((index * 10.0 + 0.8, lower))
        posterior_rows.append((index * 10.0 + 9.2, upper))
    assert_dynamic_outputs(posterior_rows, rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
