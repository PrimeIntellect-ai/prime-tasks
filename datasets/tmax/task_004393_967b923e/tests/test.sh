#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

BASE_DIR = "/home/user/ws_filter"
BINARY = os.path.join(BASE_DIR, "ws_filter")


def test_binary_exists():
    binary_path = "/home/user/ws_filter/ws_filter"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist. Did you run make?"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_allowed_log_contents():
    log_path = "/home/user/allowed.log"
    assert os.path.isfile(log_path), f"Output file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["101", "104", "105", "106"]
    assert lines == expected, f"Contents of {log_path} are incorrect. Expected {expected}, got {lines}."


def test_makefile_fixed():
    makefile_path = "/home/user/ws_filter/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "semver.o" in content, "Makefile does not appear to link semver.o."

    result = subprocess.run(
        ["make", "-B", "-n", "ws_filter"], cwd=BASE_DIR,
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"make dry run failed:\n{result.stderr}"
    link_lines = [line for line in result.stdout.splitlines() if "-o ws_filter" in line]
    assert link_lines, "Makefile does not contain a command that links ws_filter."
    assert any("semver.o" in line for line in link_lines), (
        "semver.o is mentioned in the Makefile but is not included in the ws_filter link command."
    )


def test_build_success():
    # Run make clean and make to ensure it builds correctly
    subprocess.run(["make", "clean"], cwd=BASE_DIR, capture_output=True)

    result = subprocess.run(["make"], cwd=BASE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"

    assert os.path.isfile(BINARY), "make succeeded but ws_filter binary was not created."
    assert os.path.isfile(os.path.join(BASE_DIR, "semver.o")), "make did not build semver.o."

    symbols = subprocess.run(["nm", "-C", BINARY], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Could not inspect rebuilt binary: {symbols.stderr}"
    assert "compare_semver" in symbols.stdout, "Rebuilt ws_filter does not link compare_semver."


def version_tuple(version):
    parts = [int(part) for part in version.split(".")]
    parts += [0] * (3 - len(parts))
    return tuple(parts[:3])


def expected_result(client, op, target):
    left = version_tuple(client)
    right = version_tuple(target)
    return {
        "<": left < right,
        ">": left > right,
        "<=": left <= right,
        ">=": left >= right,
        "==": left == right,
    }[op]


def policy_cases():
    cases = [
        ("1.0.0", "==", "1.0.0"),
        ("1.0.1", "==", "1.0.0"),
        ("1.2.0", ">", "1.1.99"),
        ("1.2.0", ">", "1.2.0"),
        ("0.9.9", "<", "1.0.0"),
        ("2.0.0", "<", "2.0.0"),
        ("3.4.5", ">=", "3.4.5"),
        ("3.4.4", ">=", "3.4.5"),
        ("7.0.0", "<=", "7.0.0"),
        ("7.0.1", "<=", "7.0.0"),
        ("1.12.0", ">", "1.2.0"),
    ]
    rng = random.Random(731942)
    operators = ["<", ">", "<=", ">=", "=="]
    for _ in range(80):
        client = ".".join(str(rng.randrange(0, 15)) for _ in range(3))
        target = ".".join(str(rng.randrange(0, 15)) for _ in range(3))
        cases.append((client, rng.choice(operators), target))
    return cases


def test_evaluate_policy_directly():
    harness_source = r'''
#include "policy.h"
#include <iostream>
#include <string>

int main() {
    std::string client, expression;
    while (std::getline(std::cin, client, '|') && std::getline(std::cin, expression)) {
        std::cout << (evaluate_policy(client, expression) ? "1" : "0") << "\n";
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_cpp = os.path.join(td, "policy_harness.cpp")
        harness_bin = os.path.join(td, "policy_harness")
        with open(harness_cpp, "w") as f:
            f.write(harness_source)

        compile_result = subprocess.run([
            "g++", "-std=c++17", "-Wall", "-I", BASE_DIR,
            harness_cpp,
            os.path.join(BASE_DIR, "policy.cpp"),
            os.path.join(BASE_DIR, "semver.cpp"),
            "-o", harness_bin,
        ], capture_output=True, text=True)
        assert compile_result.returncode == 0, (
            "Could not compile evaluate_policy test harness:\n" + compile_result.stderr
        )

        cases = policy_cases()
        input_text = "".join(f"{client}|V {op} {target}\n" for client, op, target in cases)
        run = subprocess.run([harness_bin], input=input_text, capture_output=True, text=True)
        assert run.returncode == 0, f"evaluate_policy harness failed: {run.stderr}"

        actual = run.stdout.splitlines()
        expected = ["1" if expected_result(c, op, t) else "0" for c, op, t in cases]
        assert actual == expected, "evaluate_policy returned incorrect results for generated semantic-version policies."


def test_rebuilt_binary_on_derived_requests():
    cases = policy_cases()
    with tempfile.TemporaryDirectory() as td:
        request_path = os.path.join(td, "requests.txt")
        with open(request_path, "w") as f:
            for index, (client, op, target) in enumerate(cases, start=5000):
                f.write(f"{index} | {client} | V {op} {target}\n")

        run = subprocess.run([BINARY, request_path], cwd=BASE_DIR, capture_output=True, text=True)
        assert run.returncode == 0, f"Rebuilt ws_filter failed: {run.stderr}"
        actual = [line.strip() for line in run.stdout.splitlines() if line.strip()]
        expected = [
            str(index)
            for index, (client, op, target) in enumerate(cases, start=5000)
            if expected_result(client, op, target)
        ]
        assert actual == expected, "Rebuilt ws_filter produced incorrect output on generated requests."


def test_binary_reproduces_allowed_log():
    run = subprocess.run(
        [BINARY, os.path.join(BASE_DIR, "ws_requests.txt")],
        cwd=BASE_DIR, capture_output=True, text=True
    )
    assert run.returncode == 0, f"ws_filter failed on ws_requests.txt: {run.stderr}"
    with open("/home/user/allowed.log", "r") as f:
        logged = f.read()
    assert run.stdout == logged, "allowed.log is not the output produced by the rebuilt ws_filter."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
