#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import random
import struct
import subprocess
import time

import pytest

CLUSTER_DIR = "/home/user/clustering"
CLUSTER_SOURCE = os.path.join(CLUSTER_DIR, "cluster.c")
CLUSTER_FIXED = os.path.join(CLUSTER_DIR, "cluster_fixed")
FINAL_OUTPUT = "/home/user/final_output.txt"
DATA_FILE = os.path.join(CLUSTER_DIR, "data.bin")
SOURCE_BUILD = "/tmp/cluster_built_by_verifier"


def parse_centroids(content):
    lines = [line.strip() for line in content.strip().split("\n") if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 centroid lines, found {len(lines)}: {content!r}"
    values = []
    for expected_index, line in enumerate(lines):
        match = re.fullmatch(r"Centroid (\d+): ([+-]?(?:\d+(?:\.\d*)?|\.\d+))", line)
        assert match, f"Invalid centroid output line: {line!r}"
        assert int(match.group(1)) == expected_index, f"Expected Centroid {expected_index}, got {line!r}"
        value = float(match.group(2))
        assert math.isfinite(value), f"Centroid is not finite: {line!r}"
        values.append(value)
    return values


def reference_cluster(points):
    centroids = [0.0, 50.0, 100.0]
    for _ in range(100):
        sums = [0.0, 0.0, 0.0]
        counts = [0, 0, 0]
        for point in points:
            best = min(range(3), key=lambda i: abs(point - centroids[i]))
            sums[best] += point
            counts[best] += 1
        updated = [sums[i] / counts[i] if counts[i] else centroids[i] for i in range(3)]
        converged = all(abs(updated[i] - centroids[i]) <= 1e-4 for i in range(3))
        centroids = updated
        if converged:
            break
    return centroids


def run_program(path, payload, partial=False):
    read_fd, write_fd = os.pipe()
    process = subprocess.Popen(
        [path], stdin=read_fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    os.close(read_fd)
    try:
        if partial and payload:
            offsets = [1, 6, 23, 87, 218, len(payload)]
            start = 0
            for end in offsets:
                end = min(end, len(payload))
                if end > start:
                    os.write(write_fd, payload[start:end])
                    start = end
                    time.sleep(0.04 if start == 1 else 0.005)
                if start == len(payload):
                    break
        else:
            view = memoryview(payload)
            while view:
                written = os.write(write_fd, view)
                view = view[written:]
    except BrokenPipeError:
        pass
    finally:
        os.close(write_fd)

    try:
        stdout, stderr = process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
        pytest.fail(f"{path} did not terminate after standard input reached EOF")
    return process.returncode, stdout, stderr


def assert_matches_reference(path, points, partial):
    payload = struct.pack(f"={len(points)}d", *points)
    returncode, stdout, stderr = run_program(path, payload, partial=partial)
    assert returncode == 0, f"{path} exited with {returncode}: {stderr.decode(errors='replace')}"
    actual = parse_centroids(stdout.decode())
    expected = reference_cluster(points)
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert abs(got - want) <= 0.0006, (
            f"Centroid {index} from {path} was {got}, expected {want:.4f}"
        )


@pytest.fixture(scope="session", autouse=True)
def compile_and_check_source():
    assert os.path.isfile(CLUSTER_SOURCE), f"Source file {CLUSTER_SOURCE} does not exist."
    with open(CLUSTER_SOURCE, "r", encoding="utf-8", errors="replace") as source_file:
        source = source_file.read()
    assert re.search(r"^\s*#\s*include\s*[<\"]assert\.h[>\"]", source, re.MULTILINE), (
        "cluster.c must include assert.h for the requested assertion-based validation."
    )
    assert re.search(r"\bassert\s*\(", source), (
        "cluster.c does not contain the requested assertion-based validation."
    )
    result = subprocess.run(
        ["gcc", "-o", SOURCE_BUILD, CLUSTER_SOURCE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"cluster.c does not compile: {result.stderr.decode(errors='replace')}"
    os.chmod(SOURCE_BUILD, 0o755)
    yield


def test_cluster_fixed_exists():
    path = "/home/user/clustering/cluster_fixed"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile your fixed code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "cluster_fixed must be a compiled ELF executable."


def test_final_output_exists():
    path = "/home/user/final_output.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist. Did you run the final command?"


def test_final_output_content():
    path = "/home/user/final_output.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    assert "NaN" not in content and "nan" not in content, "Output contains NaN. The algorithmic bug (division by zero) might not be fully fixed."

    lines = [line.strip() for line in content.strip().split('\n') if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 lines of output in {path}, found {len(lines)}."

    centroids = []
    for line in lines:
        match = re.match(r"Centroid \d:\s*([+-]?\d*\.?\d+)", line)
        assert match, f"Line '{line}' does not match expected format 'Centroid X: Y'."
        centroids.append(float(match.group(1)))

    centroids.sort()

    assert 5.0 < centroids[0] < 15.0, f"First centroid {centroids[0]} is not around the expected value of 10.0. Did you fix the partial read bug?"
    assert 45.0 < centroids[1] < 55.0, f"Second centroid {centroids[1]} is not around the expected value of 50.0. Did you fix the partial read bug?"
    assert 85.0 < centroids[2] < 95.0, f"Third centroid {centroids[2]} is not around the expected value of 90.0. Did you fix the partial read bug?"


def test_final_output_was_produced_by_cluster_fixed():
    with open(DATA_FILE, "rb") as data_file:
        payload = data_file.read()
    returncode, stdout, stderr = run_program(CLUSTER_FIXED, payload, partial=False)
    assert returncode == 0, f"cluster_fixed failed on data.bin: {stderr.decode(errors='replace')}"
    with open(FINAL_OUTPUT, "rb") as output_file:
        saved = output_file.read()
    assert saved == stdout, "final_output.txt is not the output produced by cluster_fixed on data.bin."
    points = list(struct.unpack(f"={len(payload) // 8}d", payload))
    actual = parse_centroids(stdout.decode())
    expected = reference_cluster(points)
    for got, want in zip(actual, expected):
        assert abs(got - want) <= 0.0006


@pytest.mark.parametrize("path", [CLUSTER_FIXED, SOURCE_BUILD])
def test_partial_pipe_reads_are_completed(path):
    rng = random.SystemRandom()
    points = ([10.0 + rng.uniform(-1.5, 1.5) for _ in range(33)] +
              [50.0 + rng.uniform(-1.5, 1.5) for _ in range(33)] +
              [90.0 + rng.uniform(-1.5, 1.5) for _ in range(34)])
    rng.shuffle(points)
    assert_matches_reference(path, points, partial=True)


@pytest.mark.parametrize("path", [CLUSTER_FIXED, SOURCE_BUILD])
def test_empty_clusters_keep_previous_centroids(path):
    points = [1.25] * 100
    assert_matches_reference(path, points, partial=True)


@pytest.mark.parametrize("path", [CLUSTER_FIXED, SOURCE_BUILD])
def test_truncated_input_is_rejected(path):
    payload = struct.pack("=10d", *([7.0] * 10))
    returncode, stdout, stderr = run_program(path, payload, partial=True)
    assert returncode != 0, f"{path} accepted a truncated input containing only 10 of 100 points."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
