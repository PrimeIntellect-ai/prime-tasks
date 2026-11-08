#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path("/home/user/sim_tracker")


def run(cmd, **kwargs):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)
    except FileNotFoundError as exc:
        pytest.fail(f"Required command not found: {exc}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {' '.join(map(str, cmd))}")


@pytest.fixture(scope="session")
def vulnerable_runs():
    """Run the submitted CLI wrapper against the original vulnerable library."""
    main_rs = PROJECT / "src/main.rs"
    assert main_rs.is_file(), f"File {main_rs} does not exist."

    temp = Path(tempfile.mkdtemp(prefix="vulnerable_sim_"))
    src = temp / "src"
    src.mkdir()
    (temp / "Cargo.toml").write_text(
        '[package]\nname = "sim_tracker"\nversion = "0.1.0"\nedition = "2021"\n'
    )
    shutil.copyfile(main_rs, src / "main.rs")
    (src / "lib.rs").write_text(r'''pub fn run_simulation(seed: u64) -> Result<f64, String> {
    let mut state: f32 = 1000.0;
    let perturbation = (seed % 15) as f32;

    for i in 0..50000 {
        let step = 1.0 / (perturbation + i as f32 + 1.0);
        let previous_state = state;
        state += step;
        if state == previous_state {
            return Err(format!("Numerical instability detected at iteration {}", i));
        }
    }

    Ok(state as f64)
}
''')

    built = run(["cargo", "build", "--quiet"], cwd=temp)
    assert built.returncode == 0, (
        "The submitted diagnostic wrapper does not compile against the original API.\n"
        f"Stderr: {built.stderr}\nStdout: {built.stdout}"
    )

    binary = temp / "target/debug/sim_tracker"
    results = {}
    for seed in range(1, 101):
        result = run([str(binary), str(seed)], cwd=temp)
        results[seed] = result
    return results


def test_failing_seed_file(vulnerable_runs):
    path = Path("/home/user/failing_seed.txt")
    assert path.is_file(), f"File {path} does not exist. Did you save the failing seed?"
    content = path.read_text().strip()

    failures = [
        seed for seed, result in vulnerable_runs.items()
        if result.returncode != 0
        or "Numerical instability detected" in result.stderr
        or "Numerical instability detected" in result.stdout
    ]
    assert failures, "The diagnostic wrapper did not expose the original instability."
    expected = min(failures)
    assert expected == 1, f"Expected the original simulation's first failing seed to be 1, got {expected}."
    assert content == str(expected), (
        f"Expected the first failing seed to be '{expected}', but got '{content}'."
    )


def test_error_trace_log(vulnerable_runs):
    path = Path("/home/user/error_trace.log")
    assert path.is_file(), f"File {path} does not exist. Did you save the stderr output?"
    content = path.read_text()
    assert "Numerical instability detected" in content, (
        "The error trace log does not contain the expected error message "
        "'Numerical instability detected'."
    )

    actual = vulnerable_runs[1].stderr
    assert actual, "The submitted wrapper did not emit the original failure on stderr."
    expected_messages = re.findall(
        r"Numerical instability detected at iteration \d+", actual
    )
    logged_messages = re.findall(
        r"Numerical instability detected at iteration \d+", content
    )
    assert expected_messages, "Could not derive the original numerical-instability diagnostic."
    assert logged_messages == expected_messages, (
        "error_trace.log does not contain the exact numerical-instability diagnostic "
        "emitted by the failing run."
    )
    # A direct binary capture is exact. A `cargo run` capture may prepend Cargo's
    # own status lines, but its stderr must end with the program's exact stderr.
    assert content == actual or content.endswith(actual), (
        "error_trace.log is not the stderr produced by the failing diagnostic run."
    )


def test_lib_rs_uses_f64_and_computes_the_simulation():
    lib = PROJECT / "src/lib.rs"
    assert lib.is_file(), f"File {lib} does not exist."
    content = lib.read_text()
    assert "f64" in content, "Expected to find 'f64' in src/lib.rs to fix the precision loss."

    harness = Path("/tmp/verify_precision.rs")
    harness.write_text(r'''#[path = "/home/user/sim_tracker/src/lib.rs"]
mod submitted;

fn reference(seed: u64) -> f64 {
    let mut state: f64 = 1000.0;
    let perturbation = (seed % 15) as f64;
    for i in 0..50000 {
        let step = 1.0 / (perturbation + i as f64 + 1.0);
        state += step;
    }
    state
}

fn main() {
    let mut seeds: Vec<u64> = (0..=100).collect();
    seeds.push(u64::MAX);
    for seed in seeds {
        let got = submitted::run_simulation(seed)
            .unwrap_or_else(|e| panic!("seed {} still failed: {}", seed, e));
        let expected = reference(seed);
        assert_eq!(got.to_bits(), expected.to_bits(),
            "seed {} produced {}, expected {}", seed, got, expected);
    }
}
''')
    compiled = run([
        "rustc", "--edition=2021", str(harness), "-o", "/tmp/verify_precision"
    ])
    assert compiled.returncode == 0, (
        "src/lib.rs could not be compiled with the required run_simulation API.\n"
        f"Stderr: {compiled.stderr}"
    )
    checked = run(["/tmp/verify_precision"])
    assert checked.returncode == 0, (
        "run_simulation does not perform the required f64 simulation accurately.\n"
        f"Stderr: {checked.stderr}\nStdout: {checked.stdout}"
    )


def test_cargo_run_succeeds():
    assert PROJECT.is_dir(), f"Directory {PROJECT} does not exist."
    result = run(["cargo", "run", "--", "1"], cwd=PROJECT)
    assert result.returncode == 0, (
        f"cargo run failed with exit code {result.returncode}.\n"
        f"Stderr: {result.stderr}\nStdout: {result.stdout}"
    )
    assert "Simulation result:" in result.stdout or "Simulation result:" in result.stderr, (
        "Expected 'Simulation result:' in the output of cargo run."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
