#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

PROJECT = "/home/user/trajectory"
EXECUTABLE = os.path.join(PROJECT, "traj_calc")


def stable_expected(a, b, c):
    disc = b * b - 4.0 * a * c
    if disc < 0.0:
        return -1.0
    root_disc = math.sqrt(disc)
    q = -0.5 * (b + math.copysign(root_disc, b))
    roots = []
    if a != 0.0:
        t1 = q / a
        if math.isfinite(t1) and t1 > 0.0:
            roots.append(t1)
    if q != 0.0:
        t2 = c / q
        if math.isfinite(t2) and t2 > 0.0:
            roots.append(t2)
    return min(roots) if roots else -1.0


def run_calculator(a, b, c):
    result = subprocess.run(
        [EXECUTABLE, repr(a), repr(b), repr(c)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    try:
        return float(result.stdout.strip())
    except ValueError:
        assert False, f"traj_calc did not print one floating-point value: {result.stdout!r}"


def assert_case(a, b, c):
    expected = stable_expected(a, b, c)
    actual = run_calculator(a, b, c)
    assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-300), (
        f"Incorrect result for {a} {b} {c}: expected {expected}, got {actual}"
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did the build script succeed?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_build_script_fixed():
    build_script_path = os.path.join(PROJECT, "build.sh")
    assert os.path.isfile(build_script_path), f"File {build_script_path} is missing."
    with open(build_script_path, "r") as f:
        content = f.read()
    assert "-lm" in content, "The build script does not link the math library (-lm)."

    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)
    result = subprocess.run(
        [build_script_path], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(EXECUTABLE), "build.sh did not produce traj_calc."
    assert os.access(EXECUTABLE, os.X_OK), "The traj_calc produced by build.sh is not executable."


def test_fuzzer_passes():
    fuzzer_path = os.path.join(PROJECT, "fuzzer.sh")
    assert os.path.isfile(fuzzer_path), f"File {fuzzer_path} is missing."

    try:
        result = subprocess.run(
            [fuzzer_path], cwd=PROJECT, capture_output=True, text=True,
            check=True, timeout=30
        )
        assert "FUZZER PASSED" in result.stdout, "Fuzzer script did not print 'FUZZER PASSED'."
    except subprocess.CalledProcessError as e:
        assert False, (
            f"Fuzzer script failed with exit code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )


def test_calculator_independently():
    fixed_cases = [
        (1.0, -5.0, 6.0),
        (0.0001, 1000.0, 0.0001),
        (1e-5, 1e5, 1e-5),
        (0.0001, -1000.0, 0.0001),
        (1e-5, -1e5, 1e-5),
        (1.0, 0.0, -4.0),
        (1.0, 2.0, 1.0),
        (1.0, -2.0, 1.0),
        (1.0, 0.0, 1.0),
    ]
    for case in fixed_cases:
        assert_case(*case)

    rng = secrets.SystemRandom()
    for _ in range(12):
        small = rng.uniform(1.0, 9.0) * 10.0 ** rng.uniform(-12.0, -7.0)
        large = rng.uniform(1.0, 9.0) * 10.0 ** rng.uniform(7.0, 12.0)
        a = 10.0 ** rng.uniform(-4.0, 4.0)

        # Two positive roots; the smaller one is vulnerable to cancellation.
        b = -a * (small + large)
        c = a * small * large
        assert_case(a, b, c)

        # One tiny positive root and one large negative root.
        b = -a * (small - large)
        c = -a * small * large
        assert_case(a, b, c)

        # Both roots negative, so the required result is -1.
        b = a * (small + large)
        c = a * small * large
        assert_case(a, b, c)


def test_final_output_file():
    output_file_path = "/home/user/final_output.txt"
    assert os.path.isfile(output_file_path), f"Final output file {output_file_path} is missing."

    command_output = subprocess.check_output(
        [EXECUTABLE, "0.0001", "1000.0", "0.0001"], cwd=PROJECT, timeout=5
    )
    with open(output_file_path, "rb") as f:
        saved_output = f.read()
    assert saved_output == command_output, (
        "final_output.txt is not the exact console output of the required command: "
        f"expected {command_output!r}, got {saved_output!r}"
    )

    try:
        val = float(saved_output.strip())
    except ValueError:
        assert False, f"Content of {output_file_path} is not a valid floating point number: {saved_output!r}"

    expected_val = stable_expected(0.0001, 1000.0, 0.0001)
    assert math.isclose(val, expected_val, rel_tol=1e-5), (
        f"Expected value close to {expected_val}, but got {val} in {output_file_path}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
