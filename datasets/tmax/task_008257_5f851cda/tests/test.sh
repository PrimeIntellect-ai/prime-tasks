#!/bin/bash
set -e
mkdir -p /logs/verifier

PROJECT_DIR="/home/user/rust_project"
mkdir -p "$PROJECT_DIR/tests"
cat << 'RUST_EOF' > "$PROJECT_DIR/tests/verifier_behavior.rs"
use rust_project::{analytics, storage};
use std::sync::{Arc, Barrier};
use std::thread;

#[test]
fn verifier_sum_large_metrics_uses_precise_accumulation() {
    let data = vec![1.0f32; 20_000_000];
    assert_eq!(analytics::sum_large_metrics(&data), 20_000_000.0f32);
}

#[test]
fn verifier_storage_isolated_between_concurrent_threads() {
    let barrier = Arc::new(Barrier::new(2));
    let mut handles = Vec::new();

    for payload in ["VerifierPayloadA", "VerifierPayloadB"] {
        let barrier = Arc::clone(&barrier);
        handles.push(thread::spawn(move || {
            storage::write_data(payload);
            barrier.wait();
            assert_eq!(storage::read_data(), payload);
        }));
    }

    for handle in handles {
        handle.join().expect("concurrent storage operation failed");
    }
}
RUST_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

PROJECT_DIR = "/home/user/rust_project"
SUCCESS_FILE = "/home/user/success.txt"
ENV_FILE = os.path.join(PROJECT_DIR, ".env")
EXPECTED_TOKEN = "rust_sec_77b31x"


def run_cargo(*args):
    return subprocess.run(
        ["cargo", *args],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )


def strip_rust_comments(text):
    out = []
    i = 0
    in_string = False
    in_char = False
    escaped = False
    block_depth = 0

    while i < len(text):
        if block_depth:
            if text.startswith("/*", i):
                block_depth += 1
                i += 2
            elif text.startswith("*/", i):
                block_depth -= 1
                i += 2
            else:
                i += 1
            continue

        if in_string or in_char:
            ch = text[i]
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif in_string and ch == '"':
                in_string = False
            elif in_char and ch == "'":
                in_char = False
            i += 1
            continue

        if text.startswith("//", i):
            end = text.find("\n", i)
            if end == -1:
                break
            out.append("\n")
            i = end + 1
        elif text.startswith("/*", i):
            block_depth = 1
            i += 2
        else:
            ch = text[i]
            out.append(ch)
            if ch == '"':
                in_string = True
            elif ch == "'":
                in_char = True
            i += 1

    return "".join(out)


def test_success_file():
    assert os.path.isfile(SUCCESS_FILE), f"Success file {SUCCESS_FILE} is missing."
    with open(SUCCESS_FILE, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {SUCCESS_FILE}, but found {len(lines)}."
    assert lines[0] == EXPECTED_TOKEN, f"Line 1 of {SUCCESS_FILE} is incorrect. Expected '{EXPECTED_TOKEN}', got '{lines[0]}'."
    assert lines[1] == "TESTS_PASSED", f"Line 2 of {SUCCESS_FILE} is incorrect. Expected 'TESTS_PASSED', got '{lines[1]}'."


def test_env_file_restored():
    assert os.path.isfile(ENV_FILE), f".env file missing at {ENV_FILE}"
    with open(ENV_FILE, "r") as f:
        content = f.read()

    expected_line = f"SECRET_TOKEN={EXPECTED_TOKEN}"
    assert expected_line in content, f".env file does not contain the correct secret token. Expected '{expected_line}'."


def test_cargo_test_passes():
    result = run_cargo("test")
    assert result.returncode == 0, f"cargo test failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_analytics_precision_fix():
    analytics_file = os.path.join(PROJECT_DIR, "src", "analytics.rs")
    assert os.path.isfile(analytics_file), f"Source file {analytics_file} is missing."
    with open(analytics_file, "r") as f:
        content = f.read()

    assert "f64" in content, "The analytics.rs file does not appear to use f64 for accumulation as requested."


def test_original_assertions_and_tests_remain():
    storage_file = os.path.join(PROJECT_DIR, "src", "storage.rs")
    analytics_file = os.path.join(PROJECT_DIR, "src", "analytics.rs")
    assert os.path.isfile(storage_file), f"Source file {storage_file} is missing."
    assert os.path.isfile(analytics_file), f"Source file {analytics_file} is missing."

    with open(storage_file, "r") as f:
        storage = strip_rust_comments(f.read())
    with open(analytics_file, "r") as f:
        analytics = strip_rust_comments(f.read())

    assert re.search(r'assert_eq!\s*\(\s*read_data\s*\(\s*\)\s*,\s*"PayloadA"\s*\)', storage), "The PayloadA storage assertion was removed or changed."
    assert re.search(r'assert_eq!\s*\(\s*read_data\s*\(\s*\)\s*,\s*"PayloadB"\s*\)', storage), "The PayloadB storage assertion was removed or changed."
    assert re.search(r'assert_eq!\s*\(\s*result\s*,\s*20_000_000\.0\s*\)', analytics), "The analytics precision assertion was removed or changed."

    listed = run_cargo("test", "--", "--list")
    assert listed.returncode == 0, f"Could not list cargo tests.\nSTDOUT:\n{listed.stdout}\nSTDERR:\n{listed.stderr}"
    for name in ("storage::tests::test_storage_a", "storage::tests::test_storage_b", "analytics::tests::test_sum_precision"):
        assert name in listed.stdout, f"Required original test {name} is missing or disabled."


def test_verifier_owned_behavior_tests_pass():
    result = run_cargo("test", "--test", "verifier_behavior", "--", "--test-threads=1")
    assert result.returncode == 0, f"Independent behavior tests failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
