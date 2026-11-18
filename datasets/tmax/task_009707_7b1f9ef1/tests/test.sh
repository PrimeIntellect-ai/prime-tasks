#!/bin/bash
set +e
mkdir -p /logs/verifier

# Force the submitted convergence script to recreate both required artifacts.
rm -f /home/user/heat_ode /home/user/convergence.txt
RUN_STATUS=1
if timeout 60s bash -c 'cd /home/user && ./run_convergence.sh'; then
    RUN_STATUS=0
fi
export RUN_STATUS

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

HOME = "/home/user"
EXE = os.path.join(HOME, "heat_ode")


def run_solver(dt, threads=2):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    proc = subprocess.run(
        [EXE, format(dt, ".17g")],
        cwd=HOME,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, proc.stderr
    output = proc.stdout.strip()
    assert "\n" not in output and "\r" not in output, \
        f"Solver must print exactly one line, got: {proc.stdout!r}"
    match = re.fullmatch(
        r"dt=([+-]?(?:\d+(?:\.\d*)?|\.\d+)), T0=([+-]?(?:\d+(?:\.\d*)?|\.\d+))",
        output,
    )
    assert match, f"Unexpected solver output: {output!r}"
    return output, float(match.group(1)), float(match.group(2))


def reference_t0(dt, steps):
    current = [0.0] * 1000
    current[0] = 1000.0
    for _ in range(steps):
        nxt = [0.0] * 1000
        for i in range(1000):
            nxt[i] = current[i] + dt * (
                current[(i - 1) % 1000] - 2.0 * current[i]
                + current[(i + 1) % 1000]
            )
        current = nxt
    return current[0]


def test_convergence_script_executed_successfully():
    assert os.environ.get("RUN_STATUS") == "0", \
        "run_convergence.sh did not execute successfully"


def test_files_exist():
    expected_files = [
        "/home/user/heat_ode.c",
        "/home/user/run_convergence.sh",
        "/home/user/heat_ode",
        "/home/user/convergence.txt"
    ]
    for f in expected_files:
        assert os.path.exists(f), f"Expected file {f} is missing."

    assert os.path.isfile(EXE), "heat_ode must be a regular file"
    assert os.access(EXE, os.X_OK), "heat_ode must be executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "heat_ode must be a compiled ELF executable"


def test_openmp_usage():
    with open("/home/user/heat_ode.c", "r") as f:
        source = f.read()
    assert "omp" in source.lower(), "The C source code does not appear to use OpenMP directives."
    assert re.search(r"#\s*pragma\s+omp\s+parallel\s+for\b", source, re.IGNORECASE), \
        "The spatial update loop must use an OpenMP parallel-for directive."


def test_compilation_script():
    with open("/home/user/run_convergence.sh", "r") as f:
        script = f.read()
    assert "gcc" in script and "fopenmp" in script, "The bash script must compile the code using gcc with OpenMP enabled (-fopenmp)."
    assert os.access("/home/user/run_convergence.sh", os.X_OK), "The bash script must have executable permissions."


def test_cli_arity():
    for args in ([], ["0.01", "extra"]):
        proc = subprocess.run(
            [EXE] + args,
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode != 0, "heat_ode must require exactly one command-line argument"


def test_solver_against_derived_reference_inputs():
    # Fresh unpredictable step counts prevent passing by hardcoding the three
    # convergence-study outputs. dt=1/k makes the endpoint exactly one in the
    # mathematical time grid, requiring k Forward Euler updates.
    counts = set()
    while len(counts) < 3:
        counts.add(200 + secrets.randbelow(401))

    for steps in counts:
        dt = 1.0 / steps
        expected = reference_t0(dt, steps)
        _, printed_dt, actual_parallel = run_solver(dt, threads=4)
        _, _, actual_serial = run_solver(dt, threads=1)
        assert math.isclose(printed_dt, dt, rel_tol=0.0, abs_tol=5.1e-7), \
            f"Printed dt {printed_dt} does not match input {dt}"
        assert math.isclose(actual_parallel, expected, rel_tol=0.0, abs_tol=2e-4), \
            f"Incorrect diffusion result for dt={dt}: expected {expected}, got {actual_parallel}"
        assert math.isclose(actual_serial, expected, rel_tol=0.0, abs_tol=2e-4), \
            f"Incorrect one-thread result for dt={dt}: expected {expected}, got {actual_serial}"


def test_convergence_file_was_produced_by_solver_behavior():
    with open("/home/user/convergence.txt", "r") as f:
        recorded = [line.strip() for line in f if line.strip()]
    assert len(recorded) == 3
    for line, dt in zip(recorded, (0.1, 0.01, 0.001)):
        direct, _, _ = run_solver(dt, threads=2)
        assert line == direct, \
            f"convergence.txt entry for dt={dt} does not match heat_ode output"


def test_convergence_output():
    with open("/home/user/convergence.txt", "r") as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]

    assert len(lines) == 3, f"Expected 3 lines of output in convergence.txt, found {len(lines)}."

    # Check dt=0.1
    assert "0.1" in lines[0], f"First line should contain dt=0.1, got: {lines[0]}"
    t0_1_match = re.search(r"T0=([0-9.]+)", lines[0])
    assert t0_1_match, f"Could not parse T0 from first line: {lines[0]}"
    t0_1 = float(t0_1_match.group(1))
    assert 296.0 < t0_1 < 298.0, f"Expected T0 for dt=0.1 to be ~296.87, got {t0_1}"

    # Check dt=0.01
    assert "0.01" in lines[1], f"Second line should contain dt=0.01, got: {lines[1]}"
    t0_2_match = re.search(r"T0=([0-9.]+)", lines[1])
    assert t0_2_match, f"Could not parse T0 from second line: {lines[1]}"
    t0_2 = float(t0_2_match.group(1))
    assert 305.0 < t0_2 < 307.0, f"Expected T0 for dt=0.01 to be ~305.82, got {t0_2}"

    # Check dt=0.001
    assert "0.001" in lines[2], f"Third line should contain dt=0.001, got: {lines[2]}"
    t0_3_match = re.search(r"T0=([0-9.]+)", lines[2])
    assert t0_3_match, f"Could not parse T0 from third line: {lines[2]}"
    t0_3 = float(t0_3_match.group(1))
    assert 306.0 < t0_3 < 308.0, f"Expected T0 for dt=0.001 to be ~306.74, got {t0_3}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
