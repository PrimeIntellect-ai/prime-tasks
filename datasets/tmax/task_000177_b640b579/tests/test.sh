#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import statistics
import subprocess
import tempfile

import pytest

SIM_DIR = "/home/user/sim_env"
SIM_PATH = os.path.join(SIM_DIR, "sim.py")
INPUTS_PATH = os.path.join(SIM_DIR, "inputs.csv")
MINIMAL_PATH = os.path.join(SIM_DIR, "minimal_crash.csv")
SUCCESS_PATH = os.path.join(SIM_DIR, "success.txt")


def load_sim():
    spec = importlib.util.spec_from_file_location("submitted_sim", SIM_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_sim(path):
    return subprocess.run(
        ["python3", SIM_PATH, path],
        capture_output=True,
        text=True,
        timeout=5,
    )


def parse_single_float(result):
    assert result.returncode == 0, (
        f"sim.py failed. Return code: {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    output = result.stdout.strip()
    try:
        return float(output)
    except ValueError:
        pytest.fail(f"Output of sim.py is not a valid single float: {output}")


def test_minimal_crash_csv():
    assert os.path.isfile(MINIMAL_PATH), (
        f"File {MINIMAL_PATH} is missing. You must save the minimal crashing lines here."
    )

    with open(MINIMAL_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, (
        f"minimal_crash.csv should contain exactly 2 lines, found {len(lines)}."
    )

    val1 = float(lines[0])
    val2 = float(lines[1])
    assert math.isclose(val1, 10000000.0000001), (
        f"First value in minimal_crash.csv is incorrect: {val1}"
    )
    assert math.isclose(val2, 10000000.0000002), (
        f"Second value in minimal_crash.csv is incorrect: {val2}"
    )

    with open(MINIMAL_PATH, "rb") as f:
        raw = f.read()
    assert raw == b"10000000.0000001\n10000000.0000002\n", (
        "minimal_crash.csv must contain the two original contiguous input lines exactly."
    )

    source_lines = open(INPUTS_PATH, "rb").readlines()
    minimal_lines = raw.splitlines(keepends=True)
    assert any(source_lines[i:i + 2] == minimal_lines for i in range(len(source_lines) - 1)), (
        "minimal_crash.csv is not an exact contiguous subset of inputs.csv."
    )

    values = [float(x) for x in raw.splitlines()]
    n = len(values)
    unstable_var = (sum(x ** 2 for x in values) - sum(values) ** 2 / n) / (n - 1)
    with pytest.raises(ValueError):
        math.sqrt(unstable_var)


def test_delta_debugging_script_exists_and_is_substantive():
    candidates = []
    for name in os.listdir(SIM_DIR):
        path = os.path.join(SIM_DIR, name)
        if not os.path.isfile(path) or path == SIM_PATH:
            continue
        if not (name.endswith(".py") or name.endswith(".sh")):
            continue
        try:
            text = open(path, "r", errors="replace").read()
        except OSError:
            continue
        lower = text.lower()
        if "minimal_crash.csv" in lower and "inputs.csv" in lower:
            candidates.append((path, text))

    assert candidates, (
        "No delta-debugging script was found. Save a Python or shell script that reads "
        "inputs.csv and writes minimal_crash.csv."
    )

    substantive = []
    for path, text in candidates:
        lower = text.lower()
        has_failure_oracle = "valueerror" in lower
        has_iteration = any(token in lower for token in ("for ", "while ", "ddmin", "delta"))
        has_subset_logic = any(token in lower for token in ("[", "slice", "chunk", "subset", "remove"))
        has_execution_or_math = any(token in lower for token in (
            "subprocess", "sqrt", "sum(", "variance", "calculate_std_dev"
        ))
        if len(text) >= 150 and has_failure_oracle and has_iteration and has_subset_logic and has_execution_or_math:
            substantive.append(path)

    assert substantive, (
        "The delta-debugging script must implement iterative subset reduction and test "
        "specifically for the numerical ValueError; a hardcoded file writer is insufficient."
    )


def test_success_txt():
    assert os.path.isfile(SUCCESS_PATH), (
        f"File {SUCCESS_PATH} is missing. You must save the final output here."
    )

    initial_data = [
        10.1, 10.2, 10.3, 10.15, 10.25,
        10000000.0000001, 10000000.0000002,
        10.4, 10.5, 10.6,
    ]
    expected_std_dev = statistics.stdev(initial_data)

    with open(SUCCESS_PATH, "r") as f:
        content = f.read().strip()
    assert content, "success.txt is empty."
    try:
        actual_std_dev = float(content)
    except ValueError:
        pytest.fail(f"success.txt does not contain a valid float: {content}")

    assert math.isclose(actual_std_dev, expected_std_dev, rel_tol=1e-5), (
        f"Standard deviation in success.txt is incorrect. "
        f"Expected ~{expected_std_dev}, got {actual_std_dev}"
    )


def test_sim_py_fixes():
    assert os.path.isfile(SIM_PATH), f"File {SIM_PATH} is missing."
    result = run_sim(INPUTS_PATH)
    actual_std_dev = parse_single_float(result)

    initial_data = [
        10.1, 10.2, 10.3, 10.15, 10.25,
        10000000.0000001, 10000000.0000002,
        10.4, 10.5, 10.6,
    ]
    expected_std_dev = statistics.stdev(initial_data)
    assert math.isclose(actual_std_dev, expected_std_dev, rel_tol=1e-5), (
        f"Output of sim.py is incorrect. Expected ~{expected_std_dev}, got {actual_std_dev}"
    )


def test_time_stepping_boundary_and_physics():
    sim = load_sim()
    assert hasattr(sim, "simulate_steps"), "sim.py must retain simulate_steps."

    # At or beyond max_t, no further physics step is allowed.
    assert sim.simulate_steps(7.25, 1.0, 1.0, 0.1) == 7.25
    assert sim.simulate_steps(7.25, 1.1, 1.0, 0.1) == 7.25

    # One remaining step changes position by exactly 1.5 * dt.
    one_step = sim.simulate_steps(7.25, 0.9, 1.0, 0.1)
    assert math.isclose(one_step, 7.4, rel_tol=0.0, abs_tol=1e-12)

    # The production interval is ten 0.1 steps, not the old extra step.
    full = sim.simulate_steps(2.0, 0.0, 1.0, 0.1)
    assert math.isclose(full, 3.5, rel_tol=0.0, abs_tol=1e-12)

    quarter_steps = sim.simulate_steps(-3.0, 0.0, 1.0, 0.25)
    assert math.isclose(quarter_steps, -1.5, rel_tol=0.0, abs_tol=1e-12)


def test_stable_variance_function_on_derived_inputs():
    sim = load_sim()
    assert hasattr(sim, "calculate_std_dev"), "sim.py must retain calculate_std_dev."

    rng = random.Random(847193)
    for base in (1.0e9, 1.0e12, -1.0e12):
        values = [base + rng.randint(-30, 30) / 1000.0 for _ in range(17)]
        expected = statistics.stdev(values)
        actual = sim.calculate_std_dev(values)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12), (
            f"Numerically unstable standard deviation for values near {base}: "
            f"expected {expected}, got {actual}"
        )


def test_sim_cli_on_multiple_derived_datasets():
    rng = random.Random(310927)
    datasets = [
        [rng.uniform(-5000.0, 5000.0) for _ in range(13)],
        [1.0e9 + rng.randint(-100, 100) / 1000.0 for _ in range(19)],
        [-2.0e11 + rng.randint(-80, 80) / 100.0 for _ in range(11)],
    ]

    for values in datasets:
        with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
            for value in values:
                f.write(repr(value) + "\n")
            path = f.name
        try:
            actual = parse_single_float(run_sim(path))
        finally:
            os.unlink(path)

        final_positions = [value + 1.5 for value in values]
        expected = statistics.stdev(final_positions)
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (
            f"sim.py produced {actual}; expected {expected} for a derived input dataset."
        )


def test_success_matches_current_complete_run():
    actual_run = parse_single_float(run_sim(INPUTS_PATH))
    saved = float(open(SUCCESS_PATH, "r").read().strip())
    assert math.isclose(saved, actual_run, rel_tol=1e-12, abs_tol=1e-12), (
        "success.txt is not the output of the fully fixed sim.py on inputs.csv."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
