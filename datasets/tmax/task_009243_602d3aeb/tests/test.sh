#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import secrets
import subprocess

import pytest

SCRIPT_PATH = Path("/home/user/run_workflow.sh")
WORKFLOW_PATH = Path("/home/user/workflow.json")
RESULTS_PATH = Path("/home/user/results.json")
SOLVER_PATH = Path("/home/user/solver")

CANONICAL_EXPERIMENTS = [
    {"id": "exp1", "c": 1.0},
    {"id": "exp2", "c": 2.0},
    {"id": "exp3", "c": 5.0},
    {"id": "exp4", "c": 10.0},
]


def write_workflow(experiments):
    WORKFLOW_PATH.write_text(json.dumps({"experiments": experiments}, indent=2) + "\n")


def expected_root(c):
    def f(x):
        return x ** 3 - math.cos(x) - c

    lo = 0.0
    hi = 1.0
    while f(hi) < 0.0:
        hi *= 2.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if f(mid) < 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def validate_results(experiments):
    assert RESULTS_PATH.exists(), f"Results file not found: {RESULTS_PATH}"
    try:
        results = json.loads(RESULTS_PATH.read_text())
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_PATH} is not valid JSON")

    assert isinstance(results, dict), "results.json must contain a JSON object"
    for experiment in experiments:
        key = experiment["id"]
        assert key in results, f"Missing key '{key}' in results.json"
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), \
            f"Value for '{key}' is not a number"
        assert math.isfinite(results[key]), f"Value for '{key}' is not finite"
        expected = expected_root(float(experiment["c"]))
        assert abs(float(results[key]) - expected) < 1e-5, \
            f"Value for {key} is incorrect: {results[key]} != {expected} (expected)"


def run_script(experiments):
    write_workflow(experiments)
    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()
    result = subprocess.run(
        [str(SCRIPT_PATH)], capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, \
        f"Script failed to execute successfully. stderr: {result.stderr}"
    validate_results(experiments)


def test_complete_workflow_and_rust_program():
    assert SCRIPT_PATH.exists(), f"Script not found: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"

    cargo_path = SOLVER_PATH / "Cargo.toml"
    assert cargo_path.exists(), f"Cargo.toml not found at {cargo_path}"
    cargo_contents = cargo_path.read_text()
    assert "rayon" in cargo_contents, "rayon crate is missing from Cargo.toml"

    src_dir = SOLVER_PATH / "src"
    assert src_dir.exists() and src_dir.is_dir(), \
        f"Rust source directory not found at {src_dir}"
    found_par = False
    for root, _, files in os.walk(src_dir):
        for filename in files:
            if filename.endswith(".rs"):
                content = Path(root, filename).read_text()
                if "par_iter" in content or "into_par_iter" in content or "par_bridge" in content:
                    found_par = True
                    break
        if found_par:
            break
    assert found_par, \
        "No parallel iteration (e.g., par_iter, into_par_iter) found in Rust source code"

    # Preserve the original end-to-end check on the instructed notebook.
    run_script(CANONICAL_EXPERIMENTS)

    nonce = secrets.token_hex(6)
    dynamic_experiments = [
        {"id": f"dynamic_{nonce}_{i}", "c": 0.25 + secrets.randbelow(20000) / 1000.0}
        for i in range(6)
    ]

    try:
        # Exercise the orchestration script on unpredictable inputs, preventing
        # a precomputed results.json or hardcoded canonical output from passing.
        run_script(dynamic_experiments)

        # Build and directly execute an actual release-mode Rust binary from the
        # submitted Cargo project on a second unpredictable notebook.
        build = subprocess.run(
            ["cargo", "build", "--release", "--manifest-path", str(cargo_path)],
            cwd=str(SOLVER_PATH), capture_output=True, text=True, timeout=180
        )
        assert build.returncode == 0, f"Cargo release build failed: {build.stderr}"

        metadata_result = subprocess.run(
            ["cargo", "metadata", "--no-deps", "--format-version", "1",
             "--manifest-path", str(cargo_path)],
            cwd=str(SOLVER_PATH), capture_output=True, text=True, timeout=60
        )
        assert metadata_result.returncode == 0, \
            f"Unable to inspect Cargo targets: {metadata_result.stderr}"
        metadata = json.loads(metadata_result.stdout)
        target_dir = Path(metadata["target_directory"])
        bin_names = []
        for package in metadata["packages"]:
            if Path(package["manifest_path"]).resolve() == cargo_path.resolve():
                for target in package["targets"]:
                    if "bin" in target["kind"]:
                        bin_names.append(target["name"])
        assert bin_names, "The Rust project has no binary target"

        direct_experiments = [
            {"id": f"rust_{nonce}_{i}", "c": 0.4 + secrets.randbelow(15000) / 1000.0}
            for i in range(5)
        ]
        write_workflow(direct_experiments)
        rust_binary_passed = False
        diagnostics = []
        for name in bin_names:
            binary = target_dir / "release" / name
            if not binary.exists() or not os.access(binary, os.X_OK):
                diagnostics.append(f"missing executable {binary}")
                continue
            if RESULTS_PATH.exists():
                RESULTS_PATH.unlink()
            execution = subprocess.run(
                [str(binary)], cwd=str(SOLVER_PATH), capture_output=True,
                text=True, timeout=120
            )
            if execution.returncode != 0:
                diagnostics.append(f"{binary}: {execution.stderr}")
                continue
            try:
                validate_results(direct_experiments)
                rust_binary_passed = True
                break
            except AssertionError as exc:
                diagnostics.append(f"{binary}: {exc}")
        assert rust_binary_passed, \
            "No release-mode Rust binary produced correct results: " + "; ".join(diagnostics)
    finally:
        write_workflow(CANONICAL_EXPERIMENTS)

    # Leave the requested canonical results in place and recheck them.
    run_script(CANONICAL_EXPERIMENTS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
