#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

EXECUTABLE = "/home/user/sensor_stats"
SOURCE = "/home/user/sensor_stats.c"
DATA = "/home/user/data.txt"
OUTPUT = "/home/user/output.log"


def run_program(path):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{path} did not create {OUTPUT}."
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def expected_output(values):
    total = 0.0
    total_sq = 0.0
    for value in values:
        total += value
        total_sq += value * value
    mean = total / len(values)
    variance = (total_sq / len(values)) - (mean * mean)
    stddev = math.sqrt(variance)
    return f"Mean: {mean:.6f}\nVariance: {variance:.6f}\nStdDev: {stddev:.6f}"


def test_executable_exists():
    executable_path = EXECUTABLE
    assert os.path.isfile(executable_path), f"Executable not found at {executable_path}. Did you compile the C program?"
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."
    assert os.stat(executable_path).st_mtime_ns >= os.stat(SOURCE).st_mtime_ns, \
        "The executable is older than the modified source; recompile the modified source."

    # Remove any prewritten answer and require the submitted executable to produce it.
    run_program(executable_path)


def test_output_log_correct():
    output_path = OUTPUT
    assert os.path.isfile(output_path), f"Output file not found at {output_path}. Did you run the compiled program?"

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_mean = "10000.300000"
    expected_variance = "0.020000"
    expected_stddev = "0.141421"

    assert f"Mean: {expected_mean}" in content, f"Expected Mean to be {expected_mean}, but got:\n{content}"
    assert f"Variance: {expected_variance}" in content, f"Expected Variance to be {expected_variance}, but got:\n{content}"
    assert f"StdDev: {expected_stddev}" in content, f"Expected StdDev to be {expected_stddev}, but got:\n{content}"
    assert content == f"Mean: {expected_mean}\nVariance: {expected_variance}\nStdDev: {expected_stddev}", \
        f"Output format is incorrect:\n{content}"


def test_source_code_modifications():
    source_path = SOURCE
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."

    with open(source_path, "r") as f:
        content = f.read()

    # Check that double is used instead of float
    assert "double" in content, "The source code does not seem to use 'double' precision types."


def test_source_and_executable_on_unseen_inputs():
    rebuilt = "/tmp/sensor_stats_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O0", SOURCE, "-lm", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        "The modified source does not compile successfully.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        datasets = []
        for _ in range(3):
            count = 6 + secrets.randbelow(5)
            base = 10000 + secrets.randbelow(70000)
            offsets = [secrets.randbelow(401) - 200 for _ in range(count)]
            if len(set(offsets)) == 1:
                offsets[-1] += 1
            datasets.append([base + offset / 100.0 for offset in offsets])

        for values in datasets:
            with open(DATA, "w") as f:
                for value in values:
                    f.write(f"{value:.2f}\n")

            expected = expected_output(values)
            submitted_output = run_program(EXECUTABLE)
            assert submitted_output == expected, (
                "The submitted executable produced incorrect results for an unseen dataset.\n"
                f"Expected:\n{expected}\nGot:\n{submitted_output}"
            )

            rebuilt_output = run_program(rebuilt)
            assert rebuilt_output == expected, (
                "The executable rebuilt from the modified source produced incorrect results.\n"
                f"Expected:\n{expected}\nGot:\n{rebuilt_output}"
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        try:
            run_program(EXECUTABLE)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
