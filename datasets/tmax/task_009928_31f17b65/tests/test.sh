#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SERVICE = "/home/user/weight_service"
MAIN_RS = os.path.join(SERVICE, "src/main.rs")
RESOLUTION = "/home/user/resolution.txt"


def run(cmd, cwd=SERVICE):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def test_resolution_file_exists():
    assert os.path.isfile(RESOLUTION), f"File {RESOLUTION} does not exist"


def test_resolution_file_content():
    with open(RESOLUTION, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, f"Expected at least 2 lines in {RESOLUTION}, found {len(lines)}"

    line1 = lines[0].replace(" ", "")
    line2 = lines[1].replace(" ", "")

    expected_formulas = ["1.0/(x-y)", "1.0_f64/(x-y)", "1./(x-y)", "1.0/(x-y)"]
    assert any(formula in line1 for formula in expected_formulas), \
        f"Line 1 does not contain the correct reverse-engineered formula. Got: {lines[0]}"
    assert line2 == "0.2", \
        f"Line 2 does not contain the correct computed output. Expected '0.2', got: '{lines[1]}'"


def test_c_dependency_removed():
    assert os.path.isfile(MAIN_RS), f"File {MAIN_RS} does not exist"

    with open(MAIN_RS, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert 'extern "C"' not in content, "The FFI 'extern \"C\"' block was not removed from main.rs"
    assert "libcalc.so" not in content, "References to the C library should be removed"

    rust_sources = []
    for root, dirs, files in os.walk(SERVICE):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                path = os.path.join(root, name)
                rust_sources.append(path)
                with open(path, "r", errors="replace") as f:
                    source = f.read()
                assert not re.search(r'extern\s*"C"', source), \
                    f"C FFI remains in {path}"
                assert not re.search(r'\bunsafe\b', source), \
                    f"Pure safe Rust implementation must not use unsafe code: {path}"
                assert not re.search(r'\bstatic\s+mut\b', source), \
                    f"Mutable global state remains in {path}"

    assert rust_sources, "No Rust source files were found"

    # The service must define and use compute_weights, rather than merely compile
    # an empty replacement program.
    uncommented = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
    uncommented = re.sub(r'//.*', '', uncommented)
    assert re.search(r'\bfn\s+compute_weights\s*\(', uncommented), \
        "main.rs does not define a Rust compute_weights function"
    occurrences = re.findall(r'\bcompute_weights\s*\(', uncommented)
    assert len(occurrences) >= 2, \
        "The service does not call its compute_weights implementation"


def test_cargo_build_succeeds_and_binary_has_no_c_dependency():
    assert os.path.isdir(SERVICE), f"Directory {SERVICE} does not exist"

    result = run(["cargo", "build", "--release"])
    assert result.returncode == 0, \
        f"cargo build --release failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    binary = os.path.join(SERVICE, "target/release/weight_service")
    assert os.path.isfile(binary), f"Expected release binary {binary} was not produced"

    dynamic = subprocess.run(["readelf", "-d", binary], capture_output=True, text=True)
    assert dynamic.returncode == 0, f"Could not inspect release binary: {dynamic.stderr}"
    assert "libcalc" not in dynamic.stdout.lower(), \
        "The release binary still has a dynamic dependency on libcalc"

    executed = subprocess.run([binary], cwd=SERVICE, capture_output=True, text=True, timeout=30)
    assert executed.returncode == 0, \
        f"The built service failed when executed.\nSTDOUT:\n{executed.stdout}\nSTDERR:\n{executed.stderr}"


def test_compute_weights_formula_and_concurrency():
    # Add a temporary in-crate test so private compute_weights implementations can
    # be exercised directly. The non-test wrapper also forces the function to
    # exist under normal production cfg, not only under cfg(test).
    with open(MAIN_RS, "rb") as f:
        original = f.read()

    probe = r'''

#[doc(hidden)]
fn __verifier_compute_weights_call(x: f64, y: f64) -> f64 {
    compute_weights(x, y)
}

#[cfg(test)]
mod __verifier_compute_weights_tests {
    use super::__verifier_compute_weights_call;
    use std::sync::{Arc, Barrier};
    use std::thread;

    fn expected(x: f64, y: f64) -> f64 {
        1.0_f64 / (x - y)
    }

    fn close(actual: f64, wanted: f64) -> bool {
        if actual == wanted {
            return true;
        }
        let scale = wanted.abs().max(1.0);
        (actual - wanted).abs() <= 1.0e-13 * scale
    }

    #[test]
    fn verifier_checks_many_derived_inputs() {
        let fixed = [
            (10.0, 5.0), (7.25, -2.5), (-8.0, -11.0),
            (0.125, 4.75), (1000000.5, 999997.25), (-0.5, 0.75),
        ];
        for &(x, y) in &fixed {
            let got = __verifier_compute_weights_call(x, y);
            let want = expected(x, y);
            assert!(got.is_finite(), "non-finite result for ({}, {}): {}", x, y, got);
            assert!(close(got, want), "wrong result for ({}, {}): got {}, expected {}", x, y, got, want);
        }

        let mut state: u64 = 0x9e3779b97f4a7c15;
        for i in 0..4096_u64 {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let x = ((state >> 16) % 200000) as f64 / 32.0 - 3000.0;
            let delta = ((i % 997) + 1) as f64 / 64.0;
            let y = if i & 1 == 0 { x - delta } else { x + delta };
            let got = __verifier_compute_weights_call(x, y);
            let want = expected(x, y);
            assert!(got.is_finite(), "non-finite result for ({}, {}): {}", x, y, got);
            assert!(close(got, want), "wrong result for ({}, {}): got {}, expected {}", x, y, got, want);
        }
    }

    #[test]
    fn verifier_checks_thread_safe_behavior() {
        const THREADS: usize = 32;
        const ROUNDS: usize = 1000;
        let barrier = Arc::new(Barrier::new(THREADS));
        let mut handles = Vec::new();

        for thread_id in 0..THREADS {
            let barrier = Arc::clone(&barrier);
            handles.push(thread::spawn(move || {
                barrier.wait();
                for round in 0..ROUNDS {
                    let x = 10000.0 + (thread_id * ROUNDS + round) as f64 / 16.0;
                    let delta = ((thread_id * 37 + round * 13) % 251 + 1) as f64 / 32.0;
                    let y = if (thread_id + round) & 1 == 0 { x - delta } else { x + delta };
                    let got = __verifier_compute_weights_call(x, y);
                    let want = expected(x, y);
                    assert!(got.is_finite(), "concurrent call produced {}", got);
                    assert!(close(got, want), "concurrent call got {}, expected {}", got, want);
                }
            }));
        }

        for handle in handles {
            handle.join().expect("compute_weights failed in a worker thread");
        }
    }
}
'''.encode()

    try:
        with open(MAIN_RS, "wb") as f:
            f.write(original)
            f.write(probe)

        # This build checks that the wrapper and compute_weights exist in the
        # production configuration as well as in the test configuration.
        built = run(["cargo", "build", "--release"])
        assert built.returncode == 0, \
            f"Could not call a production Rust compute_weights function.\nSTDOUT:\n{built.stdout}\nSTDERR:\n{built.stderr}"

        tested = run(["cargo", "test", "--release", "__verifier_compute_weights_tests", "--", "--test-threads=1"])
        assert tested.returncode == 0, \
            f"compute_weights failed formula or concurrency tests.\nSTDOUT:\n{tested.stdout}\nSTDERR:\n{tested.stderr}"
    finally:
        with open(MAIN_RS, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
