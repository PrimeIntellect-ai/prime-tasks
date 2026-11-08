#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import matplotlib.image as mpimg
import pytest

PROJECT = "/home/user/langevin_fit"
SIMULATED = os.path.join(PROJECT, "simulated.csv")
PDB = "/home/user/data/init.pdb"
TARGET = "/home/user/data/target.csv"
KL_FILE = "/home/user/kl_result.txt"


def run(command, cwd=None, timeout=180):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {command!r} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_numbers(path):
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    values = [float(line) for line in lines]
    assert all(math.isfinite(v) for v in values), f"Non-finite value in {path}"
    return values


def reference_simulation(initial_x, steps=100000):
    x = initial_x
    dt = 0.01
    tolerance = 1e-4
    seed = 42
    bins = [0.0] * 20

    for _ in range(steps):
        seed = (seed * 1664525 + 1013904223) & 0xffffffff
        noise = (seed >> 16) / 65536.0 - 0.5
        force = -0.5 * x
        dx = force * dt + noise * math.sqrt(dt)
        err = abs(dx * 0.1)
        x += dx

        bin_index = math.floor((x + 5.0) / 10.0 * 20.0)
        bin_index = max(0, min(19, bin_index))
        bins[bin_index] += 1.0

        new_dt = math.inf if err == 0.0 else dt * math.sqrt(tolerance / err)
        if new_dt > 0.1:
            new_dt = 0.1
        if new_dt < 0.0001:
            new_dt = 0.0001
        dt = new_dt

    return [value / steps for value in bins]


def assert_distribution_matches(initial_x):
    actual = read_numbers(SIMULATED)
    expected = reference_simulation(initial_x)
    assert len(actual) == 20, "simulated.csv must contain exactly 20 probability bins"
    assert all(v >= 0.0 for v in actual), "simulated.csv contains negative probabilities"
    assert abs(sum(actual) - 1.0) < 1e-10, "simulated.csv is not normalized"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert abs(got - want) < 1e-8, (
            f"simulated.csv bin {i} is {got}, expected {want}; the fixed simulation "
            "or PDB initial coordinate was not used"
        )
    return actual


def assert_kl_file(simulated):
    target = read_numbers(TARGET)
    assert len(target) == len(simulated), "Target and simulated distributions have different lengths"
    expected = sum(
        (p + 1e-9) * math.log((p + 1e-9) / (q + 1e-9))
        for p, q in zip(simulated, target)
    )

    assert os.path.isfile(KL_FILE), f"The file {KL_FILE} is missing"
    with open(KL_FILE, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), (
        "kl_result.txt must contain only one floating-point number"
    )
    value = float(content)
    assert math.isfinite(value), "KL result must be finite"
    assert abs(value - expected) < 1e-8, f"KL result {value} does not match recomputed value {expected}"
    assert value < 0.1, f"The KL divergence value {value} is too high"


def test_integrator_fixed():
    path = os.path.join(PROJECT, "src/integrator.rs")
    assert os.path.isfile(path), f"The file {path} is missing"
    with open(path, "r") as f:
        content = f.read()
    assert "(tolerance / err).sqrt()" in content or "(tolerance/err).sqrt()" in content, \
        "integrator.rs does not contain the fixed step-size formula"


def test_cargo_test_passes_and_regression_test_exists():
    test_path = os.path.join(PROJECT, "tests/integration_test.rs")
    assert os.path.isfile(test_path), f"The regression test file {test_path} is missing"
    with open(test_path, "r") as f:
        content = f.read().lower()
    assert "assert" in content and "kl" in content, "The regression test must assert a KL result"
    assert any(limit in content for limit in ("0.05", "5e-2", "5e-02")), \
        "The regression test must enforce the required KL < 0.05 threshold"

    result = run(["cargo", "test"], cwd=PROJECT)
    assert "test result: ok." in result.stdout or "1 passed" in result.stdout, \
        "No tests passed or no tests were found"


def test_program_outputs_and_pdb_parsing():
    with open(PDB, "r") as f:
        original_pdb = f.read()

    try:
        # Change only the first atom's fixed-width X field. A correct parser must make
        # the generated distribution follow this changed input.
        lines = original_pdb.splitlines(True)
        assert lines and lines[0].startswith(("ATOM", "HETATM"))
        lines[0] = lines[0][:30] + f"{-3.750:8.3f}" + lines[0][38:]
        with open(PDB, "w") as f:
            f.write("".join(lines))

        for path in (SIMULATED, KL_FILE):
            if os.path.exists(path):
                os.remove(path)
        run(["cargo", "run", "--quiet"], cwd=PROJECT)
        changed = assert_distribution_matches(-3.75)
        assert_kl_file(changed)
    finally:
        with open(PDB, "w") as f:
            f.write(original_pdb)

    # Leave and validate artifacts produced from the provided PDB (first X = 2.500).
    for path in (SIMULATED, KL_FILE):
        if os.path.exists(path):
            os.remove(path)
    run(["cargo", "run", "--quiet"], cwd=PROJECT)
    simulated = assert_distribution_matches(2.5)
    assert_kl_file(simulated)


def test_plot_script_executes_and_generates_plot():
    script = "/home/user/plot_dist.py"
    plot = "/home/user/distribution.png"
    assert os.path.isfile(script), f"The python script {script} is missing"
    with open(script, "r") as f:
        source = f.read().lower()
    for required in ("simulated.csv", "target.csv", "simulated", "target"):
        assert required in source, f"plot_dist.py does not reference {required}"

    if os.path.exists(plot):
        os.remove(plot)
    run(["python3", script], cwd=PROJECT)
    assert os.path.isfile(plot), f"The plot file {plot} is missing"
    assert os.path.getsize(plot) > 0, f"The plot file {plot} is empty"
    with open(plot, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "distribution.png is not a PNG image"
    image = mpimg.imread(plot)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "distribution.png is not a usable plot"
    assert float(image.max()) - float(image.min()) > 0.05, "distribution.png appears blank"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
