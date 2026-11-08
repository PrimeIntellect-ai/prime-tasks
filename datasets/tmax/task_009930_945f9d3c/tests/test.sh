#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import pytest

BASE_DIR = "/home/user/mc_pricer"
EXECUTABLE = os.path.join(BASE_DIR, "mc_pricer")
DATA_PATH = os.path.join(BASE_DIR, "data.csv")
RESULT_PATH = "/home/user/result.txt"


def expected_stddev(data):
    mean = math.fsum(data) / len(data)
    variance = math.fsum((x - mean) ** 2 for x in data) / len(data)
    return math.sqrt(variance)


def run_pricer(timeout=5):
    try:
        result = subprocess.run(
            [EXECUTABLE], cwd=BASE_DIR, capture_output=True, text=True,
            timeout=timeout
        )
    except subprocess.TimeoutExpired:
        pytest.fail("mc_pricer execution timed out.")

    assert result.returncode == 0, (
        "mc_pricer crashed or returned non-zero exit code.\n"
        f"Stderr: {result.stderr}"
    )
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"mc_pricer output is not a valid single float. Output: '{output}'")
    assert math.isfinite(value), f"mc_pricer produced a non-finite value: {output}"
    return output, value


def test_makefile_fixed():
    makefile_path = os.path.join(BASE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-g" in content, "Makefile does not contain the '-g' flag for debug symbols."
    assert "-pthread" in content or "-lpthread" in content or "pthread" in content, \
        "Makefile does not link the threading library correctly (missing -pthread)."


def test_diagnosis_report():
    diagnosis_path = "/home/user/diagnosis.txt"
    assert os.path.isfile(diagnosis_path), f"Diagnosis report not found at {diagnosis_path}"

    with open(diagnosis_path, "r") as f:
        content = f.read()

    buggy_file_match = re.search(r"BUGGY_FILE:\s*(.*)", content)
    buggy_line_match = re.search(r"BUGGY_LINE:\s*(.*)", content)
    nan_variable_match = re.search(r"NaN_VARIABLE:\s*(.*)", content)

    assert buggy_file_match is not None, "BUGGY_FILE line is missing or malformed in diagnosis.txt"
    assert buggy_line_match is not None, "BUGGY_LINE line is missing or malformed in diagnosis.txt"
    assert nan_variable_match is not None, "NaN_VARIABLE line is missing or malformed in diagnosis.txt"

    buggy_file = buggy_file_match.group(1).strip()
    buggy_line = buggy_line_match.group(1).strip()
    nan_variable = nan_variable_match.group(1).strip()

    assert buggy_file == "pricer.cpp", f"Expected BUGGY_FILE to be 'pricer.cpp', got '{buggy_file}'"
    assert buggy_line == "21", f"Expected BUGGY_LINE to be '21', got '{buggy_line}'"
    assert nan_variable in ["out_stddev", "stddev", "var"], \
        f"Expected NaN_VARIABLE to be 'out_stddev' (or related), got '{nan_variable}'"


def test_result_txt():
    assert os.path.isfile(RESULT_PATH), f"Result file not found at {RESULT_PATH}"

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    try:
        actual_stddev = float(content)
    except ValueError:
        pytest.fail(f"result.txt does not contain a valid floating-point number. Content: '{content}'")

    assert os.path.isfile(DATA_PATH), f"Data file missing at {DATA_PATH}"
    data = []
    with open(DATA_PATH, "r") as f:
        for line in f:
            val = line.strip()
            if val:
                data.append(float(val))

    assert len(data) > 0, "data.csv is empty."
    mean = sum(data) / len(data)
    variance = sum((x - mean) ** 2 for x in data) / len(data)
    expected = math.sqrt(variance)
    assert math.isclose(actual_stddev, expected, rel_tol=1e-4), \
        f"Calculated standard deviation {actual_stddev} does not match expected {expected}."


def test_mc_pricer_rebuilds_with_debug_symbols_and_matches_result():
    assert os.path.isfile(os.path.join(BASE_DIR, "pricer.cpp")), "pricer.cpp is missing."

    subprocess.run(["make", "-C", BASE_DIR, "clean"], capture_output=True, text=True)
    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)

    build = subprocess.run(["make", "-C", BASE_DIR], capture_output=True, text=True, timeout=30)
    assert build.returncode == 0, f"Project failed to build.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    assert os.path.isfile(EXECUTABLE), "mc_pricer executable not produced by make."
    assert os.access(EXECUTABLE, os.X_OK), "mc_pricer is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mc_pricer is not a compiled ELF executable."

    sections = subprocess.run(["readelf", "-S", EXECUTABLE], capture_output=True, text=True)
    assert sections.returncode == 0 and ".debug_info" in sections.stdout, \
        "Built mc_pricer does not contain debug information; ensure -g is used for compilation."

    output, actual = run_pricer()
    assert actual > 0, "Standard deviation should be positive."

    with open(RESULT_PATH, "r") as f:
        saved_output = f.read().strip()
    assert output == saved_output, \
        f"result.txt must contain the exact output of mc_pricer (binary: '{output}', file: '{saved_output}')."

    with open(DATA_PATH, "r") as f:
        data = [float(line.strip()) for line in f if line.strip()]
    expected = expected_stddev(data)
    assert math.isclose(actual, expected, rel_tol=1e-4), \
        f"mc_pricer output {actual} does not match expected {expected}."


def test_stable_variance_on_adversarial_inputs():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    rng = random.SystemRandom()
    cases = []
    for base, scale, count in [
        (10_000_000_000.0, 0.02, 193),
        (100_000_000_000.0, 3.0, 211),
        (1_000_000_000_000.0, 250.0, 227),
    ]:
        values = [base + rng.uniform(-scale, scale) for _ in range(count)]
        values.extend([base - scale, base + scale])
        cases.append(values)

    try:
        observed = []
        for values in cases:
            rendered = [format(value, ".17g") for value in values]
            parsed = [float(value) for value in rendered]
            with open(DATA_PATH, "w") as f:
                f.write("\n".join(rendered) + "\n")

            _, actual = run_pricer()
            expected = expected_stddev(parsed)
            assert expected > 0
            assert math.isclose(actual, expected, rel_tol=5e-3, abs_tol=1e-12), \
                f"Unstable or incorrect variance result: got {actual}, expected {expected}."
            observed.append(actual)

        assert len({round(value, 8) for value in observed}) == len(observed), \
            "mc_pricer returned effectively constant output for distinct datasets."
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
