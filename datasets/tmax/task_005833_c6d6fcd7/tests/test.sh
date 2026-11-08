#!/bin/bash
set -e
mkdir -p /logs/verifier
export OMP_NUM_THREADS=4
export OMP_DYNAMIC=FALSE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import importlib.machinery
import inspect
import os
import re
import subprocess
import sys

import nbformat
import numpy as np

HOME = "/home/user"
SOURCE = os.path.join(HOME, "sim_core.c")
NOTEBOOK = os.path.join(HOME, "simulation.ipynb")
ENERGY_FILE = os.path.join(HOME, "reproducible_energy.txt")


def sequential_energy(data):
    energy = 0.0
    for x in data:
        energy += float(x) * 1.0000001
    return energy


def expected_notebook_value():
    np.random.seed(42)
    return f"{sequential_energy(np.random.rand(1000000)):.12f}"


def notebook_printed_value(path):
    notebook = nbformat.read(path, as_version=4)
    values = []
    for cell in notebook.cells:
        if cell.get("cell_type") != "code":
            continue
        for output in cell.get("outputs", []):
            if output.get("output_type") == "stream":
                text = output.get("text", "")
                for line in text.splitlines():
                    line = line.strip()
                    if re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", line):
                        values.append(line)
    assert values, "The notebook has no printed numerical output; it was not executed successfully."
    return values[-1]


def test_sim_core_c_fixed_and_installed():
    assert os.path.isfile(SOURCE), f"File not found: {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    original_pragma = re.compile(
        r"^\s*#\s*pragma\s+omp\s+parallel\s+for\s+reduction\s*\(\s*\+\s*:\s*energy\s*\)\s*$",
        re.MULTILINE,
    )
    assert not original_pragma.search(content), "The original nondeterministic OpenMP reduction is still active."

    assert importlib.metadata.version("sim_core") == "1.0", "sim_core was not installed into the current Python environment."

    os.chdir(HOME)
    if HOME not in sys.path:
        sys.path.insert(0, HOME)
    import sim_core

    module_path = os.path.realpath(sim_core.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"sim_core is not a compiled C extension: {module_path}"
    assert inspect.isbuiltin(sim_core.compute_energy), "compute_energy is not provided by the compiled extension."
    assert os.path.getmtime(module_path) >= os.path.getmtime(SOURCE), \
        "The loaded sim_core extension is older than sim_core.c; rebuild and reinstall it."

    # Answers are derived at verification time from fresh inputs. Exact equality
    # requires the extension to perform the requested left-to-right reduction.
    seed = int.from_bytes(os.urandom(16), "little")
    rng = np.random.default_rng(seed)
    inputs = [
        rng.random(200003, dtype=np.float64),
        rng.normal(size=100019).astype(np.float64),
    ]
    magnitudes = np.ldexp(rng.uniform(-1.0, 1.0, 120017), rng.integers(-35, 36, 120017)).astype(np.float64)
    inputs.append(magnitudes)

    for data in inputs:
        expected = sequential_energy(data)
        results = [sim_core.compute_energy(data) for _ in range(3)]
        assert all(type(value) is float for value in results)
        assert all(value == expected for value in results), \
            f"compute_energy does not use the required deterministic reduction order (seed={seed})."
        assert results[0] == results[1] == results[2], "compute_energy changed across repeated calls."


def test_reproducible_energy_txt_and_notebook_execution():
    assert os.path.isfile(ENERGY_FILE), f"Output file {ENERGY_FILE} was not created."
    with open(ENERGY_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_value = expected_notebook_value()
    assert content == expected_value, f"Expected energy value {expected_value}, but got {content}"
    assert os.path.isfile(NOTEBOOK), f"Notebook not found: {NOTEBOOK}"

    # It must already contain the result of an execution performed by the agent.
    assert notebook_printed_value(NOTEBOOK) == expected_value

    observed = []
    for _ in range(2):
        subprocess.run(
            [
                sys.executable, "-m", "jupyter", "nbconvert",
                "--to", "notebook", "--execute", "--inplace",
                "--ExecutePreprocessor.timeout=180", NOTEBOOK,
            ],
            cwd=HOME,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
        )
        observed.append(notebook_printed_value(NOTEBOOK))

    assert observed == [expected_value, expected_value], \
        f"Repeated notebook executions were not exactly reproducible: {observed}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
