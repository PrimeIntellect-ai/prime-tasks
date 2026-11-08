#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/trade_analyzer"
VWAP_SOURCE = os.path.join(PROJECT_DIR, "src", "vwap.rs")


def run_command(args, cwd=None, timeout=60):
    try:
        return subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        pytest.fail(f"Command not found: {args[0]}")


def test_forensics_report():
    report_path = "/home/user/forensics_report.txt"
    assert os.path.exists(report_path), f"Report file missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Report file {report_path} must contain at least 2 lines."
    assert lines[0] == "TX-99842", f"Line 1 of report should be exactly 'TX-99842', got '{lines[0]}'."
    assert lines[1] in ["0", "0.0"], f"Line 2 of report should be '0' or '0.0', got '{lines[1]}'."


def test_project_and_dependency_are_valid():
    assert os.path.isdir(PROJECT_DIR), f"Project directory missing at {PROJECT_DIR}"
    assert os.path.isfile(VWAP_SOURCE), f"VWAP source missing at {VWAP_SOURCE}"
    assert stat.S_ISREG(os.stat(VWAP_SOURCE).st_mode), f"{VWAP_SOURCE} must be a regular file"

    result = run_command(
        ["cargo", "metadata", "--format-version", "1"],
        cwd=PROJECT_DIR,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Cargo dependency resolution failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    metadata = json.loads(result.stdout)
    manifest = os.path.realpath(os.path.join(PROJECT_DIR, "Cargo.toml"))
    roots = [
        package for package in metadata.get("packages", [])
        if os.path.realpath(package.get("manifest_path", "")) == manifest
    ]
    assert len(roots) == 1, "Could not identify the trade_analyzer root package"
    assert any(dep.get("name") == "thiserror" for dep in roots[0].get("dependencies", [])), (
        "Cargo.toml must retain a resolvable thiserror dependency"
    )
    assert any(package.get("name") == "thiserror" for package in metadata.get("packages", [])), (
        "The thiserror crate was not resolved"
    )


def test_cargo_test_passes():
    assert os.path.exists(PROJECT_DIR), f"Project directory missing at {PROJECT_DIR}"

    result = run_command(["cargo", "test"], cwd=PROJECT_DIR, timeout=60)
    assert result.returncode == 0, (
        f"`cargo test` failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_calculate_vwap_on_independent_inputs():
    # Compile the submitted vwap.rs directly into a verifier-owned harness. Cases
    # are generated at verification time, so repository tests cannot be deleted or
    # tailored to a fixed transaction to satisfy this check.
    rng = random.SystemRandom()
    cases = []
    for _ in range(24):
        trades = []
        for _ in range(rng.randint(1, 8)):
            price = rng.randint(1, 200000) / 20.0
            volume = rng.randint(0, 5000)
            trades.append((price, volume))
        if not any(volume for _, volume in trades):
            price, _ = trades[0]
            trades[0] = (price, rng.randint(1, 5000))
        total_volume = sum(volume for _, volume in trades)
        expected = sum(price * volume for price, volume in trades) / total_volume
        cases.append((trades, expected))

    checks = []
    zero_prices = [rng.randint(1, 200000) / 20.0 for _ in range(5)]
    zero_trades = ", ".join(
        f"submitted::Trade {{ price: {price!r}, volume: 0u32 }}"
        for price in zero_prices
    )
    checks.append(
        "{ let trades = vec![" + zero_trades + "]; "
        "let got = submitted::calculate_vwap(&trades); "
        "assert!(got == 0.0, \"all-zero-volume input returned {:?}\", got); }"
    )
    checks.append(
        "{ let trades: Vec<submitted::Trade> = vec![]; "
        "let got = submitted::calculate_vwap(&trades); "
        "assert!(got == 0.0, \"empty input returned {:?}\", got); }"
    )

    for index, (trades, expected) in enumerate(cases):
        rust_trades = ", ".join(
            f"submitted::Trade {{ price: {price!r}, volume: {volume}u32 }}"
            for price, volume in trades
        )
        checks.append(
            "{ let trades = vec![" + rust_trades + "]; "
            "let got = submitted::calculate_vwap(&trades); "
            f"let expected: f64 = {expected!r}; "
            f"assert!((got - expected).abs() <= 1e-10_f64 * expected.abs().max(1.0), "
            f"\"case {index}: expected {{:?}}, got {{:?}}\", expected, got); }}"
        )

    harness = f'''#[path = "{VWAP_SOURCE}"]
mod submitted;

fn main() {{
    {chr(10).join(checks)}
}}
'''

    with tempfile.TemporaryDirectory(prefix="vwap_verifier_") as temp_dir:
        harness_path = os.path.join(temp_dir, "harness.rs")
        binary_path = os.path.join(temp_dir, "harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        compiled = run_command(
            ["rustc", "--edition=2021", harness_path, "-o", binary_path],
            timeout=60,
        )
        assert compiled.returncode == 0, (
            f"Could not compile submitted src/vwap.rs in the independent harness.\n"
            f"STDOUT:\n{compiled.stdout}\nSTDERR:\n{compiled.stderr}"
        )

        executed = run_command([binary_path], timeout=30)
        assert executed.returncode == 0, (
            f"calculate_vwap failed independent behavioral checks.\n"
            f"STDOUT:\n{executed.stdout}\nSTDERR:\n{executed.stderr}"
        )


def test_cargo_run_output():
    result = run_command(
        ["cargo", "run", "--", "--tx", "TX-99842"],
        cwd=PROJECT_DIR,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"`cargo run` failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    output = result.stdout.strip()
    assert output in ["0", "0.0"], f"Expected output '0' or '0.0' for TX-99842, got '{output}'"

    with open("/home/user/forensics_report.txt", "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines[1] == output, "Report line 2 must contain the numerical output produced by the CLI"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
