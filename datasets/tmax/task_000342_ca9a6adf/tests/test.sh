#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile

FIXED = "/home/user/fixed_service"
SOURCE = "/home/user/fixed_service.cpp"
REBUILT = "/tmp/fixed_service_rebuilt"


def one_line_content(path):
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "rb") as f:
        raw = f.read()
    assert raw, f"File {path} is empty."
    # Permit either no terminator or one Unix/Windows line terminator, but no
    # second line (including a blank second line).
    body = raw
    if body.endswith(b"\r\n"):
        body = body[:-2]
    elif body.endswith(b"\n"):
        body = body[:-1]
    assert body and b"\n" not in body and b"\r" not in body, \
        f"{path} must contain exactly one non-empty line."
    return body.decode("utf-8")


def compile_stod_checker():
    source = r'''
#include <cmath>
#include <fstream>
#include <iostream>
#include <string>
int main(int argc, char **argv) {
    if (argc != 3) return 10;
    std::ifstream in(argv[2]);
    std::string line, extra;
    if (!std::getline(in, line) || std::getline(in, extra)) return 11;
    try {
        std::size_t used = 0;
        double reading = std::stod(line, &used);
        if (used != line.size()) return 12;
        if (std::string(argv[1]) == "corrupt") return 13;
        double normalized = 10.0 / (reading - 1.0);
        return (std::isnan(normalized) || std::isinf(normalized)) ? 0 : 14;
    } catch (...) {
        return std::string(argv[1]) == "corrupt" ? 0 : 15;
    }
}
'''
    src = "/tmp/stod_checker.cpp"
    exe = "/tmp/stod_checker"
    with open(src, "w") as f:
        f.write(source)
    result = subprocess.run(["g++", "-O2", src, "-o", exe], capture_output=True, text=True)
    assert result.returncode == 0, f"Could not build MRE checker:\n{result.stderr}"
    return exe


def ensure_rebuilt():
    if os.path.exists(REBUILT):
        return
    result = subprocess.run(["g++", "-O2", SOURCE, "-o", REBUILT], capture_output=True, text=True)
    assert result.returncode == 0, f"fixed_service.cpp does not compile:\n{result.stderr}"


def run_service(executable, data, timeout=15):
    return subprocess.run(executable, input=data, capture_output=True, text=True, timeout=timeout)


def processed_values(stdout):
    values = []
    for line in stdout.splitlines():
        assert line.startswith("Processed: "), f"Unexpected stdout line: {line!r}"
        text = line[len("Processed: "):].strip()
        try:
            values.append(float(text))
        except ValueError:
            raise AssertionError(f"Invalid numeric output in line: {line!r}")
    return values


def assert_behavior(executable):
    rng = random.SystemRandom()
    expected = []
    lines = []
    for i in range(40):
        target = rng.randint(2, 50000)
        reading = 1.0 + 10.0 / target
        lines.append(repr(reading))
        expected.append(10.0 / (reading - 1.0))
        if i % 4 == 0:
            lines.extend([f"corrupt-{rng.getrandbits(64):016x}", "1.0000000005", "NaN", "Inf"])

    result = run_service(executable, "\n".join(lines) + "\n")
    assert result.returncode == 0, f"Service failed on behavioral input:\n{result.stderr}"
    actual = processed_values(result.stdout)
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} valid output lines, got {len(actual)}: {result.stdout}"
    for got, want in zip(actual, expected):
        assert math.isfinite(got), f"Valid input produced non-finite output: {got}"
        assert math.isclose(got, want, rel_tol=5e-6, abs_tol=1e-6), \
            f"Incorrect normalization: expected approximately {want}, got {got}"

    # Values within 1e-9 of the denominator singularity, plus non-finite
    # readings and corrupt text, must be rejected rather than processed.
    rejected = "1\n1.0000000005\n0.9999999995\nNaN\nInf\n-invalid-\n"
    result = run_service(executable, rejected)
    assert result.returncode == 0, f"Service crashed on anomalous input:\n{result.stderr}"
    assert processed_values(result.stdout) == [], \
        f"Anomalous inputs should not produce normal output: {result.stdout}"

    # Values beyond the requested tolerance remain valid.
    edge_valid = [1.000000002, 0.999999998]
    result = run_service(executable, "\n".join(repr(x) for x in edge_valid) + "\n")
    assert result.returncode == 0
    actual = processed_values(result.stdout)
    assert len(actual) == 2
    expected_edge = [10.0 / (x - 1.0) for x in edge_valid]
    for got, want in zip(actual, expected_edge):
        assert math.isclose(got, want, rel_tol=5e-6), \
            f"Incorrect result outside precision guard: expected {want}, got {got}"


def test_mre_math_exists_and_valid():
    path = "/home/user/mre_math.txt"
    content = one_line_content(path)
    assert content.strip(), f"File {path} is empty."
    checker = compile_stod_checker()
    result = subprocess.run([checker, "math", path])
    assert result.returncode == 0, \
        "mre_math.txt must be one complete numeric value that makes the original normalization NaN or Infinity."


def test_mre_corrupt_exists_and_valid():
    path = "/home/user/mre_corrupt.txt"
    content = one_line_content(path)
    assert content.strip(), f"File {path} is empty."
    checker = compile_stod_checker()
    result = subprocess.run([checker, "corrupt", path])
    assert result.returncode == 0, \
        "mre_corrupt.txt must contain non-numeric text for which std::stod throws."


def test_fixed_service_compiled():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.exists(FIXED), f"{FIXED} does not exist."
    assert os.access(FIXED, os.X_OK), f"{FIXED} is not executable."
    with open(FIXED, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fixed_service must be a compiled executable."
    ensure_rebuilt()


def test_fixed_service_no_leaks():
    ensure_rebuilt()
    with open("/home/user/mre_math.txt") as f:
        math_mre = f.read().strip()
    with open("/home/user/mre_corrupt.txt") as f:
        corrupt_mre = f.read().strip()
    # Retain the original mixed cases and additionally exercise the submitted MREs.
    test_data = f"2.0\ngarbage\n1.0000000000000000001\nNaN\nInf\n3.5\n{math_mre}\n{corrupt_mre}\n"

    for executable in (FIXED, REBUILT):
        cmd = [
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all", "--error-exitcode=1", executable
        ]
        result = subprocess.run(cmd, input=test_data, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, \
            f"Valgrind reported leaks or errors for {executable}.\nStderr:\n{result.stderr}"
        assert "in use at exit: 0 bytes in 0 blocks" in result.stderr, \
            f"Valgrind did not report absolutely zero outstanding bytes for {executable}:\n{result.stderr}"


def test_fixed_service_valid_output():
    result = run_service(FIXED, "2.0\n")
    assert result.returncode == 0, "fixed_service crashed on valid input."
    assert "Processed: 10" in result.stdout, \
        f"Expected 'Processed: 10' in stdout, got: {result.stdout}"


def test_fixed_service_general_behavior():
    ensure_rebuilt()
    assert_behavior(FIXED)
    # Also verify that the submitted source independently builds to the same
    # required behavior, rather than testing only an unrelated executable.
    assert_behavior(REBUILT)


def test_million_line_mixed_stream():
    # Exercise long-running behavior on a genuinely large mixed stream without
    # retaining its potentially large diagnostics in memory.
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        path = tmp.name
        for i in range(1_000_000):
            if i % 10000 == 0:
                tmp.write("2.0\n")
            elif i % 10000 == 1:
                tmp.write("1.0000000005\n")
            else:
                tmp.write("corrupted-sensor-reading\n")
    try:
        with open(path) as stdin_f, open(os.devnull, "w") as devnull:
            result = subprocess.run(
                [FIXED], stdin=stdin_f, stdout=devnull, stderr=devnull, timeout=90
            )
        assert result.returncode == 0, \
            f"fixed_service failed while processing a one-million-line mixed stream (exit {result.returncode})."
    finally:
        os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
