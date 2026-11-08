#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import random
import shutil
import subprocess
import tempfile
import pytest


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_pipeline_execution_and_output():
    script_path = "/home/user/pipeline.sh"
    result_path = "/home/user/result.json"

    # Remove result.json if it exists to ensure the script generates it
    if os.path.exists(result_path):
        os.remove(result_path)

    # Execute the pipeline script
    result = subprocess.run(
        [script_path], capture_output=True, text=True, cwd="/home/user", timeout=180
    )
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}. stderr: {result.stderr}"

    # Check if result.json was created
    assert os.path.isfile(result_path), f"The pipeline script did not generate {result_path}."

    # Read and verify the JSON output
    with open(result_path, 'r') as f:
        try:
            coeffs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{result_path} does not contain valid JSON.")

    assert isinstance(coeffs, list), f"Expected a JSON array in {result_path}, got {type(coeffs)}."
    assert len(coeffs) == 3, f"Expected exactly 3 coefficients in {result_path}, got {len(coeffs)}."

    expected = [0.14000000, 0.94142857, 1.00714286]

    for c, e in zip(coeffs, expected):
        assert isinstance(c, (int, float)), f"Coefficient {c} is not a number."
        assert math.isclose(c, e, rel_tol=1e-3, abs_tol=1e-3), \
            f"Mismatch in coefficients: got {coeffs}, expected approximately {expected}."


def test_rust_project_structure():
    cargo_toml = "/home/user/polyfit/Cargo.toml"
    src_main = "/home/user/polyfit/src/main.rs"

    assert os.path.isfile(cargo_toml), f"Rust project file {cargo_toml} does not exist."
    assert os.path.isfile(src_main), f"Rust source file {src_main} does not exist."


def solve_3x3(matrix, vector):
    augmented = [list(matrix[i]) + [vector[i]] for i in range(3)]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda row: abs(augmented[row][col]))
        assert abs(augmented[pivot][col]) > 1e-12, "Verifier generated a singular test case."
        augmented[col], augmented[pivot] = augmented[pivot], augmented[col]
        divisor = augmented[col][col]
        for j in range(col, 4):
            augmented[col][j] /= divisor
        for row in range(3):
            if row == col:
                continue
            factor = augmented[row][col]
            for j in range(col, 4):
                augmented[row][j] -= factor * augmented[col][j]
    return [augmented[i][3] for i in range(3)]


def expected_least_squares(rows):
    ata = [[0.0] * 3 for _ in range(3)]
    aty = [0.0] * 3
    for x, y in rows:
        design = [1.0, x, x * x]
        for i in range(3):
            aty[i] += design[i] * y
            for j in range(3):
                ata[i][j] += design[i] * design[j]
    return solve_3x3(ata, aty)


def read_coefficients(path):
    assert os.path.isfile(path), f"Compiled Rust binary did not generate {path}."
    with open(path, "r") as handle:
        try:
            coeffs = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")
    assert isinstance(coeffs, list), "Rust binary output must be a JSON array."
    assert len(coeffs) == 3, "Rust binary output must contain exactly three coefficients."
    for coefficient in coeffs:
        assert isinstance(coefficient, (int, float)) and not isinstance(coefficient, bool), \
            f"Coefficient {coefficient!r} is not numeric."
        assert math.isfinite(coefficient), f"Coefficient {coefficient!r} is not finite."
    return coeffs


def test_compiled_rust_binary_solves_unseen_datasets():
    project = "/home/user/polyfit"
    dataset_path = "/home/user/dataset.csv"
    result_path = "/home/user/result.json"
    target_dir = tempfile.mkdtemp(prefix="polyfit-verifier-target-")

    with open(dataset_path, "rb") as handle:
        original_dataset = handle.read()
    original_result = None
    if os.path.exists(result_path):
        with open(result_path, "rb") as handle:
            original_result = handle.read()

    env = os.environ.copy()
    env["RUSTUP_HOME"] = "/opt/rust"
    env["CARGO_HOME"] = "/opt/cargo"
    env["CARGO_TARGET_DIR"] = target_dir
    env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")
    env.pop("RUSTC_WRAPPER", None)
    env.pop("CARGO_BUILD_RUSTC_WRAPPER", None)

    try:
        # Build the submitted project ourselves in a fresh target directory, so a
        # placeholder project plus a shell script that writes constants cannot pass.
        build = subprocess.run(
            ["/opt/cargo/bin/cargo", "build", "--release", "--message-format=json"],
            cwd=project, env=env, capture_output=True, text=True, timeout=240
        )
        assert build.returncode == 0, \
            f"The Rust project did not compile in release mode. stderr: {build.stderr}"

        executables = []
        for line in build.stdout.splitlines():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            target = message.get("target", {})
            executable = message.get("executable")
            if message.get("reason") == "compiler-artifact" and executable and "bin" in target.get("kind", []):
                executables.append(executable)
        assert executables, "Cargo did not produce a Rust binary target."
        binary = executables[-1]
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
            "Cargo's release artifact is not an executable file."

        rng = random.SystemRandom()
        for count in (9, 14):
            true_coeffs = [rng.uniform(-3.0, 3.0), rng.uniform(-2.0, 2.0), rng.uniform(-1.2, 1.2)]
            xs = sorted(rng.uniform(-4.5, 5.5) for _ in range(count))
            rows = []
            for x in xs:
                y = true_coeffs[0] + true_coeffs[1] * x + true_coeffs[2] * x * x + rng.uniform(-0.35, 0.35)
                # Derive expectations from exactly the decimal values written to CSV.
                rows.append((float(f"{x:.12g}"), float(f"{y:.12g}")))

            with open(dataset_path, "w") as handle:
                handle.write("x,y\n")
                for x, y in rows:
                    handle.write(f"{x:.12g},{y:.12g}\n")
            if os.path.exists(result_path):
                os.remove(result_path)

            run = subprocess.run(
                [binary], cwd=project, env=env, capture_output=True, text=True, timeout=60
            )
            assert run.returncode == 0, \
                f"Compiled Rust binary failed on an unseen dataset. stderr: {run.stderr}"
            actual = read_coefficients(result_path)
            expected = expected_least_squares(rows)
            for coefficient, wanted in zip(actual, expected):
                assert math.isclose(coefficient, wanted, rel_tol=2e-3, abs_tol=2e-3), \
                    f"Rust binary returned {actual}; expected approximately {expected}."
    finally:
        with open(dataset_path, "wb") as handle:
            handle.write(original_dataset)
        if original_result is None:
            if os.path.exists(result_path):
                os.remove(result_path)
        else:
            with open(result_path, "wb") as handle:
                handle.write(original_result)
        shutil.rmtree(target_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
