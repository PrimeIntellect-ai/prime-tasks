#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import math
import os
import re
import secrets
import subprocess
import sys
import tempfile

import numpy as np

VENDORED_INTEGRATOR = "/app/vendored/pydynsim-1.2.0/pydynsim/integrator.py"
ANALYZE = "/home/user/analyze.py"
OUTPUT = "/home/user/frequency.txt"
PDB = "/app/data/protein.pdb"


def read_frequency():
    assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content, f"File {OUTPUT} is empty."
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), \
        f"{OUTPUT} must contain only one floating-point number; got: {content!r}"
    try:
        value = float(content)
    except ValueError:
        raise AssertionError(f"Could not parse the content of {OUTPUT} as a float. Content: {content!r}")
    assert math.isfinite(value), f"Frequency must be finite, got {value}"
    return value


def test_complete_task():
    # Preserve the original source-level assertions.
    assert os.path.isfile(VENDORED_INTEGRATOR), f"Missing file: {VENDORED_INTEGRATOR}"
    with open(VENDORED_INTEGRATOR, "r") as f:
        content = f.read()
    assert "(tolerance / error)**0.5" in content, \
        "The integrator.py does not contain the expected fixed step-size adaptation logic."
    assert "(error / tolerance)**0.5" not in content, \
        "The integrator.py still contains the buggy step-size adaptation logic."

    assert os.path.isfile(ANALYZE), f"Missing script: {ANALYZE}"
    with open(ANALYZE, "r") as f:
        analyze_source = f.read()
    tree = ast.parse(analyze_source, filename=ANALYZE)
    fft_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            fn = node.func
            parts = []
            while isinstance(fn, ast.Attribute):
                parts.append(fn.attr)
                fn = fn.value
            if isinstance(fn, ast.Name):
                parts.append(fn.id)
            name = ".".join(reversed(parts)).lower()
            if "fft" in name:
                fft_calls.append(name)
    assert fft_calls, "analyze.py does not perform an FFT."

    # Verify that a fixed distribution is installed and works, rather than merely
    # accepting a textual edit to the vendored source.
    assert importlib.metadata.version("pydynsim") == "1.2.0", \
        "pydynsim 1.2.0 is not installed in the system Python environment."
    import pydynsim
    from pydynsim.integrator import get_dt
    assert math.isclose(get_dt(), 0.0001, rel_tol=1e-12, abs_tol=1e-15), \
        f"Installed integrator has incorrect behavior: get_dt()={get_dt()}"
    trajectory = pydynsim.simulate(PDB, steps=5000)
    assert isinstance(trajectory, np.ndarray)
    assert trajectory.shape == (5000, 10, 3), f"Unexpected simulation shape: {trajectory.shape}"
    assert np.isfinite(trajectory).all(), "The installed package simulation returned NaNs or infinities."

    # Execute the submitted artifact normally and retain the original expected-output check.
    subprocess.run([sys.executable, ANALYZE], cwd="/home/user", check=True, timeout=60)
    agent_val = read_frequency()
    target_val = 15.625
    error = abs(agent_val - target_val)
    assert error <= 0.5, \
        f"Calculated frequency {agent_val} is too far from the target {target_val}. Error {error} > 0.5."

    # Exercise analyze.py on a verifier-selected FFT bin. sitecustomize wraps the
    # installed package's simulate function, records its arguments, and supplies a
    # fresh trajectory so a hard-coded frequency cannot pass.
    selected_bin = secrets.randbelow(1400) + 300
    if selected_bin in (781, 782):
        selected_bin += 100
    expected = selected_bin / (5000 * 0.01)

    with tempfile.TemporaryDirectory() as shimdir:
        marker = os.path.join(shimdir, "simulate_called.txt")
        shim = r'''
import os
import numpy as np
import pydynsim

_original_simulate = pydynsim.simulate

def _verified_simulate(filepath, steps=5000):
    with open(os.environ["PYDYNSIM_CALL_MARKER"], "w") as f:
        f.write(str(filepath) + "\n" + str(steps) + "\n")
    n = int(steps)
    dt = 0.01
    k = int(os.environ["PYDYNSIM_TEST_BIN"])
    t = np.arange(n, dtype=float) * dt
    arr = np.zeros((n, 10, 3), dtype=float)
    frequency = k / (n * dt)
    arr[:, 4, 2] = np.sin(2.0 * np.pi * frequency * t)
    return arr

pydynsim.simulate = _verified_simulate
'''
        with open(os.path.join(shimdir, "sitecustomize.py"), "w") as f:
            f.write(shim)
        env = os.environ.copy()
        env["PYDYNSIM_TEST_BIN"] = str(selected_bin)
        env["PYDYNSIM_CALL_MARKER"] = marker
        env["PYTHONPATH"] = shimdir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        subprocess.run([sys.executable, ANALYZE], cwd="/home/user", env=env, check=True, timeout=60)

        assert os.path.isfile(marker), "analyze.py did not call pydynsim.simulate."
        with open(marker, "r") as f:
            call = f.read().splitlines()
        assert call == [PDB, "5000"], \
            f"analyze.py must call pydynsim.simulate({PDB!r}, steps=5000); observed {call!r}"

    dynamic_val = read_frequency()
    assert abs(dynamic_val - expected) <= 0.05, \
        f"FFT analysis failed on a verifier-selected trajectory: got {dynamic_val}, expected {expected} THz."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
