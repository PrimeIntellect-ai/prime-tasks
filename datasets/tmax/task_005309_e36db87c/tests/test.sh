#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import textwrap

PROJECT = "/home/user/mcmc_stat"
RESULTS = "/home/user/test_results.txt"


def run_command(command, timeout=240):
    return subprocess.run(
        command,
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def test_rust_project_exists():
    assert os.path.isfile("/home/user/mcmc_stat/Cargo.toml"), "Cargo.toml is missing. Rust project not created properly."
    assert os.path.isfile("/home/user/mcmc_stat/src/lib.rs"), "src/lib.rs is missing."


def test_run_test_script_exists_and_executable():
    script_path = "/home/user/run_test.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, f"run_test.sh failed:\n{completed.stdout}"
    assert os.path.isfile(RESULTS), "run_test.sh did not freshly generate test_results.txt"


def test_test_results_generated():
    results_path = "/home/user/test_results.txt"
    assert os.path.isfile(results_path), f"{results_path} is missing. Did the script run?"

    with open(results_path, "r") as f:
        content = f.read()

    assert "test_mcmc_analytical_validation" in content, "The test 'test_mcmc_analytical_validation' was not found in the test results."
    assert "test result: ok" in content or "ok" in content.split("test_mcmc_analytical_validation")[1].split("\n")[0], "The Rust test did not pass according to test_results.txt."


def test_cargo_toml_dependencies():
    with open("/home/user/mcmc_stat/Cargo.toml", "r") as f:
        content = f.read()
    assert "rand" in content, "The 'rand' crate is missing from Cargo.toml"
    assert "rand_distr" in content, "The 'rand_distr' crate is missing from Cargo.toml"


def test_required_regression_test_actually_runs():
    completed = run_command(["cargo", "test", "--lib", "test_mcmc_analytical_validation", "--", "--nocapture"])
    assert completed.returncode == 0, f"The required Rust regression test failed:\n{completed.stdout}"
    matching = [
        line for line in completed.stdout.splitlines()
        if "test_mcmc_analytical_validation" in line and line.rstrip().endswith("ok")
    ]
    assert matching, f"No passing test named test_mcmc_analytical_validation was executed:\n{completed.stdout}"


def test_metropolis_hastings_behavior():
    metadata_result = run_command(["cargo", "metadata", "--no-deps", "--format-version", "1"])
    assert metadata_result.returncode == 0, f"cargo metadata failed:\n{metadata_result.stdout}"
    metadata = json.loads(metadata_result.stdout)
    manifest = os.path.realpath(os.path.join(PROJECT, "Cargo.toml"))
    package = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest),
        None,
    )
    assert package is not None, "Could not identify the submitted Cargo package"
    lib_target = next((t for t in package["targets"] if "lib" in t["kind"]), None)
    assert lib_target is not None, "The Cargo project does not define a library target"
    crate_name = lib_target["name"].replace("-", "_")

    tests_dir = os.path.join(PROJECT, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    verifier_test = os.path.join(tests_dir, "__verifier_mcmc_behavior.rs")
    source = f'''use {crate_name}::metropolis_hastings;

fn check_near_sample_mean(data: &[f64], iterations: usize, seed: u64, tolerance: f64) {{
    let expected = data.iter().sum::<f64>() / data.len() as f64;
    let estimate = metropolis_hastings(data, iterations, seed);
    assert!(estimate.is_finite(), "estimate was not finite");
    assert!(
        (estimate - expected).abs() < tolerance,
        "estimate {{estimate}} was not within {{tolerance}} of analytical mean {{expected}}"
    );
}}

#[test]
fn verifier_checks_analytical_posterior_means() {{
    check_near_sample_mean(&[1.2, 2.5, 3.1, 4.0, 2.8], 50_000, 42, 0.1);
    check_near_sample_mean(&[-3.4, -2.8, -3.1, -2.9, -3.3, -2.7], 60_000, 7_391, 0.1);
    check_near_sample_mean(&[6.0, 7.5, 8.25, 6.75, 7.0, 8.5, 7.25, 6.5], 60_000, 91_827, 0.1);
}}

#[test]
fn verifier_checks_seeded_randomness_and_reproducibility() {{
    let data = [-1.0, 0.5, 1.75, 2.0];
    let first = metropolis_hastings(&data, 30_000, 123_456);
    let repeated = metropolis_hastings(&data, 30_000, 123_456);
    let other_seed = metropolis_hastings(&data, 30_000, 654_321);
    assert_eq!(first.to_bits(), repeated.to_bits(), "same seed did not reproduce the same estimate");
    assert!((first - other_seed).abs() > 1e-12, "different seeds produced an identical estimate");
}}
'''
    with open(verifier_test, "w") as f:
        f.write(textwrap.dedent(source))

    completed = run_command(["cargo", "test", "--test", "__verifier_mcmc_behavior", "--", "--nocapture"])
    assert completed.returncode == 0, f"Behavioral tests for metropolis_hastings failed:\n{completed.stdout}"
    assert "2 passed" in completed.stdout, f"Behavioral tests were not both executed:\n{completed.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
