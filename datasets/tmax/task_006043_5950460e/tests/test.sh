#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import pytest


def test_recovered_secret():
    secret_path = "/home/user/recovered_secret.txt"
    assert os.path.exists(secret_path), f"{secret_path} does not exist."

    with open(secret_path, 'r') as f:
        content = f.read()

    assert content == "vlt_892nf8923nf8923f", "The recovered secret is incorrect or contains extra whitespace/newlines."


def test_yield_result():
    result_path = "/home/user/yield_result.txt"
    assert os.path.exists(result_path), f"{result_path} does not exist."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    # 500000 * (10000 + (450 * 5)) / 10000 = 612500
    assert content == "612500", "The calculated yield result is incorrect."


def test_lib_rs_fixed():
    lib_path = "/home/user/yield-calculator/src/lib.rs"
    assert os.path.exists(lib_path), f"{lib_path} does not exist."

    with open(lib_path, 'r') as f:
        content = f.read()

    # Check that the buggy formula is gone
    assert "(principal * 10000 + rate_bps) * time_years / 10000" not in content, "The buggy formula is still present in src/lib.rs."

    # Run cargo test if possible to ensure it compiles and passes
    repo_path = "/home/user/yield-calculator"
    env = os.environ.copy()
    env["VAULT_SECRET"] = "vlt_892nf8923nf8923f"

    try:
        result = subprocess.run(
            ["cargo", "test"],
            cwd=repo_path,
            env=env,
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Cargo tests failed:\n{result.stdout}\n{result.stderr}"
    except FileNotFoundError:
        # If cargo is not installed in the test environment, fallback to a simple string check
        assert "principal * (10000 + (rate_bps * time_years)) / 10000" in content.replace(" ", ""), "The corrected formula was not found in src/lib.rs."


def test_calculate_yield_on_derived_inputs():
    repo_path = "/home/user/yield-calculator"
    tests_dir = os.path.join(repo_path, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    generated_test = os.path.join(tests_dir, "verifier_dynamic.rs")

    # Keep products comfortably within u64 while varying all arguments. The
    # expected values are independently derived here and embedded only after
    # the agent has finished.
    cases = [
        (0, 731, 9),
        (1, 1, 1),
        (9999, 0, 37),
        (1234567, 333, 0),
        (17, 123, 7),
        (987654321, 4321, 19),
    ]
    for _ in range(24):
        principal = secrets.randbelow(1_000_000_000)
        rate_bps = secrets.randbelow(5_001)
        time_years = secrets.randbelow(51)
        cases.append((principal, rate_bps, time_years))

    assertions = []
    for principal, rate_bps, time_years in cases:
        expected = principal * (10000 + rate_bps * time_years) // 10000
        assertions.append(
            f"    assert_eq!(calculate_yield({principal}u64, {rate_bps}u64, {time_years}u64), {expected}u64);"
        )

    source = (
        "use yield_calculator::calculate_yield;\n\n"
        "#[test]\n"
        "fn verifier_checks_formula_for_many_inputs() {\n"
        + "\n".join(assertions)
        + "\n}\n"
    )
    with open(generated_test, "w") as f:
        f.write(source)

    env = os.environ.copy()
    env["VAULT_SECRET"] = "vlt_892nf8923nf8923f"
    try:
        result = subprocess.run(
            ["cargo", "test", "--test", "verifier_dynamic"],
            cwd=repo_path,
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Dynamic formula tests failed:\n{result.stdout}\n{result.stderr}"
    finally:
        try:
            os.remove(generated_test)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
