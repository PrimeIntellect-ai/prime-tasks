#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import re
import stat
import subprocess
import tempfile

import pytest


def collatz(n):
    steps = 0
    while n > 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


def test_minimal_repro_txt():
    path = "/home/user/minimal_repro.txt"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "-14", f"Expected minimal_repro.txt to contain '-14', but got '{content}'"


def test_math_worker_fixed_cpp():
    path = "/home/user/math_worker_fixed.cpp"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "mutex" in content, "Expected to find 'mutex' in math_worker_fixed.cpp to prevent interleaving"

    compiled = "/tmp/math_worker_from_submitted_source"
    result = subprocess.run(
        ["g++", "-std=c++11", "-pthread", path, "-o", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Submitted fixed source does not compile: {result.stderr}"
    exercise_worker(compiled)


def test_math_worker_fixed_executable():
    path = "/home/user/math_worker_fixed"
    assert os.path.isfile(path), f"Missing compiled executable at {path}"
    assert os.access(path, os.X_OK), f"File {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"
    exercise_worker(path)


def exercise_worker(path):
    values = []
    for i in range(1, 1601):
        values.append((i * 7919) % 50000 + 1)
        if i % 173 == 0:
            values.append(-i)

    expected = collections.Counter()
    for n in values:
        if n <= 0:
            expected[(n, "error", None)] += 1
        else:
            expected[(n, "steps", collatz(n))] += 1

    valid = re.compile(r"Number: (-?\d+), (?:Steps: (\d+)|Error: Domain)")
    for _ in range(4):
        result = subprocess.run(
            [path] + [str(n) for n in values],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Worker exited with {result.returncode}: {result.stderr}"
        actual = collections.Counter()
        lines = result.stdout.splitlines()
        assert len(lines) == len(values), "Worker emitted a missing, extra, or interleaved output line"
        for line in lines:
            match = valid.fullmatch(line)
            assert match, f"Malformed/interleaved worker output: {line!r}"
            n = int(match.group(1))
            if match.group(2) is None:
                actual[(n, "error", None)] += 1
            else:
                actual[(n, "steps", int(match.group(2)))] += 1
        assert actual == expected, "Worker output values or Collatz stopping times are incorrect"


def test_parser_fixed_execution():
    parser_path = "/home/user/parser_fixed.py"
    data_path = "/home/user/data_batch.txt"
    assert os.path.isfile(parser_path), f"Missing {parser_path}"

    try:
        subprocess.check_call(
            ["python3", parser_path, data_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"parser_fixed.py failed to process data_batch.txt. Exit code: {e.returncode}")
    except subprocess.TimeoutExpired:
        pytest.fail("parser_fixed.py timed out while processing data_batch.txt")


def test_parser_actually_invokes_worker_parses_results_and_skips_errors():
    parser_path = "/home/user/parser_fixed.py"
    worker_paths = ["/home/user/math_worker", "/home/user/math_worker_fixed"]
    rng = random.SystemRandom()
    positives = rng.sample(range(100000, 900000), 23)
    values = []
    for i, n in enumerate(positives):
        values.append(str(n))
        if i in (4, 11, 19):
            values.append(str(-rng.randrange(2, 10000)))
    values.append(str(positives[3]))

    with tempfile.TemporaryDirectory() as td:
        data_path = os.path.join(td, "data.txt")
        log_path = os.path.join(td, "worker_calls.jsonl")
        with open(data_path, "w") as f:
            f.write("\n".join(values) + "\n")

        fake = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["PARSER_WORKER_LOG"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
for raw in sys.argv[1:]:
    n = int(raw)
    if n <= 0:
        print(f"Number: {n}, Error: Domain")
    else:
        print(f"Number: {n}, Steps: {(abs(n) * 7) % 101}")
'''
        backups = {}
        try:
            for path in worker_paths:
                with open(path, "rb") as f:
                    backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
                with open(path, "w") as f:
                    f.write(fake)
                os.chmod(path, 0o755)

            env = os.environ.copy()
            env["PARSER_WORKER_LOG"] = log_path
            result = subprocess.run(
                ["python3", parser_path, data_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                timeout=15,
            )
        finally:
            for path, (content, mode) in backups.items():
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, mode)

        assert result.returncode == 0, f"Parser failed on valid and Error output: {result.stderr}"
        assert os.path.isfile(log_path), "Parser did not invoke either pipeline worker"
        with open(log_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert values in calls, "Parser did not feed the supplied dataset to the worker"
        expected_count = len(set(positives))
        assert re.search(
            rf"Successfully parsed\s+{expected_count}\s+records\.", result.stdout
        ), f"Parser did not parse valid records and skip Error records correctly: {result.stdout!r}"


def test_interleaved_trace_log():
    path = "/home/user/interleaved_trace.log"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"Expected {path} to contain a snippet of the interleaved output, but it is empty"

    normal = re.compile(r"Number: -?\d+, (?:Steps: \d+|Error: Domain)")
    evidence = False
    for line in content.splitlines():
        malformed = normal.fullmatch(line) is None
        race_marker = (
            "NumbeNumber" in line
            or "NumberNumber" in line
            or "StepSteps" in line
            or line.count("Number:") >= 2
            or line.count("Steps:") >= 2
            or ("Steps:" in line and "Error:" in line)
        )
        if malformed and race_marker:
            evidence = True
            break
    assert evidence, "Trace does not contain a malformed line demonstrating interleaved worker output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
