#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_plugin
cat << 'PLUGIN_EOF' > /tmp/verifier_plugin/probe_plugin.py
import json
import os


def _reference(matrix, steps, start, end):
    size = len(matrix)
    if steps == 0:
        return 1 if start == end else 0
    current = [row[:] for row in matrix]
    for _ in range(1, steps):
        current = [
            [sum(current[i][k] * matrix[k][j] for k in range(size)) for j in range(size)]
            for i in range(size)
        ]
    return current[start][end]


def pytest_configure(config):
    mode = os.environ.get("GRAPH_PROBE_MODE", "")
    if mode == "meta":
        return

    import graph_wrapper

    def probed_get_path_count(matrix, steps, start, end):
        normalized = [list(row) for row in matrix]
        log_path = os.environ.get("GRAPH_PROBE_LOG")
        if log_path:
            with open(log_path, "a") as handle:
                handle.write(json.dumps({
                    "matrix": normalized,
                    "steps": steps,
                    "start": start,
                    "end": end,
                }) + "\n")

        is_zero_case = (
            len(normalized) == 4
            and all(len(row) == 4 for row in normalized)
            and all(value == 0 for row in normalized for value in row)
            and 1 <= steps <= 5
            and 0 <= start <= 3
            and 0 <= end <= 3
        )
        if mode == "bad_zero" and is_zero_case:
            return 1
        if mode == "bad_steps" and steps == 0:
            return 0 if start == end else 1
        return _reference(normalized, steps, start, end)

    graph_wrapper.get_path_count = probed_get_path_count


def pytest_collection_modifyitems(session, config, items):
    if os.environ.get("GRAPH_PROBE_MODE") != "meta":
        return
    metadata = {}
    try:
        from hypothesis import is_hypothesis_test
    except ImportError:
        is_hypothesis_test = lambda obj: bool(getattr(obj, "is_hypothesis_test", False))
    for item in items:
        if item.name in ("test_zero_matrix_paths", "test_zero_steps"):
            obj = getattr(item, "obj", None)
            metadata[item.name] = bool(obj is not None and is_hypothesis_test(obj))
    with open(os.environ["GRAPH_PROBE_LOG"], "w") as handle:
        json.dump(metadata, handle)
PLUGIN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess

import pytest

ROOT = "/home/user/mathlib"
TEST_FILE = os.path.join(ROOT, "test_graph.py")
PLUGIN_PATH = "/tmp/verifier_plugin"


def run_pytest_node(name, mode, log_path=None):
    env = os.environ.copy()
    env["PYTHONPATH"] = PLUGIN_PATH + os.pathsep + env.get("PYTHONPATH", "")
    env["GRAPH_PROBE_MODE"] = mode
    if log_path:
        env["GRAPH_PROBE_LOG"] = log_path
    return subprocess.run(
        ["python3", "-m", "pytest", "-q", "-p", "probe_plugin", f"{TEST_FILE}::{name}"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def load_calls(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def is_binary_4x4(matrix):
    return (
        isinstance(matrix, list)
        and len(matrix) == 4
        and all(isinstance(row, list) and len(row) == 4 for row in matrix)
        and all(value in (0, 1) for row in matrix for value in row)
    )


def test_import_succeeds():
    """Verify that importing graph_wrapper succeeds after fixing the RPATH."""
    res = subprocess.run(
        ["python3", "-c", "import graph_wrapper"],
        cwd=ROOT,
        capture_output=True,
        text=True
    )
    assert res.returncode == 0, f"Importing graph_wrapper still fails. Error:\n{res.stderr}"


def test_rpath_configured():
    """Verify that libgraph.so has the correct RPATH set."""
    lib_path = os.path.join(ROOT, "lib", "libgraph.so")
    assert os.path.exists(lib_path), f"Library {lib_path} does not exist. Did you run build.sh?"

    res = subprocess.run(["readelf", "-d", lib_path], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to run readelf on libgraph.so"

    stdout_lower = res.stdout.lower()
    assert "rpath" in stdout_lower or "runpath" in stdout_lower, "RPATH/RUNPATH is not set in libgraph.so"
    assert "/home/user/mathlib/lib" in res.stdout, "RPATH does not point to the absolute path /home/user/mathlib/lib"


def test_build_script_reproduces_rpath_fix():
    """Delete built outputs and ensure the submitted build.sh recreates the fixed libraries."""
    build_script = os.path.join(ROOT, "build.sh")
    assert os.path.isfile(build_script), "build.sh is missing"
    assert os.access(build_script, os.X_OK), "build.sh is not executable"

    for name in ("libgraph.so", "libmatrix.so"):
        path = os.path.join(ROOT, "lib", name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    res = subprocess.run(["./build.sh"], cwd=ROOT, capture_output=True, text=True)
    assert res.returncode == 0, f"build.sh failed:\n{res.stdout}\n{res.stderr}"

    graph_lib = os.path.join(ROOT, "lib", "libgraph.so")
    matrix_lib = os.path.join(ROOT, "lib", "libmatrix.so")
    assert os.path.isfile(graph_lib), "build.sh did not recreate libgraph.so"
    assert os.path.isfile(matrix_lib), "build.sh did not recreate libmatrix.so"

    readelf = subprocess.run(["readelf", "-d", graph_lib], capture_output=True, text=True)
    assert readelf.returncode == 0, "Rebuilt libgraph.so is not a readable shared library"
    lowered = readelf.stdout.lower()
    assert "rpath" in lowered or "runpath" in lowered, "Rebuilt libgraph.so has no RPATH/RUNPATH"
    assert "/home/user/mathlib/lib" in readelf.stdout, "Rebuilt libgraph.so lacks the required absolute RPATH"

    imported = subprocess.run(
        ["python3", "-c", "import graph_wrapper"], cwd=ROOT, capture_output=True, text=True
    )
    assert imported.returncode == 0, f"Import failed after rebuilding:\n{imported.stderr}"


def test_dependencies_installed():
    """Verify that pytest and hypothesis are installed."""
    res = subprocess.run(
        ["python3", "-c", "import pytest; import hypothesis"],
        capture_output=True,
        text=True
    )
    assert res.returncode == 0, "pytest and/or hypothesis are not installed in the Python environment"


def test_test_graph_file_and_content():
    """Verify that test_graph.py exists and contains the required test functions."""
    assert os.path.exists(TEST_FILE), f"Test file {TEST_FILE} is missing"

    with open(TEST_FILE, "r") as f:
        content = f.read()

    assert "test_zero_matrix_paths" in content, "Function 'test_zero_matrix_paths' not found in test_graph.py"
    assert "test_zero_steps" in content, "Function 'test_zero_steps' not found in test_graph.py"
    assert "hypothesis" in content, "hypothesis does not appear to be used in test_graph.py"


def test_pytest_passes():
    """Verify that running pytest on test_graph.py succeeds."""
    res = subprocess.run(
        ["python3", "-m", "pytest", TEST_FILE],
        cwd=ROOT,
        capture_output=True,
        text=True
    )
    assert res.returncode == 0, f"pytest failed on test_graph.py. Output:\n{res.stdout}\n{res.stderr}"


def test_required_tests_are_hypothesis_tests(tmp_path):
    metadata_path = str(tmp_path / "metadata.json")
    env = os.environ.copy()
    env["PYTHONPATH"] = PLUGIN_PATH + os.pathsep + env.get("PYTHONPATH", "")
    env["GRAPH_PROBE_MODE"] = "meta"
    env["GRAPH_PROBE_LOG"] = metadata_path
    res = subprocess.run(
        ["python3", "-m", "pytest", "--collect-only", "-q", "-p", "probe_plugin", TEST_FILE],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Could not collect test_graph.py:\n{res.stdout}\n{res.stderr}"
    with open(metadata_path) as handle:
        metadata = json.load(handle)
    assert metadata.get("test_zero_matrix_paths") is True, "test_zero_matrix_paths is not a Hypothesis test"
    assert metadata.get("test_zero_steps") is True, "test_zero_steps is not a Hypothesis test"


def test_zero_matrix_property_exercises_required_domain_and_asserts(tmp_path):
    log_path = str(tmp_path / "zero_matrix_calls.jsonl")
    res = run_pytest_node("test_zero_matrix_paths", "log", log_path)
    assert res.returncode == 0, f"test_zero_matrix_paths failed under instrumentation:\n{res.stdout}\n{res.stderr}"
    calls = load_calls(log_path)
    matching = [
        call for call in calls
        if is_binary_4x4(call["matrix"])
        and all(value == 0 for row in call["matrix"] for value in row)
        and 1 <= call["steps"] <= 5
        and 0 <= call["start"] <= 3
        and 0 <= call["end"] <= 3
    ]
    assert len(matching) >= 10, "test_zero_matrix_paths did not generate the required zero-matrix cases"
    assert {call["steps"] for call in matching} == set(range(1, 6)), "steps does not cover the required 1..5 range"
    assert {call["start"] for call in matching} == set(range(4)), "start does not cover indices 0..3"
    assert {call["end"] for call in matching} == set(range(4)), "end does not cover indices 0..3"

    mutant = run_pytest_node("test_zero_matrix_paths", "bad_zero")
    assert mutant.returncode != 0, "test_zero_matrix_paths passes when zero-matrix path counts are incorrectly nonzero"


def test_zero_steps_property_exercises_required_domain_and_asserts(tmp_path):
    log_path = str(tmp_path / "zero_steps_calls.jsonl")
    res = run_pytest_node("test_zero_steps", "log", log_path)
    assert res.returncode == 0, f"test_zero_steps failed under instrumentation:\n{res.stdout}\n{res.stderr}"
    calls = load_calls(log_path)
    matching = [
        call for call in calls
        if is_binary_4x4(call["matrix"])
        and call["steps"] == 0
        and 0 <= call["start"] <= 3
        and 0 <= call["end"] <= 3
    ]
    assert len(matching) >= 10, "test_zero_steps did not generate enough required cases"
    assert any(call["start"] == call["end"] for call in matching), "test_zero_steps did not exercise start == end"
    assert any(call["start"] != call["end"] for call in matching), "test_zero_steps did not exercise start != end"
    observed_values = {value for call in matching for row in call["matrix"] for value in row}
    assert observed_values == {0, 1}, "test_zero_steps did not generate binary matrices containing both values"
    distinct_matrices = {json.dumps(call["matrix"], sort_keys=True) for call in matching}
    assert len(distinct_matrices) >= 2, "test_zero_steps did not generate varying matrices"

    mutant = run_pytest_node("test_zero_steps", "bad_steps")
    assert mutant.returncode != 0, "test_zero_steps passes with the identity-matrix result inverted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
