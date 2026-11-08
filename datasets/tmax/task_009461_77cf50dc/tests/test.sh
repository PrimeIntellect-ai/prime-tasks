#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import uuid

import pytest

PROJECT = "/home/user/proxy_analyzer"
BINARY = os.path.join(PROJECT, "proxy_analyzer")
OUTPUT = "/home/user/output.txt"

EXPECTED_LINES = [
    "/login 57.7",
    "/data 55",
    "/calc 14",
    "/auth 2.5",
]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_output_file_exists():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file {path} was not created."


def test_output_file_contents():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file {path} was not created."

    lines = read_nonempty_lines(path)

    expected_lines = [
        "/login 57.7",
        "/data 55",
        "/calc 14",
        "/auth 2.5"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output.txt, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def test_parser_fixed():
    path = "/home/user/proxy_analyzer/parser.cpp"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "std::string_view(word)" not in content, "The dangling reference bug using std::string_view(word) is still present in parser.cpp."


def test_evaluator_implemented():
    path = "/home/user/proxy_analyzer/evaluator.cpp"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    has_stack_include = "<stack>" in content
    has_push = "push" in content
    has_pop = "pop" in content
    has_vector_back = "back" in content and "pop_back" in content

    assert (has_stack_include and has_push and has_pop) or (has_push and has_vector_back), \
        "evaluator.cpp does not appear to implement a stack-based algorithm (missing push/pop or stack operations)."

    assert "+" in content and "-" in content and "*" in content and "/" in content, \
        "evaluator.cpp does not seem to implement all required arithmetic operators (+, -, *, /)."


def parse_program_output(text, expected):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == len(expected), \
        f"Expected {len(expected)} output lines, got {len(lines)}: {lines!r}"

    for index, (line, (endpoint, value)) in enumerate(zip(lines, expected), 1):
        fields = line.split()
        assert len(fields) == 2, f"Malformed output line {index}: {line!r}"
        assert fields[0] == endpoint, \
            f"Line {index} endpoint mismatch: expected {endpoint!r}, got {fields[0]!r}"
        try:
            actual = float(fields[1])
        except ValueError as exc:
            raise AssertionError(f"Line {index} has a non-numeric result: {fields[1]!r}") from exc
        assert math.isfinite(actual), f"Line {index} produced a non-finite result"
        assert math.isclose(actual, value, rel_tol=2e-5, abs_tol=2e-5), \
            f"Line {index} result mismatch: expected {value}, got {actual}"


def make_random_cases():
    rng = random.SystemRandom()
    cases = []

    def number():
        return rng.randint(1, 400) / 4.0

    for shape in range(20):
        a, b, c, d = number(), number(), number(), number()
        if shape % 5 == 0:
            tokens = [a, b, "+", c, "*"]
            result = (a + b) * c
        elif shape % 5 == 1:
            tokens = [a, b, "-", c, "/"]
            result = (a - b) / c
        elif shape % 5 == 2:
            tokens = [a, b, "*", c, "+"]
            result = a * b + c
        elif shape % 5 == 3:
            tokens = [a, b, "/", c, "-"]
            result = a / b - c
        else:
            tokens = [a, b, "+", c, d, "-", "*"]
            result = (a + b) * (c - d)

        rendered = [f"{token:.2f}" if isinstance(token, float) else token for token in tokens]
        endpoint = f"/dynamic/{uuid.uuid4().hex}"
        cases.append((f"ENDPOINT {endpoint} [ {' '.join(rendered)} ]", endpoint, result))

    return cases


def test_clean_build_and_execute_real_implementations():
    subprocess.run(["make", "clean"], cwd=PROJECT, check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    build = subprocess.run(["make"], cwd=PROJECT, timeout=60,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert build.returncode == 0, f"make failed:\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
    assert os.path.isfile(BINARY), "make did not create proxy_analyzer"
    assert os.access(BINARY, os.X_OK), "proxy_analyzer is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy_analyzer is not a compiled ELF executable"

    fixed_run = subprocess.run([BINARY, "/home/user/logs.txt"], cwd=PROJECT, timeout=10,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert fixed_run.returncode == 0, f"proxy_analyzer failed on logs.txt: {fixed_run.stderr}"
    assert [line.strip() for line in fixed_run.stdout.splitlines() if line.strip()] == EXPECTED_LINES
    assert read_nonempty_lines(OUTPUT) == [line.strip() for line in fixed_run.stdout.splitlines() if line.strip()], \
        "output.txt is not the output produced by the compiled program for logs.txt"

    # Build a separate driver directly against parser.cpp and evaluator.cpp so the
    # required functions themselves, rather than hardcoded output in main, are exercised.
    harness_source = r'''#include <iostream>
#include <string>
#include <vector>
struct LogEntry {
    std::string endpoint;
    std::vector<std::string> tokens;
};
LogEntry parse_line(const std::string& line);
double evaluate_postfix(const std::vector<std::string>& tokens);
int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        LogEntry entry = parse_line(line);
        if (!entry.endpoint.empty())
            std::cout << entry.endpoint << " " << evaluate_postfix(entry.tokens) << "\n";
    }
}
'''
    harness_cpp = "/tmp/proxy_analyzer_harness.cpp"
    harness_bin = "/tmp/proxy_analyzer_harness"
    with open(harness_cpp, "w") as f:
        f.write(harness_source)

    compile_harness = subprocess.run([
        "g++", "-std=c++17", "-Wall", "-Wextra",
        harness_cpp,
        os.path.join(PROJECT, "parser.cpp"),
        os.path.join(PROJECT, "evaluator.cpp"),
        "-o", harness_bin,
    ], timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert compile_harness.returncode == 0, \
        f"parser/evaluator harness failed to compile:\n{compile_harness.stderr}"

    cases = make_random_cases()
    input_text = "\n".join(case[0] for case in cases) + "\n"
    expected = [(case[1], case[2]) for case in cases]

    harness_run = subprocess.run([harness_bin], input=input_text, timeout=10,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert harness_run.returncode == 0, f"parser/evaluator harness failed: {harness_run.stderr}"
    parse_program_output(harness_run.stdout, expected)

    with tempfile.NamedTemporaryFile("w", delete=False) as log_file:
        log_file.write(input_text)
        random_log_path = log_file.name
    try:
        binary_run = subprocess.run([BINARY, random_log_path], cwd=PROJECT, timeout=10,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert binary_run.returncode == 0, f"proxy_analyzer failed on generated input: {binary_run.stderr}"
        parse_program_output(binary_run.stdout, expected)
    finally:
        os.unlink(random_log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
