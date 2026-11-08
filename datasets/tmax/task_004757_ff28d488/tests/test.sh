#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
GO_FILE = os.path.join(HOME, "analyze.go")
GO_MOD = os.path.join(HOME, "go.mod")
CSV_FILE = os.path.join(HOME, "data", "sensor_data.csv")
RESULTS_FILE = os.path.join(HOME, "results.json")
EXPECTED_KEYS = {"clean_row_count", "correlation_f1_f2", "max_eigenvalue"}


def run_program():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    completed = subprocess.run(
        ["go", "run", "analyze.go"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "go run analyze.go failed:\n"
        + completed.stdout
        + completed.stderr
    )
    assert os.path.isfile(RESULTS_FILE), (
        f"File {RESULTS_FILE} does not exist. The Go program must generate this file."
    )
    try:
        with open(RESULTS_FILE, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{RESULTS_FILE} is not a valid JSON file.")
    except Exception as exc:
        pytest.fail(f"Failed to read {RESULTS_FILE}: {exc}")


def assert_result_shape(data):
    assert isinstance(data, dict), "results.json must contain a JSON object"
    missing_keys = EXPECTED_KEYS - set(data.keys())
    assert not missing_keys, f"results.json is missing expected keys: {missing_keys}"
    assert isinstance(data.get("clean_row_count"), int), (
        f"clean_row_count must be an integer, got {type(data.get('clean_row_count'))}"
    )
    assert isinstance(data.get("correlation_f1_f2"), (int, float)), (
        "correlation_f1_f2 must be a number, got "
        f"{type(data.get('correlation_f1_f2'))}"
    )
    assert isinstance(data.get("max_eigenvalue"), (int, float)), (
        f"max_eigenvalue must be a number, got {type(data.get('max_eigenvalue'))}"
    )


def test_analyze_go_exists_and_uses_required_module():
    assert os.path.isfile(GO_FILE), (
        f"File {GO_FILE} does not exist. You must write your Go program here."
    )
    assert os.path.getsize(GO_FILE) > 0, f"File {GO_FILE} is empty"
    assert os.path.isfile(GO_MOD), "The required Go module was not initialized"

    with open(GO_MOD, "r") as f:
        module_text = f.read()
    assert any(
        line.strip() == "module sensor_analysis" for line in module_text.splitlines()
    ), "go.mod must declare module sensor_analysis"

    listed = subprocess.run(
        ["go", "list", "-deps", "analyze.go"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert listed.returncode == 0, "The Go program does not compile:\n" + listed.stderr
    assert any(
        line.startswith("gonum.org/v1/gonum/")
        for line in listed.stdout.splitlines()
    ), "analyze.go must import and use the gonum.org/v1/gonum library"


def test_program_executes_and_analyzes_input():
    with open(CSV_FILE, "r") as f:
        original_csv = f.read()

    try:
        # Execute the submitted artifact against the supplied dataset before
        # checking all of the original verifier's expected values.
        original = run_program()
        assert_result_shape(original)
        assert original["clean_row_count"] == 8, (
            f"Expected 8 clean rows, got {original['clean_row_count']}"
        )
        assert round(original["correlation_f1_f2"], 4) == 0.9944, (
            "Expected correlation_f1_f2 to be approx 0.9944, got "
            f"{original['correlation_f1_f2']}"
        )
        assert round(original["max_eigenvalue"], 4) == 0.5369, (
            "Expected max_eigenvalue to be approx 0.5369, got "
            f"{original['max_eigenvalue']}"
        )

        # Apply an unpredictable affine transformation to every valid row.
        # Correlation and clean-row count are invariant, while every covariance
        # eigenvalue is multiplied by scale^2. Invalid rows remain sentinels.
        scale = 1.5 + secrets.randbelow(1000001) / 1000000.0
        offsets = [
            (secrets.randbelow(2000001) - 1000000) / 10000.0
            for _ in range(4)
        ]
        lines = original_csv.strip().splitlines()
        transformed = [lines[0]]
        for line in lines[1:]:
            fields = line.split(",")
            values = [float(field) for field in fields]
            if any(value == -9999.0 for value in values):
                transformed.append(line)
            else:
                transformed.append(",".join(
                    f"{value * scale + offsets[index]:.10f}"
                    for index, value in enumerate(values)
                ))

        # Extra corrupt rows ensure they cannot contribute to the analysis.
        for sentinel_column in range(4):
            values = [
                (secrets.randbelow(2000001) - 1000000) / 1000.0
                for _ in range(4)
            ]
            values[sentinel_column] = -9999.0
            transformed.append(",".join(str(value) for value in values))

        with open(CSV_FILE, "w") as f:
            f.write("\n".join(transformed) + "\n")

        changed = run_program()
        assert_result_shape(changed)
        assert changed["clean_row_count"] == 8, (
            "Rows containing -9999 must be excluded; expected 8 clean rows, got "
            f"{changed['clean_row_count']}"
        )
        assert round(changed["correlation_f1_f2"], 4) == 0.9944, (
            "Correlation should be invariant under the generated positive affine "
            f"transformation, got {changed['correlation_f1_f2']}"
        )

        # The original rounded value represents an underlying value within
        # 0.00005. Include that uncertainty and the transformed output's own
        # four-decimal rounding error.
        expected_eigenvalue = 0.5369 * scale * scale
        tolerance = 0.00005 * scale * scale + 0.000051
        assert abs(changed["max_eigenvalue"] - expected_eigenvalue) <= tolerance, (
            "max_eigenvalue did not respond to the generated input transformation: "
            f"expected approximately {expected_eigenvalue:.4f}, got "
            f"{changed['max_eigenvalue']}"
        )
    finally:
        with open(CSV_FILE, "w") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
