#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

PROJECT = "/home/user/sim_solver"


def expected_output():
    # Independently derive the real root of x^3 - 2x + 2 by bisection.
    lo, hi = -2.0, -1.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        value = mid ** 3 - 2.0 * mid + 2.0
        if value < 0:
            lo = mid
        else:
            hi = mid
    root = (lo + hi) / 2.0
    return f"Converged root: {root:.6f}\n"


@pytest.fixture(scope="session")
def cargo_result():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    try:
        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("cargo run timed out")

    assert result.returncode == 0, (
        "cargo run failed:\n" + result.stderr.decode("utf-8", errors="replace")
    )
    return result


def test_cargo_config_fixed():
    config_path = "/home/user/sim_solver/.cargo/config.toml"
    if os.path.exists(config_path):
        with open(config_path, "r") as f:
            content = f.read()
        assert "link-arg=-lnonexistent_legacy_math_lib" not in content, "The bad linker flag is still present in .cargo/config.toml"


def test_main_rs_fixed():
    main_rs_path = "/home/user/sim_solver/src/main.rs"
    assert os.path.isfile(main_rs_path), f"{main_rs_path} is missing"

    with open(main_rs_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "-2.0" in content, "The initial guess in src/main.rs was not updated to -2.0"
    assert "let mut x: f64 = 0.0;" not in content, "The buggy initial guess of 0.0 is still in src/main.rs"

    # Ensure -2.0 is the executable initializer, rather than text in a comment.
    uncommented = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)
    assert re.search(
        r"\blet\s+mut\s+x\s*:\s*f64\s*=\s*-2(?:\.0+)?\s*;",
        uncommented,
    ), "The executable initial guess declaration is not set to -2.0"


def test_project_builds_and_converges(cargo_result):
    expected = expected_output().encode("utf-8")
    assert cargo_result.stdout == expected, (
        "cargo run must print exactly one convergence line; got: "
        + repr(cargo_result.stdout.decode("utf-8", errors="replace"))
    )

    match = re.fullmatch(rb"Converged root: (-?\d+\.\d{6})\n", cargo_result.stdout)
    assert match is not None, "Program output is not a single correctly formatted convergence line"
    root = float(match.group(1))
    assert abs(root ** 3 - 2.0 * root + 2.0) < 5e-6, "Reported value is not a root of the equation"


def test_diagnostics_log_contains_correct_output(cargo_result):
    log_path = "/home/user/diagnostics.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. Did you save the output of cargo run?"

    with open(log_path, "rb") as f:
        log_content = f.read()

    # Preserve the original expected-output assertion.
    assert b"Converged root: -1.769292" in log_content, "The diagnostics.log does not contain the expected convergence output."

    # The saved log must be exactly the stdout produced by a fresh successful run.
    assert log_content == cargo_result.stdout, "diagnostics.log is not the exact stdout of cargo run"
    assert log_content == expected_output().encode("utf-8"), "diagnostics.log must contain exactly one correct output line"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
