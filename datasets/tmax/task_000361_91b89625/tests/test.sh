#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import struct
import subprocess

PROJECT_DIR = "/home/user/oscillator_fit"

EXPECTED_MAIN = '''mod integrator;
mod mcmc;

use std::fs::File;
use std::io::Write;
use plotters::prelude::*;

fn main() {
    // Mock MCMC loop and plotting for the sake of the exercise
    let mut c = 0.5;
    let mut k = 2.0;

    // Simulate finding the fit
    if mcmc::mh_accept(-10.0, -2.0) {
        c = 0.51;
        k = 1.98;
    }

    println!("c: {:.2}, k: {:.2}", c, k);

    // Create dummy plot
    let root = BitMapBackend::new("/home/user/fit.png", (640, 480)).into_drawing_area();
    root.fill(&WHITE).unwrap();
    let mut chart = ChartBuilder::on(&root)
        .build_cartesian_2d(0f32..10f32, -1f32..1f32)
        .unwrap();
    chart.configure_mesh().draw().unwrap();
}
'''
EXPECTED_DATA = '''0.0, 1.0
0.1, 0.9
0.2, 0.7
'''


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def test_instruction_protected_files_unchanged():
    with open(os.path.join(PROJECT_DIR, "src/main.rs"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_MAIN, "src/main.rs was modified"
    with open(os.path.join(PROJECT_DIR, "data.csv"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_DATA, "data.csv was modified"


def test_cargo_test_passes():
    """Verify that cargo test passes in the Rust project."""
    assert os.path.isdir(PROJECT_DIR), f"{PROJECT_DIR} does not exist"
    result = run(["cargo", "test"], cwd=PROJECT_DIR, timeout=180)
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}\n{result.stderr}"


def test_integrator_and_mcmc_behavior():
    """Compile the submitted modules into fresh tests and exercise their behavior."""
    tests_dir = os.path.join(PROJECT_DIR, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    test_path = os.path.join(tests_dir, "verifier_behavior.rs")

    random = secrets.SystemRandom()
    integrator_cases = []
    for _ in range(12):
        tolerance = random.uniform(0.001, 0.5)
        dt = random.uniform(0.001, 2.0)
        integrator_cases.extend([
            (tolerance, dt, tolerance * random.uniform(1.1, 8.0), dt * 0.5),
            (tolerance, dt, tolerance * random.uniform(0.001, 0.09), dt * 2.0),
            (tolerance, dt, tolerance * random.uniform(0.11, 0.99), dt),
        ])

    cases_text = ",\n".join(
        f"        ({tol:.17e}, {dt:.17e}, {err:.17e}, {expected:.17e})"
        for tol, dt, err, expected in integrator_cases
    )

    probabilities = [random.uniform(0.12, 0.88) for _ in range(4)]
    probability_checks = []
    for index, probability in enumerate(probabilities):
        current = random.uniform(-50.0, 20.0)
        proposed = current + math.log(probability)
        probability_checks.append(f'''        let accepted_{index} = (0..8000)
            .filter(|_| mcmc::mh_accept({current:.17e}, {proposed:.17e}))
            .count();
        let observed_{index} = accepted_{index} as f64 / 8000.0;
        assert!((observed_{index} - {probability:.17e}).abs() < 0.05,
            "wrong MH acceptance rate: expected about {{}} but observed {{}}",
            {probability:.17e}, observed_{index});''')

    improving_checks = []
    for _ in range(32):
        current = random.uniform(-100.0, 100.0)
        proposed = current + random.uniform(0.001, 100.0)
        improving_checks.append(
            f'        assert!(mcmc::mh_accept({current:.17e}, {proposed:.17e}), '
            f'"an improving proposal must always be accepted");'
        )

    rust_test = f'''#[path = "../src/integrator.rs"]
mod integrator;
#[path = "../src/mcmc.rs"]
mod mcmc;

#[test]
fn adaptive_step_size_has_correct_behavior() {{
    let cases: &[(f64, f64, f64, f64)] = &[
{cases_text}
    ];
    for &(tolerance, initial_dt, error, expected_dt) in cases {{
        let solver = integrator::AdaptiveEuler {{ tolerance }};
        let mut dt = initial_dt;
        solver.step(&mut dt, error);
        let scale = expected_dt.abs().max(1.0);
        assert!((dt - expected_dt).abs() <= 1e-12 * scale,
            "for tolerance={{tolerance}}, error={{error}}, and initial dt={{initial_dt}}, expected {{expected_dt}} but got {{dt}}");
    }}
}}

#[test]
fn metropolis_hastings_acceptance_has_correct_behavior() {{
{chr(10).join(improving_checks)}
    for _ in 0..64 {{
        assert!(mcmc::mh_accept(3.25, 3.25), "an equal-likelihood proposal must always be accepted");
        assert!(!mcmc::mh_accept(10.0, -1000.0), "a proposal with zero effective acceptance probability was accepted");
    }}
{chr(10).join(probability_checks)}
}}
'''

    with open(test_path, "w", encoding="utf-8") as f:
        f.write(rust_test)

    try:
        result = run(
            ["cargo", "test", "--test", "verifier_behavior", "--", "--test-threads=1"],
            cwd=PROJECT_DIR,
            timeout=180,
        )
        assert result.returncode == 0, (
            "behavioral tests failed:\n" + result.stdout + "\n" + result.stderr
        )
    finally:
        try:
            os.remove(test_path)
        except FileNotFoundError:
            pass


def test_project_runs_and_generates_expected_artifacts():
    """Run the requested release artifact and require it to freshly generate the plot."""
    png_path = "/home/user/fit.png"
    try:
        os.remove(png_path)
    except FileNotFoundError:
        pass

    result = run(["cargo", "run", "--release"], cwd=PROJECT_DIR, timeout=240)
    assert result.returncode == 0, f"cargo run --release failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.strip() == "c: 0.51, k: 1.98", f"unexpected program output: {result.stdout!r}"
    assert os.path.isfile(png_path), "cargo run --release did not generate /home/user/fit.png"

    with open(png_path, "rb") as f:
        png = f.read()
    assert len(png) > 1000, "fit.png is too small to be the generated plot"
    assert png.startswith(b"\x89PNG\r\n\x1a\n"), "fit.png is not a PNG file"
    assert png[12:16] == b"IHDR", "fit.png has no valid PNG IHDR chunk"
    width, height = struct.unpack(">II", png[16:24])
    assert (width, height) == (640, 480), f"unexpected plot dimensions: {width}x{height}"
    assert png.endswith(b"\x00\x00\x00\x00IEND\xaeB`\x82"), "fit.png is truncated"


def test_results_file_content():
    """Verify that results.txt contains the correct output."""
    results_path = "/home/user/results.txt"
    assert os.path.isfile(results_path), f"{results_path} does not exist"
    with open(results_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert "c: 0.51, k: 1.98" in content, f"Expected 'c: 0.51, k: 1.98' in {results_path}, found: {content}"
    assert content == "c: 0.51, k: 1.98", f"{results_path} is not in the exact required format: {content!r}"


def test_fit_png_exists():
    """Verify that the plot was successfully generated."""
    png_path = "/home/user/fit.png"
    assert os.path.isfile(png_path), f"{png_path} does not exist"
    assert os.path.getsize(png_path) > 0, f"{png_path} is empty"


def test_integrator_fixed():
    """Preserve the original source-level assertion."""
    integrator_path = os.path.join(PROJECT_DIR, "src/integrator.rs")
    assert os.path.isfile(integrator_path), f"{integrator_path} does not exist"
    with open(integrator_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "*dt *= 0.5" in content or "*dt /= 2.0" in content, "Step size should be halved on high error"


def test_mcmc_implemented():
    """Preserve the original source-level assertion."""
    mcmc_path = os.path.join(PROJECT_DIR, "src/mcmc.rs")
    assert os.path.isfile(mcmc_path), f"{mcmc_path} does not exist"
    with open(mcmc_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "exp()" in content or "gen_bool" in content or "gen::<f64>()" in content, "MCMC acceptance logic seems incomplete"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
