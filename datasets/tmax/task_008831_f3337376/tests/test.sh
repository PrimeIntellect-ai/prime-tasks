#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import secrets
import subprocess
import pytest

CPP_FILE = "/home/user/kepler_solver.cpp"
EXE_FILE = "/home/user/kepler_solver"
INPUT_FILE = "/home/user/inputs.csv"
OUTPUT_FILE = "/home/user/ml_dataset.csv"


def solve_reference(e, M):
    E = M
    iters = 0
    while True:
        f_val = E - e * math.sin(E) - M
        if abs(f_val) < 1e-8:
            return E, iters
        f_prime = 1.0 - e * math.cos(E)
        E = E - f_val / f_prime
        iters += 1
        if iters > 50:
            pytest.fail(f"Reference case did not converge: e={e}, M={M}")


def test_source_and_executable_exist():
    """Verify that the source code and compiled executable exist."""
    assert os.path.isfile(CPP_FILE), f"Source file {CPP_FILE} is missing."
    assert os.path.isfile(EXE_FILE), f"Executable file {EXE_FILE} is missing."
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."


def test_analytical_validation_mode():
    """Verify that the executable supports --test mode and passes."""
    try:
        result = subprocess.run(
            [EXE_FILE, "--test"],
            capture_output=True,
            text=True,
            check=True
        )
        assert "Tests passed" in result.stdout, "The output of --test did not contain 'Tests passed'."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"The --test command failed with exit code {e.returncode}. Output: {e.stdout} {e.stderr}")


def test_ml_dataset_output():
    """Verify that the generated dataset matches the expected Newton-Raphson results."""
    assert os.path.isfile(OUTPUT_FILE), f"Output dataset {OUTPUT_FILE} is missing."

    expected = {}
    with open(INPUT_FILE, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            e = float(row['e'])
            M = float(row['M'])

            # Newton Raphson in Python
            E = M
            iters = 0
            while True:
                f_val = E - e * math.sin(E) - M
                if abs(f_val) < 1e-8:
                    break
                f_prime = 1.0 - e * math.cos(E)
                E = E - f_val / f_prime
                iters += 1
                if iters > 50:
                    break
            expected[row['id']] = (E, iters)

    agent_results = {}
    with open(OUTPUT_FILE, 'r') as f:
        reader = csv.DictReader(f)
        assert 'id' in reader.fieldnames and 'E' in reader.fieldnames and 'iterations' in reader.fieldnames, \
            "Output CSV is missing required headers (id, E, iterations)."
        for row in reader:
            agent_results[row['id']] = (float(row['E']), int(row['iterations']))

    assert len(agent_results) == len(expected), "Output dataset row count does not match input dataset."

    for idx, (expected_E, expected_iters) in expected.items():
        assert idx in agent_results, f"ID {idx} missing in output dataset."
        agent_E, agent_iters = agent_results[idx]

        assert abs(agent_E - expected_E) < 1e-7, f"Mismatch in E for id {idx}. Expected {expected_E}, got {agent_E}."
        assert agent_iters == expected_iters, f"Mismatch in iterations for id {idx}. Expected {expected_iters}, got {agent_iters}."


def test_run_mode_on_additional_inputs(tmp_path):
    """Execute --run on fresh inputs and verify computed values and convergence counts."""
    rng = secrets.SystemRandom()
    cases = [
        (f"zero-{secrets.token_hex(4)}", 0.0, rng.uniform(0.0, 2.0 * math.pi)),
        (f"origin-{secrets.token_hex(4)}", rng.uniform(0.05, 0.9), 0.0),
        (f"low-{secrets.token_hex(4)}", rng.uniform(0.01, 0.25), rng.uniform(0.1, 6.1)),
        (f"mid-{secrets.token_hex(4)}", rng.uniform(0.3, 0.65), rng.uniform(0.2, 6.0)),
        (f"high-{secrets.token_hex(4)}", rng.uniform(0.75, 0.95), rng.uniform(0.8, 5.4)),
    ]
    for _ in range(5):
        cases.append((
            f"random-{secrets.token_hex(4)}",
            rng.uniform(0.0, 0.85),
            rng.uniform(0.0, 2.0 * math.pi),
        ))

    dynamic_input = tmp_path / "additional_inputs.csv"
    dynamic_output = tmp_path / "additional_output.csv"
    with dynamic_input.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "e", "M"])
        for row in cases:
            writer.writerow(row)

    try:
        result = subprocess.run(
            [EXE_FILE, "--run", str(dynamic_input), str(dynamic_output)],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"The --run command failed with exit code {e.returncode}. Output: {e.stdout} {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("The --run command did not finish within 15 seconds.")

    assert dynamic_output.is_file(), "--run did not create the requested output file."

    with dynamic_output.open(newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "e", "M", "E", "iterations"], \
            f"Incorrect output header: {reader.fieldnames}"
        rows = list(reader)

    assert len(rows) == len(cases), "Additional-input output row count is incorrect."
    by_id = {row["id"]: row for row in rows}
    assert len(by_id) == len(cases), "Output contains duplicate or missing IDs."

    for idx, e, M in cases:
        assert idx in by_id, f"ID {idx} missing from additional-input output."
        row = by_id[idx]
        try:
            output_e = float(row["e"])
            output_M = float(row["M"])
            output_E = float(row["E"])
            output_iters = int(row["iterations"])
        except (TypeError, ValueError) as exc:
            pytest.fail(f"Invalid numeric output for ID {idx}: {exc}")

        assert math.isfinite(output_E), f"Non-finite E for ID {idx}."
        assert abs(output_e - e) < 1e-5, f"Eccentricity was not preserved for ID {idx}."
        assert abs(output_M - M) < 1e-5, f"Mean anomaly was not preserved for ID {idx}."

        expected_E, expected_iters = solve_reference(e, M)
        assert abs(output_E - expected_E) < 1e-7, \
            f"Mismatch in E for additional ID {idx}. Expected {expected_E}, got {output_E}."
        assert output_iters == expected_iters, \
            f"Mismatch in iterations for additional ID {idx}. Expected {expected_iters}, got {output_iters}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
