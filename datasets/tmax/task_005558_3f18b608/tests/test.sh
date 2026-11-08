#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import h5py
import numpy as np
import pytest
from scipy.stats import wasserstein_distance

PROJECT = "/home/user/mcmc_project"
SOURCE = os.path.join(PROJECT, "mcmc.cpp")
EXECUTABLE = os.path.join(PROJECT, "mcmc_sim")
POSTERIOR = os.path.join(PROJECT, "posterior.txt")
DISTANCE = os.path.join(PROJECT, "wasserstein_distance.txt")


def restore_pristine_inputs():
    np.random.seed(42)
    t_obs = np.linspace(0, 10, 50)
    y_obs = np.zeros_like(t_obs)
    y, v = 1.0, 0.0
    t_current = 0.0

    for i, t_target in enumerate(t_obs):
        while t_current < t_target:
            dt = min(0.05, t_target - t_current)
            y, v = y + v * dt, v + (-2.0 * y - 0.5 * v) * dt
            t_current += dt
        y_obs[i] = y + np.random.normal(0, 0.05)

    reference = np.random.normal(0.5, 0.02, 5000)

    with h5py.File(os.path.join(PROJECT, "observations.h5"), "w") as f:
        f.create_dataset("t", data=t_obs)
        f.create_dataset("y", data=y_obs)
    with h5py.File(os.path.join(PROJECT, "reference_posterior.h5"), "w") as f:
        f.create_dataset("samples", data=reference)

    return reference


def read_posterior(path):
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "posterior.txt is empty."
    try:
        samples = np.asarray([float(line.strip()) for line in lines], dtype=float)
    except ValueError as exc:
        pytest.fail(f"posterior.txt contains a non-numeric sample: {exc}")
    assert samples.size == 4000, f"Expected 4000 posterior samples, found {samples.size}."
    assert np.all(np.isfinite(samples)), "posterior.txt contains non-finite samples."
    return samples


def run_and_read(command):
    if os.path.exists(POSTERIOR):
        os.remove(POSTERIOR)
    result = subprocess.run(
        command,
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Command {' '.join(command)} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return read_posterior(POSTERIOR)


def test_mcmc_cpp_fixed():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "dt =" in content or "dt=" in content, "No dt assignment found in mcmc.cpp."
    assert "t_end - t" in content or "t_end-t" in content, "The logic to cap dt to (t_end - t) is missing in mcmc.cpp."

    # Exercise integrate_to directly. The untouched implementation ends at 0.10,
    # whereas a correctly capped final step ends exactly at 0.07.
    harness = r'''#include <cmath>
#define main mcmc_program_main
#include "/home/user/mcmc_project/mcmc.cpp"
#undef main
int main() {
    double t = 0.0, y = 1.0, v = 0.0;
    integrate_to(0.07, t, y, v, 0.5, 2.0);
    if (std::fabs(t - 0.07) > 1e-12) return 2;
    if (std::fabs(y - 0.998) > 1e-12) return 3;
    if (std::fabs(v - (-0.139)) > 1e-12) return 4;
    return 0;
}
'''
    with open("/tmp/integrator_harness.cpp", "w") as f:
        f.write(harness)
    compile_result = subprocess.run(
        ["h5c++", "-std=c++11", "/tmp/integrator_harness.cpp", "-o", "/tmp/integrator_harness"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert compile_result.returncode == 0, f"mcmc.cpp could not be compiled:\n{compile_result.stderr}"
    run_result = subprocess.run(["/tmp/integrator_harness"], timeout=30)
    assert run_result.returncode == 0, "integrate_to does not cap its final step to hit t_end exactly."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "The compiled executable mcmc_sim is missing."
    assert os.access(EXECUTABLE, os.X_OK), "mcmc_sim is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mcmc_sim is not a compiled ELF executable."


@pytest.fixture(scope="module")
def executed_results():
    reference = restore_pristine_inputs()

    # Independently compile and run the submitted source.
    rebuilt = "/tmp/mcmc_rebuilt"
    compile_result = subprocess.run(
        ["h5c++", "-std=c++11", SOURCE, "-o", rebuilt],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert compile_result.returncode == 0, f"mcmc.cpp could not be compiled:\n{compile_result.stderr}"
    rebuilt_samples = run_and_read([rebuilt])
    rebuilt_distance = float(wasserstein_distance(rebuilt_samples, reference))
    assert 0.0 <= rebuilt_distance < 0.15, (
        f"Recompiled mcmc.cpp produced Wasserstein distance {rebuilt_distance}, "
        "outside [0.0, 0.15)."
    )

    # Execute the actual artifact requested by the instruction, not merely any
    # pre-created posterior file.
    submitted_samples = run_and_read([EXECUTABLE])
    submitted_distance = float(wasserstein_distance(submitted_samples, reference))
    assert 0.0 <= submitted_distance < 0.15, (
        f"mcmc_sim produced Wasserstein distance {submitted_distance}, "
        "outside [0.0, 0.15)."
    )
    assert np.allclose(submitted_samples, rebuilt_samples, rtol=0.0, atol=1e-6), (
        "mcmc_sim output does not match the executable rebuilt from mcmc.cpp."
    )
    return submitted_samples, submitted_distance


def test_posterior_txt_exists(executed_results):
    samples, _ = executed_results
    assert samples.size > 0


def test_wasserstein_distance_file(executed_results):
    _, actual_distance = executed_results
    assert os.path.isfile(DISTANCE), f"{DISTANCE} is missing."
    with open(DISTANCE, "r") as f:
        content = f.read().strip()

    try:
        distance = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {DISTANCE} as a float. Content: '{content}'")

    # Preserve the original bound assertion, then verify the value rather than
    # trusting a self-supplied number.
    assert 0.0 <= distance < 0.15, f"Wasserstein distance {distance} is out of expected bounds [0.0, 0.15). The bug might not be properly fixed."
    assert re.fullmatch(r"(?:0|[1-9][0-9]*)\.[0-9]{4}", content), (
        "wasserstein_distance.txt must contain the distance rounded to four decimal places."
    )
    expected_text = f"{actual_distance:.4f}"
    assert content == expected_text, (
        f"Reported Wasserstein distance {content} does not match the recomputed value {expected_text}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
