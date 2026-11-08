#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/sim.cpp"
EXE = "/home/user/sim"
LOG = "/home/user/convergence.log"
REQUESTED_DTS = ["0.1", "0.05", "0.025", "0.0125"]
HIDDEN_DTS = ["0.08", "0.03125"]


def oracle(dt_text):
    dt = float(dt_text)
    T = 10.0
    N = int(T / dt)
    P = [0.0] * N
    P[0] = 1.0
    k = 0.5

    for i in range(N - 1):
        t = i * dt
        dP = -k * P[i] + math.sin(2.0 * math.pi * t)
        P[i + 1] = P[i] + dP * dt

    energies = [0.0] * N
    for k_freq in range(N):
        re_part = 0.0
        im_part = 0.0
        for n in range(N):
            angle = 2.0 * math.pi * k_freq * n / N
            re_part += P[n] * math.cos(angle)
            im_part -= P[n] * math.sin(angle)
        energies[k_freq] = re_part * re_part + im_part * im_part

    total_energy = 0.0
    for energy in energies:
        total_energy += energy
    return P[N - 1], total_energy


def run_program(path, dt, threads):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_DYNAMIC"] = "FALSE"
    result = subprocess.run(
        [path, dt], capture_output=True, text=True, check=True,
        timeout=30, env=env
    )
    assert result.stderr == "", f"Unexpected stderr for dt={dt}: {result.stderr!r}"
    output = result.stdout.strip()
    assert "\n" not in output and "\r" not in output, \
        f"Expected exactly one output line for dt={dt}, got {output!r}"
    fields = output.split(",")
    assert len(fields) == 2, f"Expected final_P,total_energy for dt={dt}, got {output!r}"
    try:
        values = tuple(float(field) for field in fields)
    except ValueError as exc:
        raise AssertionError(f"Non-numeric output for dt={dt}: {output!r}") from exc
    assert all(math.isfinite(value) for value in values), \
        f"Non-finite output for dt={dt}: {output!r}"
    return output, values


def assert_matches_oracle(values, dt):
    expected_final, expected_energy = oracle(dt)
    actual_final, actual_energy = values
    assert math.isclose(actual_final, expected_final, rel_tol=1e-10, abs_tol=6e-10), \
        f"Incorrect final_P for dt={dt}: expected {expected_final}, got {actual_final}"
    assert math.isclose(actual_energy, expected_energy, rel_tol=2e-10, abs_tol=5e-7), \
        f"Incorrect total_energy for dt={dt}: expected {expected_energy}, got {actual_energy}"


def test_sim_cpp_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."

    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "#pragma omp atomic" not in content, f"{SOURCE} still contains '#pragma omp atomic'."
    assert "omp parallel" in content, f"{SOURCE} is missing the OpenMP parallel directive."

    # Ensure the parallel directive is active code, rather than text in a comment
    # or an inactive preprocessor branch.
    preprocessed = subprocess.run(
        ["g++", "-fopenmp", "-E", "-P", SOURCE],
        capture_output=True, text=True, check=True, timeout=30
    ).stdout
    assert re.search(r"(?m)^\s*#\s*pragma\s+omp\s+parallel\s+for\b", preprocessed), \
        "No active '#pragma omp parallel for' directive was found."


def test_sim_compiled():
    assert os.path.isfile(EXE), f"Compiled executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."


def test_computation_determinism_and_convergence_log():
    test_exe = "/tmp/sim_test"
    subprocess.run(
        ["g++", "-O3", "-fopenmp", SOURCE, "-o", test_exe],
        check=True, timeout=60
    )

    canonical_outputs = {}
    for dt in REQUESTED_DTS + HIDDEN_DTS:
        observed = []
        for threads in (1, 2, 4):
            for _ in range(2):
                output, values = run_program(test_exe, dt, threads)
                assert_matches_oracle(values, dt)
                observed.append(output)
        assert len(set(observed)) == 1, \
            f"Output is not deterministic across runs/thread counts for dt={dt}: {observed}"
        canonical_outputs[dt] = observed[0]

        installed_output, installed_values = run_program(EXE, dt, 3)
        assert_matches_oracle(installed_values, dt)
        assert installed_output == canonical_outputs[dt], \
            f"{EXE} does not match the program compiled from {SOURCE} for dt={dt}."

    assert os.path.isfile(LOG), f"File {LOG} is missing."
    with open(LOG, "r") as f:
        raw_lines = f.read().splitlines()

    expected_lines = [f"{dt},{canonical_outputs[dt]}" for dt in REQUESTED_DTS]
    assert len(raw_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in {LOG}, found {len(raw_lines)}."
    for i, (expected, actual) in enumerate(zip(expected_lines, raw_lines)):
        assert actual == expected, \
            f"Line {i + 1} in {LOG} is incorrect. Expected {expected!r}, got {actual!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
