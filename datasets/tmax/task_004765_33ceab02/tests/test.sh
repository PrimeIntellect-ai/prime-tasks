#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/motif_ode.c"
EXECUTABLE = "/home/user/motif_sim"
RESULT = "/home/user/result.txt"


def run_program(path):
    completed = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30, check=True
    )
    output = completed.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), \
        f"{path} did not print exactly one floating-point number: {output!r}"
    return output, float(output)


def compile_source(source_path, output_path):
    subprocess.run(
        ["gcc", "-O2", "-fopenmp", source_path, "-o", output_path, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=30, check=True
    )


def reference_value(num_env):
    final_values = []
    for i in range(num_env):
        r = 1.0 + i * 0.001
        t = 0.0
        p = 0.01
        dt = 0.5
        while t < 10.0:
            if t + dt > 10.0:
                dt = 10.0 - t
            p1 = p + dt * (r * p * (1.0 - p))
            p_half = p + (dt / 2.0) * (r * p * (1.0 - p))
            p2 = p_half + (dt / 2.0) * (r * p_half * (1.0 - p_half))
            err = abs(p1 - p2)
            if err > 1e-4:
                dt *= 0.5
                continue
            p = p2
            t += dt
            dt *= 1.1
        final_values.append(p)
    return sum(final_values) / num_env


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def test_executable_exists_and_runnable():
    executable_path = EXECUTABLE
    assert os.path.exists(executable_path), f"Executable {executable_path} does not exist."
    assert os.path.isfile(executable_path), f"Path {executable_path} is not a file."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."
    run_program(executable_path)


def test_result_file_exists_and_correct():
    result_path = RESULT
    assert os.path.exists(result_path), f"Result file {result_path} does not exist."
    assert os.path.isfile(result_path), f"Path {result_path} is not a file."

    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content, f"Result file {result_path} is empty."
    try:
        result_value = float(content)
    except ValueError:
        pytest.fail(f"Content of {result_path} is not a valid float: {content!r}")

    expected_value = 0.99933
    tolerance = 0.0001
    assert abs(result_value - expected_value) <= tolerance, \
        f"Result value {result_value} is not within {tolerance} of expected {expected_value}."

    executable_output, executable_value = run_program(EXECUTABLE)
    assert executable_output == content, \
        "result.txt is not the standard output produced by motif_sim."
    assert abs(executable_value - reference_value(1000)) <= tolerance


def test_c_code_fixed():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        original_content = f.read()
    content = strip_comments(original_content)

    # Ensure the requested model, constants, initial conditions, and OpenMP loop remain present.
    required = [
        r"#\s*define\s+NUM_ENV\s+1000\b",
        r"#\s*define\s+TOL\s+1e-4\b",
        r"return\s+r\s*\*\s*p\s*\*\s*\(\s*1\.0\s*-\s*p\s*\)\s*;",
        r"r\s*=\s*1\.0\s*\+\s*\(\s*i\s*\*\s*0\.001\s*\)\s*;",
        r"p\s*=\s*0\.01\s*;",
        r"dt\s*=\s*0\.5\s*;",
        r"while\s*\(\s*t\s*<\s*10\.0\s*\)",
        r"#\s*pragma\s+omp\s+parallel\s+for",
    ]
    for pattern in required:
        assert re.search(pattern, content), f"Required model code is missing or altered: {pattern}"

    high_error = re.search(r"if\s*\(\s*err\s*>\s*TOL\s*\)\s*\{([^{}]*)\}", content, re.S)
    assert high_error, "Could not find the high-error adaptation branch."
    branch = high_error.group(1)
    assert not re.search(r"dt\s*\*=\s*2(?:\.0+)?\s*;", branch), \
        "The high-error branch still doubles the step size."

    decreases = False
    multiplier = re.search(r"dt\s*\*=\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s*;", branch)
    if multiplier:
        decreases = 0.0 < float(multiplier.group(1)) < 1.0
    divisor = re.search(r"dt\s*/=\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s*;", branch)
    if divisor:
        decreases = decreases or float(divisor.group(1)) > 1.0
    assigned_mul = re.search(r"dt\s*=\s*dt\s*\*\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s*;", branch)
    if assigned_mul:
        decreases = decreases or 0.0 < float(assigned_mul.group(1)) < 1.0
    assigned_div = re.search(r"dt\s*=\s*dt\s*/\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s*;", branch)
    if assigned_div:
        decreases = decreases or float(assigned_div.group(1)) > 1.0
    assert decreases, "The high-error branch does not decrease dt."

    # Compile the submitted source independently and verify its behavior.
    fresh_binary = "/tmp/motif_sim_fresh"
    compile_source(SOURCE, fresh_binary)
    _, fresh_value = run_program(fresh_binary)
    assert abs(fresh_value - reference_value(1000)) <= 0.0001

    # Exercise the implementation with a verifier-selected environment count so a
    # source file that merely prints the known final answer cannot pass.
    variant_source = re.sub(
        r"(#\s*define\s+NUM_ENV\s+)1000\b", r"\g<1>37", original_content, count=1
    )
    assert variant_source != original_content, "Could not create behavioral test variant."
    variant_path = "/tmp/motif_ode_variant.c"
    variant_binary = "/tmp/motif_sim_variant"
    with open(variant_path, "w") as f:
        f.write(variant_source)
    compile_source(variant_path, variant_binary)
    _, variant_value = run_program(variant_binary)
    assert abs(variant_value - reference_value(37)) <= 0.0001, \
        "Submitted source does not implement the requested simulation."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
