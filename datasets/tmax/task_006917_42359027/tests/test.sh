#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
import tomllib
from pathlib import Path

PROJECT = Path("/home/user/stats_project")

EXPECTED_PREFIX = """use rand::{Rng, SeedableRng};
use rand::rngs::SmallRng;
use log::{info, error};

"""

EXPECTED_SUFFIX = """

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_statistical_anomaly() {
        let _ = env_logger::builder().is_test(true).try_init();
        let mut rng = SmallRng::seed_from_u64(42);
        let mut data = vec![];
        for _ in 0..100 {
            data.push(rng.gen_range(-10.0..10.0));
        }

        let var = compute_variance(&data);
        info!("Computed variance: {}", var);

        let std_dev = var.sqrt();
        info!("Computed std_dev: {}", std_dev);

        assert!(std_dev > 4.0 && std_dev < 7.0, "Statistical anomaly detected: std_dev is {}", std_dev);
    }
}
"""


def test_project_structure_and_unchanged_tests():
    assert PROJECT.is_dir(), f"Project directory {PROJECT} is missing."
    assert not (PROJECT / "build.rs").exists(), "build.rs is not an allowed modification."
    assert not (PROJECT / ".cargo").exists(), "Project-local Cargo configuration is not allowed."

    src = PROJECT / "src"
    assert src.is_dir() and not src.is_symlink(), "src must be a real directory."
    assert sorted(p.name for p in src.iterdir()) == ["lib.rs"], "Only the original src/lib.rs is allowed."
    assert (src / "lib.rs").is_file() and not (src / "lib.rs").is_symlink()

    source = (src / "lib.rs").read_text()
    signature = "pub fn compute_variance(data: &[f64]) -> f64"
    start = source.find(signature)
    assert start >= 0, "compute_variance with the required public signature is missing."
    assert source[:start] == EXPECTED_PREFIX, "Code outside compute_variance was modified."

    brace = source.find("{", start + len(signature))
    assert brace >= 0, "compute_variance has no function body."
    depth = 0
    end = None
    for pos in range(brace, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                end = pos
                break
    assert end is not None, "compute_variance has an unterminated body."
    assert source[end + 1:] == EXPECTED_SUFFIX, "The original test code was changed or disabled."


def test_dependency_configuration():
    cargo_path = PROJECT / "Cargo.toml"
    assert cargo_path.is_file() and not cargo_path.is_symlink(), "Cargo.toml is missing or invalid."
    with cargo_path.open("rb") as f:
        cargo = tomllib.load(f)

    assert set(cargo) == {"package", "dependencies"}, "Unexpected Cargo configuration was added."
    assert cargo["package"] == {
        "name": "stats_project",
        "version": "0.1.0",
        "edition": "2021",
    }, "Package metadata must remain unchanged."

    deps = cargo["dependencies"]
    assert set(deps) == {"rand", "log", "env_logger"}, "The original dependency set must remain unchanged."
    assert deps["log"] == "0.4" and deps["env_logger"] == "0.10", "Unrelated dependencies were modified."
    rand = deps["rand"]
    assert isinstance(rand, dict), "rand must be configured with its required feature."
    assert set(rand).issubset({"version", "features"}), "Unexpected rand dependency overrides are not allowed."
    assert rand.get("version") == "0.8", "The rand version must remain 0.8."
    assert isinstance(rand.get("features"), list) and "small_rng" in rand["features"], \
        "The rand small_rng feature is not enabled."


def test_cargo_test_passes():
    result = subprocess.run(
        ["cargo", "test"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"cargo test failed. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_compute_variance_on_hidden_inputs():
    rng = secrets.SystemRandom()
    cases = [
        [3.25] * 17,
        [-4.0, -1.0, 2.0, 5.0],
        [0.0, 1.0, -1.0, 2.5, -3.75],
    ]
    for _ in range(12):
        length = rng.randrange(2, 80)
        scale = 10.0 ** rng.uniform(-2.0, 3.0)
        offset = rng.uniform(-2.0, 2.0) * scale
        cases.append([offset + rng.uniform(-5.0, 5.0) * scale for _ in range(length)])

    with tempfile.TemporaryDirectory(prefix="variance_verifier_") as td:
        td_path = Path(td)
        (td_path / "src").mkdir()
        (td_path / "Cargo.toml").write_text(
            '[package]\nname = "variance_verifier"\nversion = "0.1.0"\nedition = "2021"\n'
            '[dependencies]\nstats_project = { path = "/home/user/stats_project" }\n'
        )
        (td_path / "src" / "main.rs").write_text(r'''use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut fields = input.split_whitespace();
    while let Some(n) = fields.next() {
        let n: usize = n.parse().unwrap();
        let mut values = Vec::with_capacity(n);
        for _ in 0..n {
            values.push(fields.next().unwrap().parse::<f64>().unwrap());
        }
        println!("{:.17}", stats_project::compute_variance(&values));
    }
}
''')
        payload = "".join(
            str(len(case)) + " " + " ".join(format(x, ".17g") for x in case) + "\n"
            for case in cases
        )
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--offline"],
            cwd=td_path,
            input=payload,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, \
            f"External variance checks could not run. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    lines = result.stdout.splitlines()
    assert len(lines) == len(cases), "compute_variance produced unexpected output."
    for case, line in zip(cases, lines):
        try:
            actual = float(line)
        except ValueError:
            raise AssertionError(f"Invalid variance output: {line!r}")
        mean = sum(case) / len(case)
        expected = sum(x * x for x in case) / len(case) - mean ** 2
        assert math.isfinite(actual), f"Variance is not finite for input {case!r}."
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-9), \
            f"Incorrect variance for hidden input: expected {expected}, got {actual}."


def test_fix_txt_content():
    fix_txt_path = Path("/home/user/fix.txt")
    assert fix_txt_path.is_file(), f"{fix_txt_path} is missing."
    content = fix_txt_path.read_text().strip()
    expected = "let var = mean_sq - mean.powi(2);"
    assert content == expected, f"Expected fix.txt to contain exactly '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
