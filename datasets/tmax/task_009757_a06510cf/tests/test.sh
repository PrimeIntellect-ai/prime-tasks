#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/spectro_solve")
LIB = PROJECT / "src/lib.rs"
MAIN = PROJECT / "src/main.rs"
OUTPUT = Path("/home/user/concentrations.txt")

EXPECTED_CARGO = '''[package]
name = "spectro_solve"
version = "0.1.0"
edition = "2021"
'''

EXPECTED_MAIN = '''use spectro_solve::solve_concentrations;

fn main() {
    // Wavelength 1: A=0.8, B=0.3, Mix=2.5
    // Wavelength 2: A=0.2, B=0.9, Mix=2.95
    let (c_a, c_b) = solve_concentrations(0.8, 0.3, 2.5, 0.2, 0.9, 2.95);
    println!("Component A: {:.2}", c_a);
    println!("Component B: {:.2}", c_b);
}
'''

EXPECTED_TESTS = '''#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reference_dataset() {
        // Known reference: mix of 2.0 A and 1.0 B
        // Wavelength 1: A=2.0, B=1.0, Mix=5.0
        // Wavelength 2: A=1.0, B=3.0, Mix=5.0
        let (c_a, c_b) = solve_concentrations(2.0, 1.0, 5.0, 1.0, 3.0, 5.0);
        assert!((c_a - 2.0).abs() < 1e-6, "Expected c_a = 2.0, got {}", c_a);
        assert!((c_b - 1.0).abs() < 1e-6, "Expected c_b = 1.0, got {}", c_b);
    }
}
'''


def run(command, cwd=None, timeout=120):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_concentrations_file_exists_and_correct():
    """Preserve the required output-file check."""
    assert OUTPUT.is_file(), f"Output file {OUTPUT} does not exist. Did you run the cargo command and redirect output?"
    content = OUTPUT.read_text().strip()
    expected = "Component A: 2.07\nComponent B: 2.82"
    assert content == expected, f"Content of {OUTPUT} is incorrect.\nExpected:\n{expected}\n\nGot:\n{content}"


def test_protected_project_files_and_tests_are_unchanged():
    assert PROJECT.is_dir(), f"Directory {PROJECT} does not exist."
    assert (PROJECT / "Cargo.toml").read_text() == EXPECTED_CARGO, "Cargo.toml was modified."
    assert MAIN.read_text() == EXPECTED_MAIN, "src/main.rs was modified."
    assert not (PROJECT / "tests").exists(), "Tests were added or modified in the project tests directory."

    content = LIB.read_text()
    marker = "#[cfg(test)]"
    assert marker in content, "The original Rust tests were removed."
    assert content[content.index(marker):] == EXPECTED_TESTS, "The original tests in src/lib.rs were modified."


def test_lib_rs_bug_fixed():
    """Preserve the original source-level typo check."""
    assert LIB.is_file(), f"File {LIB} does not exist."
    content = LIB.read_text()
    assert "m1 * b2 + b1 * m2" not in content, (
        "The mathematical bug 'm1 * b2 + b1 * m2' is still present in src/lib.rs. "
        "It should use subtraction for Cramer's rule."
    )


def test_cargo_test_passes_and_original_test_is_present():
    """Preserve cargo test and ensure it did not silently run zero tests."""
    result = run(["cargo", "test"], cwd=PROJECT)
    listing = run(["cargo", "test", "--", "--list"], cwd=PROJECT)
    combined = listing.stdout + listing.stderr
    assert "tests::test_reference_dataset: test" in combined, "The original Rust unit test was disabled or removed."


def test_solver_on_runtime_generated_systems():
    """Compile lib.rs directly and exercise the solver on unpredictable nonsingular systems."""
    cases = []
    while len(cases) < 16:
        a1 = secrets.randbelow(39) - 19
        b1 = secrets.randbelow(39) - 19
        a2 = secrets.randbelow(39) - 19
        b2 = secrets.randbelow(39) - 19
        if abs(a1 * b2 - b1 * a2) < 3:
            continue
        x = (secrets.randbelow(401) - 200) / 13.0
        y = (secrets.randbelow(401) - 200) / 17.0
        m1 = a1 * x + b1 * y
        m2 = a2 * x + b2 * y
        cases.append((float(a1), float(b1), m1, float(a2), float(b2), m2, x, y))

    case_literals = ",\n".join(
        "        (" + ", ".join(format(v, ".17g") for v in case) + ")"
        for case in cases
    )
    harness = f'''mod candidate {{
    include!(r#"{LIB}"#);
}}

fn main() {{
    let cases: [(f64, f64, f64, f64, f64, f64, f64, f64); {len(cases)}] = [
{case_literals}
    ];
    for (a1, b1, m1, a2, b2, m2, expected_x, expected_y) in cases {{
        let (x, y) = candidate::solve_concentrations(a1, b1, m1, a2, b2, m2);
        let tol_x = 1e-9_f64 * expected_x.abs().max(1.0);
        let tol_y = 1e-9_f64 * expected_y.abs().max(1.0);
        assert!((x - expected_x).abs() <= tol_x,
                "wrong x for system {{:?}}: expected {{}}, got {{}}",
                (a1, b1, m1, a2, b2, m2), expected_x, x);
        assert!((y - expected_y).abs() <= tol_y,
                "wrong y for system {{:?}}: expected {{}}, got {{}}",
                (a1, b1, m1, a2, b2, m2), expected_y, y);
    }}
}}
'''
    harness_path = Path("/tmp/spectro_solver_verifier.rs")
    binary_path = Path("/tmp/spectro_solver_verifier")
    harness_path.write_text(harness)
    run(["rustc", "--edition=2021", "-O", str(harness_path), "-o", str(binary_path)])
    run([str(binary_path)])


def test_release_binary_reproduces_submitted_output():
    """Actually execute the required binary and compare its output to the submitted file."""
    result = run(["cargo", "run", "--release", "--quiet"], cwd=PROJECT)
    assert result.stdout.strip() == OUTPUT.read_text().strip(), (
        "The current release binary does not reproduce /home/user/concentrations.txt."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
