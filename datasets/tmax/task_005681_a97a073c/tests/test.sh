#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/sequence_aligner')
BOOTSTRAP = PROJECT / 'src/bootstrap.rs'
MAIN = PROJECT / 'src/main.rs'
SCRIPT = Path('/home/user/run_tests.sh')
RESULT = Path('/home/user/ci_result.txt')
BINARY = PROJECT / 'target/release/sequence_aligner'
EXPECTED = '44.60,50.35'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=180, **kwargs)


def parse_ci(output):
    match = re.search(r'95% CI:\s*\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\]', output)
    assert match, f'Could not parse confidence interval from application output: {output!r}'
    return f'{match.group(1)},{match.group(2)}'


def test_bootstrap_rs_optimized():
    assert BOOTSTRAP.is_file(), 'bootstrap.rs is missing.'
    content = BOOTSTRAP.read_text()
    assert 'data.to_vec()' not in content, 'The performance bug (data.to_vec()) is still present in bootstrap.rs.'


def test_run_tests_sh_exists_and_executable():
    assert SCRIPT.is_file(), '/home/user/run_tests.sh does not exist.'
    assert os.access(SCRIPT, os.X_OK), '/home/user/run_tests.sh is not executable.'


def test_ci_result_content():
    assert RESULT.is_file(), '/home/user/ci_result.txt does not exist.'
    content = RESULT.read_text().strip()
    assert content == EXPECTED, f"Expected /home/user/ci_result.txt to contain '{EXPECTED}', but found '{content}'."


def test_harness_really_builds_runs_and_parses():
    subprocess.run(['cargo', 'clean'], cwd=PROJECT, check=True, timeout=60)
    if RESULT.exists():
        RESULT.unlink()

    run([str(SCRIPT)], cwd='/home/user')
    assert RESULT.is_file(), 'run_tests.sh did not create /home/user/ci_result.txt.'
    assert BINARY.is_file(), 'run_tests.sh did not build the release application.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'The release artifact is not a compiled ELF executable.'

    app = run([str(BINARY)], cwd=PROJECT)
    parsed = parse_ci(app.stdout)
    assert parsed == EXPECTED, f'Compiled application produced {parsed}, expected {EXPECTED}.'
    assert RESULT.read_text().strip() == parsed, 'ci_result.txt was not derived from the application output.'

    # Change only the program's emitted interval and require the harness to follow it.
    # This rejects a harness that merely writes the known answer.
    original_main = MAIN.read_bytes()
    try:
        MAIN.write_text('fn main() { println!("95% CI: [12.34, 67.89]"); }\n')
        if BINARY.exists():
            BINARY.unlink()
        if RESULT.exists():
            RESULT.unlink()
        run([str(SCRIPT)], cwd='/home/user')
        assert RESULT.read_text().strip() == '12.34,67.89', \
            'run_tests.sh hardcodes the result instead of parsing the application output.'
    finally:
        MAIN.write_bytes(original_main)

    # Restore the requested final build and result.
    if BINARY.exists():
        BINARY.unlink()
    run([str(SCRIPT)], cwd='/home/user')
    assert RESULT.read_text().strip() == EXPECTED


def test_bootstrap_function_correct_and_allocation_free_in_hot_loop():
    bin_dir = PROJECT / 'src/bin'
    probe = bin_dir / 'verifier_probe.rs'
    bin_dir.mkdir(exist_ok=True)
    probe.write_text(r'''
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

#[path = "../bootstrap.rs"]
mod submission;

struct CountingAllocator;
static ALLOCS: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOCS.fetch_add(1, Ordering::SeqCst);
        System.alloc(layout)
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout)
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        ALLOCS.fetch_add(1, Ordering::SeqCst);
        System.realloc(ptr, layout, size)
    }
}

#[global_allocator]
static GLOBAL: CountingAllocator = CountingAllocator;

fn reference(data: &[f64], iterations: usize) -> (f64, f64) {
    let mut rng = StdRng::seed_from_u64(42);
    let n = data.len();
    let mut means = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let mut sum = 0.0;
        for _ in 0..n {
            sum += data[rng.gen_range(0..n)];
        }
        means.push(sum / n as f64);
    }
    means.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let lo = (iterations as f64 * 0.025).floor() as usize;
    let hi = (iterations as f64 * 0.975).floor() as usize;
    (means[lo], means[hi])
}

fn check(data: &[f64], iterations: usize) {
    let expected = reference(data, iterations);
    ALLOCS.store(0, Ordering::SeqCst);
    let actual = submission::calculate_95_ci(data, iterations);
    let allocations = ALLOCS.load(Ordering::SeqCst);
    assert_eq!(actual.0.to_bits(), expected.0.to_bits(), "wrong lower bound");
    assert_eq!(actual.1.to_bits(), expected.1.to_bits(), "wrong upper bound");
    assert!(allocations <= 3,
        "bootstrap calculation made {} allocations; allocation appears to remain in the sampling loop",
        allocations);
}

fn main() {
    check(&[3.5, -2.0, 8.25, 11.0, 0.5, 6.75, 4.0], 257);
    check(&[101.0, 4.5, 19.25, -7.0, 33.0, 2.0, 18.5, 9.75, 61.0], 2000);
    check(&[45.0, 50.0, 42.0, 48.0, 55.0, 40.0, 47.0, 49.0, 51.0, 46.0,
            43.0, 52.0, 44.0, 53.0, 41.0, 54.0, 39.0, 56.0, 38.0, 57.0], 10000);
}
''')
    try:
        run(['cargo', 'run', '--release', '--quiet', '--bin', 'verifier_probe'], cwd=PROJECT)
    finally:
        if probe.exists():
            probe.unlink()
        try:
            bin_dir.rmdir()
        except OSError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
