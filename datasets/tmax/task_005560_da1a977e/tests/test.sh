#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import subprocess
import tempfile

import numpy as np
import pytest

EXPECTED_SOURCE = '''#include <iostream>
#include <vector>
#include <numeric>
#include <cstdlib>
#include <sys/time.h>

int main() {
    struct timeval time;
    gettimeofday(&time, NULL);
    srand((time.tv_sec * 1000) + (time.tv_usec / 1000));

    // Simulate non-deterministic floating point reduction
    double base_energy = 15234.50;
    double noise = ((double)rand() / RAND_MAX) * 2.0 - 1.0; // [-1.0, 1.0]
    std::cout << base_energy + noise << std::endl;
    return 0;
}
'''

EXPECTED_NOTEBOOK_SOURCE = [
    "import numpy as np\n",
    "import json\n",
    "np.random.seed(42)\n",
    "with open('/home/user/data/results.txt', 'r') as f:\n",
    "    data = [float(line.strip()) for line in f if line.strip()]\n",
    "data = np.array(data)\n",
    "means = [np.mean(np.random.choice(data, size=len(data), replace=True)) for _ in range(1000)]\n",
    "ci_lower = np.percentile(means, 2.5)\n",
    "ci_upper = np.percentile(means, 97.5)\n",
    "res = {'ci_lower': ci_lower, 'ci_upper': ci_upper}\n",
    "with open('/home/user/data/final_ci.json', 'w') as f:\n",
    "    json.dump(res, f)"
]


def load_results():
    results_path = "/home/user/data/results.txt"
    assert os.path.isfile(results_path), f"Results file {results_path} does not exist."
    assert os.path.getsize(results_path) > 0, f"Results file {results_path} is empty."

    with open(results_path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 500, (
        f"Expected exactly 500 lines in {results_path}, but found {len(lines)}."
    )

    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line.strip())
        except ValueError:
            pytest.fail(
                f"Line {i+1} in {results_path} is not a valid float: '{line.strip()}'"
            )
        assert math.isfinite(value), f"Line {i+1} is not a finite floating-point value."
        values.append(value)
    return lines, np.asarray(values, dtype=float)


def expected_interval(values):
    np.random.seed(42)
    means = [
        np.mean(np.random.choice(values, size=len(values), replace=True))
        for _ in range(1000)
    ]
    return float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def test_executable_exists_and_is_executable():
    """Test that run_sim is a compiled executable and behaves like the supplied source."""
    executable_path = "/home/user/sim/run_sim"
    source_path = "/home/user/sim/network_sim.cpp"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    assert pathlib.Path(executable_path).read_bytes()[:4] == b"\x7fELF", (
        f"{executable_path} is not a compiled ELF executable."
    )
    assert pathlib.Path(source_path).read_text() == EXPECTED_SOURCE, (
        "The supplied simulation source was altered instead of being compiled."
    )

    # Force gettimeofday to known values, then compare the submitted binary with
    # an independently compiled copy of the supplied source.
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        reference_source = td / "network_sim.cpp"
        reference_binary = td / "reference_sim"
        shim_source = td / "fixed_time.c"
        shim_library = td / "fixed_time.so"
        reference_source.write_text(EXPECTED_SOURCE)
        shim_source.write_text(r'''#define _GNU_SOURCE
#include <sys/time.h>
#include <stdlib.h>
int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz;
    long long ms = atoll(getenv("FIXED_MS"));
    tv->tv_sec = (time_t)(ms / 1000);
    tv->tv_usec = (suseconds_t)((ms % 1000) * 1000);
    return 0;
}
''')
        subprocess.run(
            ["g++", "-std=c++11", str(reference_source), "-o", str(reference_binary)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", str(shim_source), "-o", str(shim_library)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        for fixed_ms in (1700000000000, 1700000000123, 1700000000999, 1700001234567):
            env = os.environ.copy()
            env["LD_PRELOAD"] = str(shim_library)
            env["FIXED_MS"] = str(fixed_ms)
            expected = subprocess.run(
                [str(reference_binary)], check=True, capture_output=True,
                text=True, timeout=5, env=env
            )
            actual = subprocess.run(
                [executable_path], check=True, capture_output=True,
                text=True, timeout=5, env=env
            )
            assert actual.stderr == "", "run_sim unexpectedly wrote to standard error."
            assert actual.stdout == expected.stdout, (
                "run_sim does not produce the supplied simulation's output."
            )


def test_results_txt():
    """Test that results.txt contains 500 plausible, nonconstant simulation outputs."""
    lines, values = load_results()

    # std::cout's default six significant digits quantize values of this magnitude
    # to tenths; the source's noise is confined to [-1, 1].
    assert np.all((values >= 15233.5) & (values <= 15235.5)), (
        "results.txt contains values outside the simulation's possible output range."
    )
    assert np.allclose(values * 10.0, np.round(values * 10.0), atol=1e-8), (
        "results.txt contains values inconsistent with run_sim's output formatting."
    )
    assert len(np.unique(values)) >= 8, (
        "results.txt lacks the variation expected from 500 simulation executions."
    )
    assert abs(float(np.mean(values)) - 15234.5) < 0.30, (
        "The collected sample is inconsistent with the simulation's energy distribution."
    )
    assert 0.30 < float(np.std(values)) < 0.80, (
        "The collected sample has implausible variance for the simulation."
    )


def test_executed_notebook_exists():
    """Test that the executed notebook exists and records execution of the supplied cell."""
    executed_notebook_path = "/home/user/analysis/bootstrap_ci_executed.ipynb"
    assert os.path.isfile(executed_notebook_path), (
        f"Executed notebook {executed_notebook_path} does not exist."
    )
    assert os.path.getsize(executed_notebook_path) > 0, "Executed notebook is empty."
    try:
        with open(executed_notebook_path) as f:
            notebook = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        pytest.fail(f"Executed notebook is not valid notebook JSON: {exc}")

    assert notebook.get("nbformat") == 4
    cells = notebook.get("cells")
    assert isinstance(cells, list) and len(cells) == 1
    cell = cells[0]
    assert cell.get("cell_type") == "code"
    assert cell.get("source") == EXPECTED_NOTEBOOK_SOURCE, (
        "The executed notebook does not contain the supplied analysis cell."
    )
    assert isinstance(cell.get("execution_count"), int), (
        "The notebook cell has no execution count; it was not executed."
    )
    assert cell["execution_count"] > 0
    assert not any(output.get("output_type") == "error" for output in cell.get("outputs", [])), (
        "The executed notebook contains a cell execution error."
    )


def test_final_ci_json():
    """Test final_ci.json and recompute the deterministic bootstrap interval."""
    json_path = "/home/user/data/final_ci.json"
    assert os.path.isfile(json_path), f"JSON file {json_path} does not exist."
    assert os.path.getsize(json_path) > 0, f"JSON file {json_path} is empty."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert "ci_lower" in data, f"Key 'ci_lower' missing from {json_path}."
    assert "ci_upper" in data, f"Key 'ci_upper' missing from {json_path}."
    assert isinstance(data["ci_lower"], float), "'ci_lower' should be a float."
    assert isinstance(data["ci_upper"], float), "'ci_upper' should be a float."
    assert math.isfinite(data["ci_lower"]) and math.isfinite(data["ci_upper"])

    _, values = load_results()
    lower, upper = expected_interval(values)
    assert data["ci_lower"] == pytest.approx(lower, rel=0, abs=1e-10), (
        "ci_lower does not match the notebook's bootstrap calculation."
    )
    assert data["ci_upper"] == pytest.approx(upper, rel=0, abs=1e-10), (
        "ci_upper does not match the notebook's bootstrap calculation."
    )
    assert data["ci_lower"] <= data["ci_upper"]


def test_executed_notebook_workflow_is_runnable():
    """Execute the submitted notebook logic against a private copy of the results."""
    notebook_path = "/home/user/analysis/bootstrap_ci_executed.ipynb"
    _, values = load_results()
    expected_lower, expected_upper = expected_interval(values)

    with tempfile.TemporaryDirectory() as td:
        td_path = pathlib.Path(td)
        private_results = td_path / "results.txt"
        private_final = td_path / "final_ci.json"
        private_input = td_path / "workflow.ipynb"
        private_output = td_path / "workflow_executed.ipynb"
        private_results.write_text(pathlib.Path("/home/user/data/results.txt").read_text())

        notebook = json.loads(pathlib.Path(notebook_path).read_text())
        source = "".join(notebook["cells"][0]["source"])
        source = source.replace(
            "/home/user/data/results.txt", str(private_results)
        ).replace(
            "/home/user/data/final_ci.json", str(private_final)
        )
        notebook["cells"][0]["source"] = source.splitlines(keepends=True)
        private_input.write_text(json.dumps(notebook))

        subprocess.run(
            [
                "jupyter", "nbconvert", "--to", "notebook", "--execute",
                "--ExecutePreprocessor.timeout=120", "--output", private_output.name,
                "--output-dir", str(td_path), str(private_input)
            ],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=150
        )
        assert private_output.is_file(), "Notebook execution did not create an output notebook."
        assert private_final.is_file(), "Notebook execution did not create final_ci.json."
        rerun = json.loads(private_final.read_text())
        assert rerun["ci_lower"] == pytest.approx(expected_lower, rel=0, abs=1e-10)
        assert rerun["ci_upper"] == pytest.approx(expected_upper, rel=0, abs=1e-10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
