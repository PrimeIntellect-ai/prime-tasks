#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import time

import pytest

DATASET_PATH = "/home/user/dataset.txt"
CPP_PATH = "/home/user/resolver.cpp"
BINARY_PATH = "/home/user/resolver"
ORIGINAL_DATASET = "pkgA>=1.0.0,<2.0.0\npkgB>=1.5.0\npkgA<=1.9.0\npkgC>=0.0.1\n"


def version_tuple(text):
    parts = text.split(".")
    assert len(parts) == 3
    return tuple(int(part) for part in parts)


def derive_expected(dataset):
    constraints = {}
    candidates = {}
    line_re = re.compile(r"^([A-Za-z][A-Za-z0-9_]*)(.*)$")
    constraint_re = re.compile(r"^(>=|<=|>|<|=)(\d+\.\d+\.\d+)$")

    for raw_line in dataset.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = line_re.fullmatch(line)
        assert match, f"Malformed generated line: {line}"
        package, tail = match.groups()
        constraints.setdefault(package, [])
        candidates.setdefault(package, set())
        for item in tail.split(","):
            parsed = constraint_re.fullmatch(item.strip())
            assert parsed, f"Malformed generated constraint: {item}"
            op, version_text = parsed.groups()
            version = version_tuple(version_text)
            constraints[package].append((op, version))
            candidates[package].add(version)

    def valid(version, package_constraints):
        for op, bound in package_constraints:
            if op == ">=" and not version >= bound:
                return False
            if op == "<=" and not version <= bound:
                return False
            if op == ">" and not version > bound:
                return False
            if op == "<" and not version < bound:
                return False
            if op == "=" and not version == bound:
                return False
        return True

    output = []
    for package in sorted(constraints):
        valid_versions = [
            version for version in candidates[package]
            if valid(version, constraints[package])
        ]
        assert valid_versions, f"Generated unsatisfiable package: {package}"
        chosen = max(valid_versions)
        output.append(f"{package}: {chosen[0]}.{chosen[1]}.{chosen[2]}")
    return "\n".join(output)


def run_resolver(dataset, timeout=3.0):
    with open(DATASET_PATH, "w") as dataset_file:
        dataset_file.write(dataset)

    start = time.perf_counter()
    proc = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    elapsed = time.perf_counter() - start
    assert proc.returncode == 0, f"Execution failed:\n{proc.stderr}"
    return proc.stdout.strip(), elapsed


def test_dataset_extracted():
    assert os.path.isfile(DATASET_PATH), f"File {DATASET_PATH} does not exist."
    with open(DATASET_PATH, "r") as dataset_file:
        content = dataset_file.read()
    assert content == ORIGINAL_DATASET, f"Extracted dataset content does not match expected. Got:\n{content}"


def test_cpp_compilation_and_performance():
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} does not exist."

    compile_cmd = ["g++", "-O3", "-pthread", "-std=c++20", CPP_PATH, "-o", BINARY_PATH]
    compile_proc = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} was not created."

    output, execution_time = run_resolver(ORIGINAL_DATASET)
    expected_output = "pkgA: 1.9.0\npkgB: 1.5.0\npkgC: 0.0.1"
    assert output == expected_output, f"Output did not match expected. Got:\n{output}\nExpected:\n{expected_output}"
    assert execution_time <= 0.5, f"Execution time {execution_time:.4f}s exceeded threshold of 0.5s."


def test_resolver_handles_unseen_constraints():
    nonce = secrets.token_hex(6)
    rows = []
    for index in range(31):
        package = f"p{nonce}_{index:03d}"
        low = (index % 3, index % 7, index % 11)
        floor = (low[0] + 1, (index * 3) % 10, (index * 5) % 13)
        cap = (floor[0] + 2, (index * 7) % 12, (index * 11) % 17)
        ceiling = (cap[0] + 2, 0, 0)
        fmt = lambda value: f"{value[0]}.{value[1]}.{value[2]}"
        rows.extend([
            f"{package}>={fmt(low)},<{fmt(ceiling)}",
            f"{package}<={fmt(cap)}",
            f"{package}>={fmt(floor)}",
        ])
    random.SystemRandom().shuffle(rows)
    dataset = "\n".join(rows) + "\n"
    expected = derive_expected(dataset)
    output, _ = run_resolver(dataset)
    assert output == expected, f"Resolver failed on unseen input. Got:\n{output}\nExpected:\n{expected}"


def test_scaled_dataset_and_runtime():
    nonce = secrets.token_hex(8)
    rows = []
    for index in range(4000):
        package = f"scale_{nonce}_{index:05d}"
        low = (index % 4, index % 9, index % 15)
        floor = (low[0] + 1, (index * 5) % 20, (index * 7) % 30)
        cap = (floor[0] + 3, (index * 11) % 20, (index * 13) % 30)
        ceiling = (cap[0] + 2, 0, 0)
        fmt = lambda value: f"{value[0]}.{value[1]}.{value[2]}"
        rows.extend([
            f"{package}>={fmt(low)},<{fmt(ceiling)}",
            f"{package}>={fmt(floor)}",
            f"{package}<={fmt(cap)}",
            f"{package}>={fmt(low)}",
            f"{package}<={fmt(ceiling)}",
            f"{package}>={fmt(floor)},<={fmt(cap)}",
            f"{package}>={fmt(low)}",
            f"{package}<={fmt(cap)}",
            f"{package}>={fmt(floor)}",
            f"{package}<{fmt(ceiling)}",
            f"{package}>={fmt(low)},<={fmt(cap)}",
            f"{package}>={fmt(floor)}",
        ])

    random.SystemRandom().shuffle(rows)
    dataset = "\n".join(rows) + "\n"
    expected = derive_expected(dataset)
    output, execution_time = run_resolver(dataset)
    assert output == expected, "Resolver produced an incorrect resolution on the scaled dataset."
    assert execution_time <= 0.5, f"Scaled execution time {execution_time:.4f}s exceeded threshold of 0.5s."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
