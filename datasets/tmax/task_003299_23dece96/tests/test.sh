#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import subprocess
import tempfile

import numpy as np
import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "bio_sim.c")
LIBRARY = os.path.join(HOME, "libbiosim.so")
NOTEBOOK = os.path.join(HOME, "workflow.ipynb")
RESULT = os.path.join(HOME, "sim_result.json")


def configure_library(path):
    lib = ctypes.CDLL(path)
    array = np.ctypeslib.ndpointer(dtype=np.float64, flags="C_CONTIGUOUS")
    lib.compute_total_mass.restype = ctypes.c_double
    lib.compute_total_mass.argtypes = [array, ctypes.c_int]
    lib.solve_lu.restype = None
    lib.solve_lu.argtypes = [array, array, ctypes.c_int]
    return lib


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_workflow():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    assert os.path.isfile(NOTEBOOK), f"File {NOTEBOOK} is missing."

    # Compile bio_sim.c directly so a stale or fabricated shared object cannot pass.
    direct_lib = os.path.join(tempfile.mkdtemp(prefix="biosim-test-"), "libbiosim.so")
    direct_build = subprocess.run(
        ["gcc", "-shared", "-o", direct_lib, "-fPIC", "-O3", "-fopenmp", SOURCE],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert direct_build.returncode == 0, direct_build.stdout

    # Also exercise the required project build and its resulting artifact.
    build = subprocess.run(
        ["make"], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60,
    )
    assert build.returncode == 0, build.stdout
    assert os.path.isfile(LIBRARY), "make did not produce /home/user/libbiosim.so"

    yield direct_lib

    # Execute the actual notebook as part of verification. Any cell error makes
    # nbconvert fail, and the generated result is checked below.


@pytest.fixture(scope="session")
def executed_notebook(build_and_execute_workflow):
    output_name = "verified_workflow.ipynb"
    output_path = os.path.join("/tmp", output_name)
    if os.path.exists(output_path):
        os.unlink(output_path)
    run = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute",
            "--ExecutePreprocessor.timeout=120", "--output", output_name,
            "--output-dir", "/tmp", NOTEBOOK,
        ],
        cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180,
    )
    assert run.returncode == 0, run.stdout
    assert os.path.isfile(output_path), "Notebook execution produced no executed notebook"
    with open(output_path, "r") as f:
        notebook = json.load(f)
    code_cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code"]
    assert code_cells and all(c.get("execution_count") is not None for c in code_cells), \
        "The notebook was not fully executed"
    assert not any(
        output.get("output_type") == "error"
        for cell in code_cells for output in cell.get("outputs", [])
    ), "The executed notebook contains a cell error"
    return notebook


def test_bio_sim_c_reduction():
    file_path = "/home/user/bio_sim.c"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()
    # Preserve the original assertion.
    assert "reduction" in content, "The bio_sim.c file does not use OpenMP 'reduction' as required to fix the non-deterministic reduction."

    # Do not allow the word to appear only in a comment: require a real OpenMP
    # reduction pragma in compute_total_mass and removal of its atomic update.
    no_comments = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    no_comments = re.sub(r"//[^\n]*", "", no_comments)
    start = no_comments.find("double compute_total_mass")
    end = no_comments.find("void solve_lu", start)
    assert start >= 0 and end > start, "Required C functions are missing"
    mass_function = no_comments[start:end]
    assert re.search(
        r"#\s*pragma\s+omp\s+parallel\s+for[^\n]*\breduction\s*\(\s*\+\s*:\s*total_mass\s*\)",
        mass_function,
    ), "compute_total_mass must use an OpenMP parallel-for reduction on total_mass"
    assert not re.search(r"#\s*pragma\s+omp\s+atomic", mass_function), \
        "compute_total_mass still uses an atomic floating-point accumulation"


def exercise_c_library(path):
    lib = configure_library(path)
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))

    # Derive fresh diagonally dominant systems at verification time, preventing
    # a solver specialized to the notebook's single 4x4 example.
    for n in (1, 2, 3, 5, 8, 13):
        for _ in range(3):
            A = rng.normal(size=(n, n)).astype(np.float64)
            A[np.diag_indices(n)] = np.sum(np.abs(A), axis=1) + rng.uniform(1.0, 3.0, n)
            b = rng.normal(size=n).astype(np.float64)
            expected = np.linalg.solve(A.copy(), b.copy())
            actual_A = np.ascontiguousarray(A.copy())
            actual_b = np.ascontiguousarray(b.copy())
            lib.solve_lu(actual_A, actual_b, n)
            assert np.all(np.isfinite(actual_b)), "solve_lu produced non-finite values"
            assert np.allclose(actual_b, expected, rtol=2e-10, atol=2e-10), \
                f"solve_lu returned an incorrect solution for a {n}x{n} system"
            assert np.allclose(A @ actual_b, b, rtol=2e-10, atol=2e-10), \
                "solve_lu solution does not satisfy Ax=b"

    state = rng.normal(size=200003).astype(np.float64)
    observed = [lib.compute_total_mass(state, state.size) for _ in range(80)]
    assert all(np.isfinite(observed)), "compute_total_mass produced a non-finite result"
    assert len({np.float64(x).tobytes() for x in observed}) == 1, \
        "compute_total_mass is not bit-for-bit reproducible across identical calls"
    assert np.isclose(observed[0], np.sum(state), rtol=1e-12, atol=1e-10), \
        "compute_total_mass returned an incorrect total"


def test_compiled_c_functions(build_and_execute_workflow):
    exercise_c_library(build_and_execute_workflow)
    exercise_c_library(LIBRARY)


def test_notebook_executed(executed_notebook):
    output_text = "".join(
        str(output.get("text", ""))
        for cell in executed_notebook.get("cells", [])
        for output in cell.get("outputs", [])
        if output.get("output_type") == "stream"
    )
    assert "Simulation successful." in output_text, \
        "The workflow did not reach its successful completion"


def test_sim_result_json(executed_notebook):
    file_path = "/home/user/sim_result.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The notebook might not have been executed successfully."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("sim_result.json does not contain valid JSON.")

    # Preserve all original result assertions.
    assert "state" in data, "sim_result.json is missing 'state' key."
    assert "mass" in data, "sim_result.json is missing 'mass' key."
    assert abs(data['state'][0] - 0.1219512) < 1e-4, f"Expected state[0] to be ~0.1219512, got {data['state'][0]}"
    assert abs(data['mass'] - 3.12195) < 1e-4, f"Expected mass to be ~3.12195, got {data['mass']}"

    A = np.array([
        [4.0, 1.0, 0.0, 0.0],
        [1.0, 4.0, 1.0, 0.0],
        [0.0, 1.0, 4.0, 1.0],
        [0.0, 0.0, 1.0, 3.0],
    ])
    b = np.array([1.0, 2.0, 3.0, 4.0])
    expected = np.linalg.solve(A, b)
    state = np.asarray(data["state"], dtype=float)
    assert state.shape == (4,), "sim_result.json has an invalid state shape"
    assert np.allclose(state, expected, rtol=1e-12, atol=1e-12), \
        "sim_result.json does not contain the solved ODE state"
    assert np.isclose(float(data["mass"]), np.sum(expected), rtol=1e-12, atol=1e-12), \
        "sim_result.json contains an incorrect total mass"
TEST_EOF

if OMP_NUM_THREADS=4 OMP_DYNAMIC=FALSE python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
