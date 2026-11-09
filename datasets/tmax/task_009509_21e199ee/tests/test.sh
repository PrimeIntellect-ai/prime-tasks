#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import pytest

JOB_DIR = "/home/user/risk_job"
SOURCE = os.path.join(JOB_DIR, "calc_metrics.c")
BINARY = os.path.join(JOB_DIR, "calc_metrics")
SCRIPT = os.path.join(JOB_DIR, "run_job.sh")
SUCCESS_LOG = os.path.join(JOB_DIR, "success.log")
TRACE = "/tmp/risk_job_inputs.log"


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd=JOB_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def assert_elf(path):
    assert os.path.isfile(path), f"Expected compiled helper {path} to exist"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


@pytest.fixture(scope="session", autouse=True)
def execute_and_verify_job():
    assert os.path.isfile(SOURCE), f"Missing C helper source: {SOURCE}"
    assert os.path.isfile(SCRIPT), f"Missing orchestration script: {SCRIPT}"

    with open(SCRIPT, "r") as f:
        script_text = f.read()
    assert re.search(r"(?m)^\s*X\s*=\s*5\.0\s*$", script_text), "Initial X=5.0 was changed"
    assert re.search(r"(?m)^\s*TOL\s*=\s*[\"']?0\.0001[\"']?\s*$", script_text), "Tolerance was changed"
    assert re.search(r"(?m)^\s*MAX_ITER\s*=\s*20\s*$", script_text), "Maximum iteration limit was changed"

    # A stale or fabricated output must not satisfy the verifier.
    for path in (BINARY, SUCCESS_LOG, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Build the submitted helper from scratch and exercise its required formula
    # on verifier-selected inputs.
    run_checked(["make"])
    assert_elf(BINARY)
    seed = int.from_bytes(secrets.token_bytes(4), "big")
    samples = [1.25 + ((seed >> shift) & 255) / 37.0 for shift in (0, 8, 16)]
    for x in samples:
        result = run_checked([BINARY, repr(x)])
        fields = result.stdout.strip().split()
        assert len(fields) == 2, f"Unexpected helper output for x={x}: {result.stdout!r}"
        fx, fdx = map(float, fields)
        assert math.isclose(fx, x**3 - 5*x - 9, rel_tol=0, abs_tol=2e-5)
        assert math.isclose(fdx, 3*x**2 - 5, rel_tol=0, abs_tol=2e-5)

    with open(SOURCE, "rb") as f:
        original_source = f.read()

    # Rebuild with an equivalent instrumented helper so the verifier can prove
    # that run_job.sh actually performs the iterative calculation.
    instrumented = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *trace = fopen("/tmp/risk_job_inputs.log", "a");
    if (trace) { fprintf(trace, "%s\n", argv[1]); fclose(trace); }
    double x = atof(argv[1]);
    double fx = pow(x, 3) - 5 * x - 9;
    double fdx = 3 * pow(x, 2) - 5;
    printf("%f %f\n", fx, fdx);
    return 0;
}
'''
    try:
        with open(SOURCE, "w") as f:
            f.write(instrumented)
        for path in (BINARY, SUCCESS_LOG, TRACE):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        run_checked([SCRIPT])
        assert_elf(BINARY)

        assert os.path.isfile(TRACE), "run_job.sh did not invoke the compiled helper"
        with open(TRACE, "r") as f:
            inputs = [float(line.strip()) for line in f if line.strip()]

        assert 2 <= len(inputs) <= 20, (
            f"Expected 2 to 20 root-finding iterations, observed {len(inputs)}"
        )
        assert math.isclose(inputs[0], 5.0, rel_tol=0, abs_tol=1e-12), (
            f"Iteration did not start at X=5.0: {inputs[0]}"
        )

        # Every observed next input must be the Newton update produced from the
        # previous helper result (which is printed to six decimal places).
        for previous, observed in zip(inputs, inputs[1:]):
            fx = float(f"{previous**3 - 5*previous - 9:.6f}")
            fdx = float(f"{3*previous**2 - 5:.6f}")
            expected = previous - fx / fdx
            assert math.isclose(observed, expected, rel_tol=0, abs_tol=5e-4), (
                f"Invalid or excessively imprecise update: from {previous}, "
                f"expected about {expected}, observed {observed}"
            )

        last = inputs[-1]
        last_fx = float(f"{last**3 - 5*last - 9:.6f}")
        last_fdx = float(f"{3*last**2 - 5:.6f}")
        final_delta = last_fx / last_fdx
        assert abs(final_delta) < 0.0001, (
            f"Job reported success without meeting tolerance: delta={final_delta}"
        )

        assert os.path.isfile(SUCCESS_LOG), "Successful execution did not create success.log"
        with open(SUCCESS_LOG, "r") as f:
            content = f.read().strip()
        value_match = re.fullmatch(r"Converged at\s+([-+0-9.eE]+)", content)
        assert value_match, f"Unexpected success.log content: {content!r}"
        logged_value = float(value_match.group(1))
        expected_final = last - final_delta
        assert math.isclose(logged_value, expected_final, rel_tol=0, abs_tol=5e-4), (
            f"Logged value {logged_value} is not the final computed update {expected_final}"
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)


def test_success_log_exists():
    assert os.path.isfile(SUCCESS_LOG), (
        f"Expected success log file at {SUCCESS_LOG} does not exist. "
        "Did the script run successfully and converge?"
    )


def test_success_log_content():
    assert os.path.isfile(SUCCESS_LOG), (
        f"Cannot check content because {SUCCESS_LOG} does not exist."
    )
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()

    # Check if the content matches the expected convergence value.
    match = re.search(r"Converged at 2\.85519.*", content)
    assert match is not None, (
        f"Content of {SUCCESS_LOG} ('{content}') does not match the expected "
        "convergence value pattern 'Converged at 2.85519...'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
