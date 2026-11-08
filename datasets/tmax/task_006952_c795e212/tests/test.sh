#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

EXE = "/home/user/asset_optimizer/optimizer"
SOURCE = "/home/user/asset_optimizer/optimizer.go"
BENCHMARK = "/home/user/benchmark.py"
RESULTS = "/home/user/benchmark_results.json"
FIXTURES = {
    "fixture_1.json": {"max_pixels": 2000000, "min_aspect": 1.3, "max_aspect": 1.4},
    "fixture_2.json": {"max_pixels": 8000000, "min_aspect": 1.7, "max_aspect": 1.8},
    "fixture_3.json": {"max_pixels": 500000, "min_aspect": 1.0, "max_aspect": 1.1},
}
FIXTURE_PATHS = [f"/home/user/fixtures/fixture_{i}.json" for i in range(1, 4)]


def optimal_area(config):
    best = 0
    max_pixels = config["max_pixels"]
    min_aspect = config["min_aspect"]
    max_aspect = config["max_aspect"]

    for width in range(1, 5001):
        height = min(width, max_pixels // width, int(math.floor(width / min_aspect)))
        while height > 0 and (float(width) / float(height)) < min_aspect:
            height -= 1
        if height > 0:
            aspect = float(width) / float(height)
            if min_aspect <= aspect <= max_aspect:
                best = max(best, width * height)
    return best


def parse_and_validate_output(stdout, config):
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Go program output is not valid JSON: {stdout}")

    assert "Width" in data
    assert "Height" in data
    assert "Area" in data
    assert type(data["Width"]) is int
    assert type(data["Height"]) is int
    assert type(data["Area"]) is int

    width = data["Width"]
    height = data["Height"]
    area = data["Area"]
    assert width > 0 and height > 0
    assert width <= 5000
    assert height <= width
    assert area == width * height
    assert area <= config["max_pixels"]
    aspect = float(width) / float(height)
    assert config["min_aspect"] <= aspect <= config["max_aspect"]
    assert area == optimal_area(config), (
        f"Program returned area {area}, but the optimal area is {optimal_area(config)}"
    )
    return data


def run_optimizer(executable, config, timeout=15):
    fd, path = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(config, f)
        try:
            result = subprocess.run(
                [executable, path], capture_output=True, text=True, timeout=timeout
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The Go program timed out, indicating the deadlock was likely not fixed.")
        assert result.returncode == 0, (
            f"Go program failed with return code {result.returncode} and stderr: {result.stderr}"
        )
        return parse_and_validate_output(result.stdout, config)
    finally:
        if os.path.exists(path):
            os.unlink(path)


def validate_results(results, outputs=None):
    assert isinstance(results, list), f"Expected a JSON list, got {type(results)}."
    assert len(results) == 3, f"Expected 3 results, got {len(results)}."

    for i, res in enumerate(results):
        assert "fixture" in res, f"Result {i} missing 'fixture' key."
        assert res["fixture"] == FIXTURE_PATHS[i], (
            f"Result {i} 'fixture' expected {FIXTURE_PATHS[i]}, got {res['fixture']}."
        )
        assert "time_seconds" in res, f"Result {i} missing 'time_seconds' key."
        assert isinstance(res["time_seconds"], float), (
            f"Result {i} 'time_seconds' should be a float."
        )
        assert math.isfinite(res["time_seconds"])
        assert res["time_seconds"] >= 0.0

        assert "optimal_width" in res, f"Result {i} missing 'optimal_width' key."
        assert isinstance(res["optimal_width"], int), (
            f"Result {i} 'optimal_width' should be an int."
        )
        assert "optimal_height" in res, f"Result {i} missing 'optimal_height' key."
        assert isinstance(res["optimal_height"], int), (
            f"Result {i} 'optimal_height' should be an int."
        )
        assert res["optimal_width"] > 0
        assert res["optimal_height"] > 0

        config = FIXTURES[f"fixture_{i + 1}.json"]
        width = res["optimal_width"]
        height = res["optimal_height"]
        assert width <= 5000 and height <= width
        assert width * height <= config["max_pixels"]
        aspect = float(width) / float(height)
        assert config["min_aspect"] <= aspect <= config["max_aspect"]
        assert width * height == optimal_area(config)

        if outputs is not None:
            assert width == outputs[i]["Width"]
            assert height == outputs[i]["Height"]


def test_go_executable_exists():
    """Verify the Go program was built into an executable."""
    assert os.path.isfile(EXE), f"Executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "optimizer is not a compiled Linux executable"


def test_fixtures_exist_and_correct():
    """Verify the fixtures directory and files were created correctly."""
    fixtures_dir = "/home/user/fixtures"
    assert os.path.isdir(fixtures_dir), f"Directory {fixtures_dir} is missing."
    for filename, expected_data in FIXTURES.items():
        filepath = os.path.join(fixtures_dir, filename)
        assert os.path.isfile(filepath), f"Fixture file {filepath} is missing."
        with open(filepath, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Fixture {filepath} is not valid JSON.")
        assert data == expected_data, (
            f"Fixture {filepath} content {data} does not match expected {expected_data}."
        )


def test_go_program_no_deadlock():
    """Verify the Go program runs successfully without deadlocking and is optimal."""
    fixture_path = "/home/user/fixtures/fixture_3.json"
    try:
        result = subprocess.run([EXE, fixture_path], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("The Go program timed out, indicating the deadlock was likely not fixed.")
    assert result.returncode == 0, (
        f"Go program failed with return code {result.returncode} and stderr: {result.stderr}"
    )
    parse_and_validate_output(result.stdout, FIXTURES["fixture_3.json"])


def test_source_builds_and_fixed_program_handles_derived_inputs():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    built = "/tmp/optimizer-built-from-submitted-source"
    build = subprocess.run(
        ["go", "build", "-o", built, SOURCE], capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"optimizer.go does not build: {build.stderr}"

    nonce = secrets.randbelow(500000)
    source_config = {
        "max_pixels": 350000 + nonce,
        "min_aspect": 1.15,
        "max_aspect": 1.31,
    }
    binary_config = {
        "max_pixels": 900000 + secrets.randbelow(700000),
        "min_aspect": 1.42,
        "max_aspect": 1.67,
    }
    run_optimizer(built, source_config)
    run_optimizer(EXE, binary_config)


def test_benchmark_results_json():
    """Verify the existing benchmark report has the required structure and optimal values."""
    assert os.path.isfile(RESULTS), f"Benchmark results file {RESULTS} is missing."
    with open(RESULTS, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")
    validate_results(results)


def test_benchmark_script_generates_fixtures_runs_optimizer_sequentially_and_reports_outputs():
    assert os.path.isfile(BENCHMARK), f"Benchmark script {BENCHMARK} is missing."

    with open(BENCHMARK, "r") as f:
        tree = ast.parse(f.read(), filename=BENCHMARK)
    subprocess_aliases = set()
    subprocess_functions = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess":
                    subprocess_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            for alias in node.names:
                subprocess_functions.add(alias.asname or alias.name)
    uses_subprocess = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            if node.func.value.id in subprocess_aliases:
                uses_subprocess = True
        elif isinstance(node.func, ast.Name) and node.func.id in subprocess_functions:
            uses_subprocess = True
    assert uses_subprocess, "benchmark.py must use subprocess to run the optimizer"

    backup = EXE + ".verifier-real"
    log_path = "/tmp/benchmark-invocations.log"
    if os.path.exists(backup):
        os.unlink(backup)
    if os.path.exists(log_path):
        os.unlink(log_path)

    shutil.rmtree("/home/user/fixtures", ignore_errors=True)
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)

    os.replace(EXE, backup)
    wrapper = f'''#!/bin/bash
printf 'START\\t%s\\n' "$1" >> {log_path}
out=$("{backup}" "$@")
status=$?
printf 'END\\t%s\\t%s\\n' "$1" "$out" >> {log_path}
printf '%s\\n' "$out"
exit $status
'''
    try:
        with open(EXE, "w") as f:
            f.write(wrapper)
        os.chmod(EXE, 0o755)
        result = subprocess.run(
            ["python3", BENCHMARK], capture_output=True, text=True, timeout=90
        )
        assert result.returncode == 0, (
            f"benchmark.py failed with return code {result.returncode}: {result.stderr}"
        )
    finally:
        if os.path.exists(EXE):
            os.unlink(EXE)
        os.replace(backup, EXE)

    assert os.path.isdir("/home/user/fixtures")
    for filename, expected in FIXTURES.items():
        path = os.path.join("/home/user/fixtures", filename)
        assert os.path.isfile(path)
        with open(path, "r") as f:
            assert json.load(f) == expected

    assert os.path.isfile(log_path), "benchmark.py did not invoke the required executable"
    with open(log_path, "r") as f:
        events = [line.rstrip("\n") for line in f if line.strip()]
    assert len(events) == 6, f"Expected exactly three optimizer invocations, got: {events}"

    outputs = []
    for i, expected_path in enumerate(FIXTURE_PATHS):
        start = events[2 * i].split("\t", 1)
        end = events[2 * i + 1].split("\t", 2)
        assert start == ["START", expected_path], f"Optimizer calls were not sequential: {events}"
        assert len(end) == 3 and end[0] == "END" and end[1] == expected_path
        output = parse_and_validate_output(end[2], FIXTURES[f"fixture_{i + 1}.json"])
        outputs.append(output)

    assert os.path.isfile(RESULTS), "benchmark.py did not create benchmark_results.json"
    with open(RESULTS, "r") as f:
        results = json.load(f)
    validate_results(results, outputs=outputs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
