#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import pytest


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=120)


def test_lib_rs_bugs_fixed():
    path = "/home/user/num_calc/src/lib.rs"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "as f32" not in content, "The precision loss bug (using f32) is still present in lib.rs."
    assert "0..=steps" not in content, "The off-by-one bug (0..=steps) is still present in lib.rs."
    assert "left_riemann_sum" in content, "The left_riemann_sum function is missing in lib.rs."


def test_cargo_test_passes():
    path = "/home/user/num_calc"
    assert os.path.isdir(path), f"Directory {path} does not exist."
    result = run(["cargo", "test"], cwd=path)
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}\n{result.stderr}"


def test_mre_compiles_and_runs():
    mre_path = "/home/user/mre.rs"
    assert os.path.isfile(mre_path), f"File {mre_path} does not exist."

    compile_result = run(["rustc", mre_path], cwd="/home/user")
    assert compile_result.returncode == 0, f"rustc failed to compile mre.rs:\n{compile_result.stderr}"

    exe_path = "/home/user/mre"
    assert os.path.isfile(exe_path), f"Executable {exe_path} was not created."
    run_result = run([exe_path], cwd="/home/user")
    assert run_result.returncode == 0, f"./mre failed to run:\n{run_result.stderr}"

    output = run_result.stdout.strip()
    assert output, "./mre did not print any output."
    try:
        val = float(output)
        assert abs(val - 332833.5) < 1.0, f"Expected output close to 332833.5, but got {val}"
    except ValueError:
        pytest.fail(f"Output of ./mre could not be parsed as a float: {output}")


def expected_left_sum(start, end, steps):
    width = (end - start) / steps
    return math.fsum((start + i * width) ** 2 * width for i in range(steps))


def exercise(executable, cases):
    for start, end, steps in cases:
        result = run([executable, repr(start), repr(end), str(steps)])
        assert result.returncode == 0, result.stderr
        try:
            actual = float(result.stdout.strip())
        except ValueError:
            pytest.fail(f"Probe output was not a float: {result.stdout!r}")
        expected = expected_left_sum(start, end, steps)
        tolerance = max(1e-8, abs(expected) * 2e-9)
        assert math.isfinite(actual), f"Non-finite result for ({start}, {end}, {steps})"
        assert abs(actual - expected) <= tolerance, (
            f"left_riemann_sum({start}, {end}, {steps}) returned {actual}; "
            f"expected {expected} within {tolerance}"
        )


def test_functions_work_for_arbitrary_arguments():
    rng = random.SystemRandom()
    cases = [
        (0.0, 1.0, 1),
        (2.5, 9.25, 2),
        (-7.0, 3.0, 17),
        (12.0, -4.0, 101),
        (-3.125, -0.25, 997),
    ]
    step_choices = [3, 7, 19, 64, 257, 1009, 4096]
    for _ in range(10):
        start = rng.uniform(-75.0, 75.0)
        delta = rng.uniform(-100.0, 100.0)
        if abs(delta) < 0.5:
            delta = 0.5 if delta >= 0 else -0.5
        cases.append((start, start + delta, rng.choice(step_choices)))

    with tempfile.TemporaryDirectory() as td:
        lib_probe = os.path.join(td, "lib_probe.rs")
        lib_exe = os.path.join(td, "lib_probe")
        with open(lib_probe, "w") as f:
            f.write(r'''
#[path = "/home/user/num_calc/src/lib.rs"]
mod submitted;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let start: f64 = args[1].parse().unwrap();
    let end: f64 = args[2].parse().unwrap();
    let steps: usize = args[3].parse().unwrap();
    println!("{:.17e}", submitted::left_riemann_sum(start, end, steps));
}
''')
        compiled = run(["rustc", "--edition=2021", lib_probe, "-o", lib_exe])
        assert compiled.returncode == 0, f"Could not compile library probe:\n{compiled.stderr}"
        exercise(lib_exe, cases)

        mre_probe = os.path.join(td, "mre_probe.rs")
        mre_exe = os.path.join(td, "mre_probe")
        with open(mre_probe, "w") as f:
            f.write(r'''
mod submitted {
    include!("/home/user/mre.rs");
    pub fn verifier_call(start: f64, end: f64, steps: usize) -> f64 {
        left_riemann_sum(start, end, steps)
    }
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let start: f64 = args[1].parse().unwrap();
    let end: f64 = args[2].parse().unwrap();
    let steps: usize = args[3].parse().unwrap();
    println!("{:.17e}", submitted::verifier_call(start, end, steps));
}
''')
        compiled = run(["rustc", "--edition=2021", mre_probe, "-o", mre_exe])
        assert compiled.returncode == 0, f"Could not compile MRE function probe:\n{compiled.stderr}"
        exercise(mre_exe, cases)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
