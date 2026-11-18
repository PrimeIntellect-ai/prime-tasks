#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import json
import math
import os
import struct
import subprocess
import textwrap
import time

import pytest

WORKSPACE_DIR = "/home/user/workspace"
SCRIPT_FILE = os.path.join(WORKSPACE_DIR, "model_eval.py")
RESULTS_FILE = os.path.join(WORKSPACE_DIR, "results.json")
VENV_PYTHON = os.path.join(WORKSPACE_DIR, "venv", "bin", "python")
DATASETS = ["data1.csv", "data2.csv", "data3.csv"]


def clean_outputs():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    for path in glob.glob(os.path.join(WORKSPACE_DIR, "plot_*.png")):
        os.remove(path)


def run_command(args, timeout=120):
    env = os.environ.copy()
    env.pop("MPLBACKEND", None)
    return subprocess.run(
        args,
        cwd=WORKSPACE_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_FILE), f"Missing required script: {SCRIPT_FILE}"
    assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK), \
        f"Missing usable virtual environment Python: {VENV_PYTHON}"

    dependency_check = run_command([
        VENV_PYTHON,
        "-c",
        "import numpy, pandas, matplotlib; assert matplotlib.__version__",
    ])
    assert dependency_check.returncode == 0, \
        f"Required packages are not installed in the virtual environment:\n{dependency_check.stderr}"

    # Exercise main() with deliberately slow loading, training, and prediction.
    # A correct benchmark must include the prediction delay, but exclude the two
    # larger delays outside predict(). This prevents a fabricated or whole-run time.
    clean_outputs()
    benchmark_csv = os.path.join(WORKSPACE_DIR, "benchmark.csv")
    with open(benchmark_csv, "w") as f:
        f.write("x,y\n1,2\n2,4\n3,6\n")

    harness = textwrap.dedent(f"""
        import runpy
        import sys
        import time

        ns = runpy.run_path({SCRIPT_FILE!r}, run_name="model_eval_under_test")
        original_load = ns["load_data"]
        original_train = ns["train_model"]
        original_predict = ns["predict"]

        def slow_load(*args, **kwargs):
            time.sleep(0.20)
            return original_load(*args, **kwargs)

        def slow_train(*args, **kwargs):
            time.sleep(0.20)
            return original_train(*args, **kwargs)

        def slow_predict(*args, **kwargs):
            time.sleep(0.15)
            return original_predict(*args, **kwargs)

        ns["load_data"] = slow_load
        ns["train_model"] = slow_train
        ns["predict"] = slow_predict
        sys.argv = [{SCRIPT_FILE!r}, "benchmark.csv"]
        ns["main"]()
    """)

    started = time.monotonic()
    benchmark_run = run_command([VENV_PYTHON, "-c", harness])
    elapsed = time.monotonic() - started
    assert benchmark_run.returncode == 0, \
        f"The script failed during benchmark instrumentation:\n{benchmark_run.stdout}\n{benchmark_run.stderr}"
    assert elapsed >= 0.50, "Benchmark instrumentation did not exercise all three stages."
    assert os.path.isfile(RESULTS_FILE), "The instrumented script did not create results.json."
    with open(RESULTS_FILE) as f:
        benchmark_results = json.load(f)
    assert isinstance(benchmark_results, list) and len(benchmark_results) == 1
    measured = benchmark_results[0].get("inference_time_sec")
    assert isinstance(measured, (int, float)) and not isinstance(measured, bool)
    assert 0.12 <= measured < 0.30, \
        f"inference_time_sec must time exactly predict(); instrumented value was {measured!r}."

    # Remove the verifier's benchmark artifacts, then actually run the submitted
    # script once on each required dataset. This also exercises JSON appending.
    clean_outputs()
    os.remove(benchmark_csv)
    for dataset in DATASETS:
        completed = run_command([VENV_PYTHON, SCRIPT_FILE, dataset])
        assert completed.returncode == 0, \
            f"model_eval.py failed for {dataset}:\n{completed.stdout}\n{completed.stderr}"


def expected_mse(dataset_name):
    path = os.path.join(WORKSPACE_DIR, dataset_name)
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    xs = [float(row["x"]) for row in rows]
    ys = [float(row["y"]) for row in rows]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    denominator = sum((x - x_mean) ** 2 for x in xs)
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / denominator
    intercept = y_mean - slope * x_mean
    predictions = [slope * x + intercept for x in xs]
    return sum((y - prediction) ** 2 for y, prediction in zip(ys, predictions)) / len(ys)


def test_agg_is_configured_before_pyplot_import():
    with open(SCRIPT_FILE) as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_FILE)

    pyplot_line = None
    matplotlib_aliases = {"matplotlib"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "matplotlib":
                    matplotlib_aliases.add(alias.asname or "matplotlib")
                if alias.name == "matplotlib.pyplot":
                    pyplot_line = min(pyplot_line or node.lineno, node.lineno)
        elif isinstance(node, ast.ImportFrom):
            if node.module == "matplotlib" and any(a.name == "pyplot" for a in node.names):
                pyplot_line = min(pyplot_line or node.lineno, node.lineno)
            elif node.module and node.module.startswith("matplotlib.pyplot"):
                pyplot_line = min(pyplot_line or node.lineno, node.lineno)

    assert pyplot_line is not None, "model_eval.py does not import matplotlib.pyplot."
    configured = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or getattr(node, "lineno", 10**9) >= pyplot_line:
            continue
        func = node.func
        if (isinstance(func, ast.Attribute) and func.attr == "use" and
                isinstance(func.value, ast.Name) and func.value.id in matplotlib_aliases and node.args):
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and str(arg.value).lower() == "agg":
                configured = True
    prefix = "\n".join(source.splitlines()[:pyplot_line - 1]).lower()
    if "mplbackend" in prefix and "agg" in prefix:
        configured = True
    assert configured, "Configure the Agg backend before importing matplotlib.pyplot."


def test_results_json_exists_and_valid():
    assert os.path.isfile(RESULTS_FILE), \
        f"Results file {RESULTS_FILE} is missing. Did you run the script and save the output?"
    try:
        with open(RESULTS_FILE) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_FILE} is not valid JSON.")

    assert isinstance(data, list), \
        f"Expected {RESULTS_FILE} to contain a JSON array, but got {type(data).__name__}."
    assert len(data) == 3, \
        f"Expected exactly 3 results in {RESULTS_FILE}, found {len(data)}. Did you append correctly?"


def test_results_json_content():
    with open(RESULTS_FILE) as f:
        data = json.load(f)

    datasets_found = []
    for item in data:
        assert isinstance(item, dict), "Each result must be a JSON object."
        assert "dataset" in item, "Missing 'dataset' key in result object."
        assert "mse" in item, "Missing 'mse' key in result object."
        assert "inference_time_sec" in item, "Missing 'inference_time_sec' key in result object."

        dataset_name = os.path.basename(item["dataset"])
        datasets_found.append(dataset_name)
        assert dataset_name in DATASETS, f"Unexpected dataset name {dataset_name} found in results."

        actual_mse = item["mse"]
        assert isinstance(actual_mse, (int, float)) and not isinstance(actual_mse, bool)
        assert math.isfinite(actual_mse)
        expected = expected_mse(dataset_name)
        assert abs(actual_mse - expected) < 1e-3, \
            f"Incorrect MSE for {dataset_name}. Expected ~{expected}, got {actual_mse}."

        inference_time = item["inference_time_sec"]
        assert isinstance(inference_time, (int, float)) and not isinstance(inference_time, bool)
        assert math.isfinite(inference_time) and inference_time >= 0
        assert inference_time < 0.1, \
            f"Inference time for {dataset_name} is too high ({inference_time}s). It should only measure predict()."

    assert set(datasets_found) == set(DATASETS), \
        f"Missing results for datasets. Found: {datasets_found}"


def assert_valid_png(path):
    with open(path, "rb") as f:
        content = f.read()
    assert content.startswith(b"\x89PNG\r\n\x1a\n"), f"{path} is not a PNG file."
    assert len(content) > 1000, f"{path} is implausibly small for the generated plot."

    offset = 8
    chunks = []
    width = height = 0
    while offset + 12 <= len(content):
        length = struct.unpack(">I", content[offset:offset + 4])[0]
        chunk_type = content[offset + 4:offset + 8]
        end = offset + 12 + length
        assert end <= len(content), f"{path} contains a truncated PNG chunk."
        chunks.append(chunk_type)
        if chunk_type == b"IHDR":
            width, height = struct.unpack(">II", content[offset + 8:offset + 16])
        offset = end
        if chunk_type == b"IEND":
            break
    assert chunks and chunks[0] == b"IHDR"
    assert b"IDAT" in chunks and chunks[-1] == b"IEND"
    assert width > 10 and height > 10, f"{path} has invalid plot dimensions."


def test_plots_exist_and_are_valid_pngs():
    for dataset in DATASETS:
        plot = f"plot_{os.path.splitext(dataset)[0]}.png"
        plot_path = os.path.join(WORKSPACE_DIR, plot)
        assert os.path.isfile(plot_path), f"Plot file {plot_path} is missing."
        assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."
        assert_valid_png(plot_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
