#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import stat
import subprocess
from collections import OrderedDict

import pytest

SOURCE = "/home/user/max_degree.c"
EXECUTABLE = "/home/user/max_degree"
RESULT = "/home/user/result.txt"
LOG = "/home/user/pipeline.log"
REBUILT = "/tmp/max_degree_rebuilt"


def run_program(path, lines, trailing_newline=True):
    data = "\n".join(lines)
    if trailing_newline and lines:
        data += "\n"
    try:
        process = subprocess.run(
            [path],
            input=data,
            text=True,
            capture_output=True,
            check=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out while reading standard input.")
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"{path} failed with return code {exc.returncode}. Stderr: {exc.stderr}"
        )
    return process.stdout.strip()


def expected_for_sorted_lines(lines):
    counts = OrderedDict()
    for line in lines:
        counts[line] = counts.get(line, 0) + 1
    winner = max(counts, key=counts.get)
    return f"MAX_NODE={winner} COUNT={counts[winner]}"


def assert_dataset(path, lines, trailing_newline=True):
    expected = expected_for_sorted_lines(lines)
    actual = run_program(path, lines, trailing_newline)
    assert actual == expected, (
        f"{path} produced incorrect output. Expected {expected!r}, got {actual!r}."
    )


def test_c_source_file_exists():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_executable_exists_and_executable():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file."
    st = os.stat(EXECUTABLE)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), (
        f"{EXECUTABLE} is not executable."
    )
    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", (
            f"{EXECUTABLE} is not a native compiled executable."
        )


def test_result_file_content():
    assert os.path.exists(RESULT), (
        f"Result file {RESULT} does not exist. Did you run your pipeline and redirect output?"
    )
    with open(RESULT, "r") as handle:
        content = handle.read().strip()

    # Preserve the original assertion for the supplied log.
    expected = "MAX_NODE=extract_transactions COUNT=5"
    assert content == expected, f"Expected {expected!r} in {RESULT}, but got {content!r}."

    # Independently derive the answer by extracting only valid dependency sources.
    sources = []
    pattern = re.compile(r"^\[DEPENDENCY\]\s+(\S+)\s+->\s+\S+\s*$")
    with open(LOG, "r") as handle:
        for raw_line in handle:
            match = pattern.match(raw_line.rstrip("\n"))
            if match:
                sources.append(match.group(1))
    assert sources, "No dependency records were found in pipeline.log."
    sources.sort()
    derived = expected_for_sorted_lines(sources)
    assert content == derived, (
        f"{RESULT} does not match the result derived from dependency lines: {derived!r}."
    )


def test_max_degree_executable_behavior():
    # Preserve the original fixed behavior assertion.
    lines = ["nodeA", "nodeB", "nodeB", "nodeC", "nodeC", "nodeC", "nodeD"]
    expected = "MAX_NODE=nodeC COUNT=3"
    output = run_program(EXECUTABLE, lines)
    assert output == expected, (
        f"Executable produced incorrect output. Expected {expected!r}, got {output!r}."
    )


def test_source_compiles():
    process = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", REBUILT],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert process.returncode == 0, f"max_degree.c did not compile with gcc:\n{process.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_submitted_and_rebuilt_programs_on_derived_inputs():
    assert os.path.exists(REBUILT), "Rebuilt executable is missing."

    nonce = secrets.token_hex(8)
    datasets = []

    # Equal maxima verify that the first encountered sorted node wins.
    datasets.append(([f"a_{nonce}"] * 4 + [f"b_{nonce}"] * 4 + [f"z_{nonce}"], True))

    # Verify correct EOF handling when the final line has no newline.
    datasets.append(([f"eof_a_{nonce}", f"eof_b_{nonce}", f"eof_b_{nonce}"], False))

    # Exercise the required maximum supported line length.
    long_name = "m" + nonce + ("x" * (255 - len(nonce) - 1))
    assert len(long_name) == 255
    datasets.append((sorted([long_name] * 5 + [f"z_{nonce}"] * 3), True))

    # Generate unpredictable sorted frequency sets and derive each answer locally.
    rng = random.SystemRandom()
    for case in range(10):
        names = sorted({f"n_{secrets.token_hex(6)}_{case}" for _ in range(7)})
        counts = [rng.randint(1, 9) for _ in names]
        lines = []
        for name, count in zip(names, counts):
            lines.extend([name] * count)
        datasets.append((lines, bool(rng.getrandbits(1))))

    for program in (EXECUTABLE, REBUILT):
        for lines, trailing_newline in datasets:
            assert_dataset(program, lines, trailing_newline)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
