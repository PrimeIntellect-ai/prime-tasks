#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets
import pytest


def test_c_source_exists():
    """Test that the C source file exists."""
    assert os.path.exists("/home/user/analyze.c"), "The source file /home/user/analyze.c does not exist."
    assert os.path.isfile("/home/user/analyze.c"), "/home/user/analyze.c is not a regular file."


def test_executable_exists_and_executable():
    """Test that the compiled executable exists and is executable."""
    exe_path = "/home/user/analyze"
    assert os.path.exists(exe_path), f"The executable {exe_path} does not exist."
    assert os.path.isfile(exe_path), f"{exe_path} is not a regular file."

    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled native executable."


def test_anomalies_output():
    """Test that the anomalies.txt file contains the correct output."""
    output_path = "/home/user/anomalies.txt"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist. Did you run the program and redirect output?"

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected_output = "Anomaly: 50\nAnomaly: 100"

    # Normalize line endings and whitespace
    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]
    expected_lines = [line.strip() for line in expected_output.split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"The contents of {output_path} do not match the expected anomalies. Found: {actual_lines}"


def oracle(values):
    seen = set()
    window = []
    anomalies = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        if len(window) == 4:
            if value > (sum(window) / 4.0 + 10.0):
                anomalies.append(value)
            window.pop(0)
        window.append(value)
    return ''.join(f"Anomaly: {value}\n" for value in anomalies)


def run_case(executable, values):
    input_data = ''.join(f"{value}\n" for value in values)
    result = subprocess.run(
        [executable],
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}; stderr: {result.stderr!r}"
    )
    expected = oracle(values)
    assert result.stdout == expected, (
        f"Incorrect output for input {values!r}. Expected {expected!r}, got {result.stdout!r}."
    )


@pytest.fixture(scope="module")
def rebuilt_executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "analyze"
    result = subprocess.run(
        ["gcc", "/home/user/analyze.c", "-o", str(output)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"analyze.c does not compile with gcc: {result.stderr}"
    return str(output)


def test_program_behavior(rebuilt_executable):
    rng = secrets.SystemRandom()
    base = rng.randint(-500, 500)

    cases = [
        [10, 12, 11, 10, 13, 15],
        [base - 3, base - 1, base + 1, base + 3, base + 10],
        [base - 4, base - 2, base + 2, base + 4, base + 35,
         base + 6, base + 8, base - 4, base + 60, base + 35],
    ]

    # Runtime-generated cases exercise duplicates both inside and outside the
    # rolling window, negative values, window replacement, and anomalies.
    for _ in range(8):
        values = []
        unique_values = []
        used = set()
        for _ in range(70):
            if unique_values and rng.randrange(100) < 38:
                values.append(rng.choice(unique_values))
            else:
                value = rng.randint(-1000, 1000)
                while value in used:
                    value = rng.randint(-1000, 1000)
                used.add(value)
                unique_values.append(value)
                values.append(value)
        cases.append(values)

    for executable in ("/home/user/analyze", rebuilt_executable):
        for values in cases:
            run_case(executable, values)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
