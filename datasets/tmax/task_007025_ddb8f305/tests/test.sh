#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import pytest

PROJECT_DIR = "/home/user/packet_parser"


def cargo_env():
    env = os.environ.copy()
    env["RUSTFLAGS"] = "-D warnings"
    return env


def test_reproducer():
    reproducer_path = "/home/user/reproducer.txt"
    assert os.path.isfile(reproducer_path), f"Expected reproducer file at {reproducer_path} is missing."

    with open(reproducer_path, "r") as f:
        hex_str = f.read().strip()

    assert re.fullmatch(r"(?:[0-9A-F]{2})+", hex_str), \
        "reproducer.txt must contain only an uppercase, even-length hex string."

    try:
        bytes_data = bytes.fromhex(hex_str)
    except ValueError:
        pytest.fail("reproducer.txt does not contain a valid hex string.")

    # Inputs shorter than three bytes return before the vulnerable slice, so three
    # bytes is the minimum possible reproducer length.
    assert len(bytes_data) == 3, \
        "Reproducer must be minimal: the out-of-bounds panic can first occur at exactly 3 bytes."
    assert bytes_data[0] == 0xAA, \
        "Reproducer byte sequence must start with 0xAA to pass the magic byte check."

    length_field = bytes_data[1]
    assert 2 + length_field > len(bytes_data), \
        "Reproducer byte sequence does not trigger the out-of-bounds condition."


def test_rust_code_compiles_without_warnings_and_passes_tests():
    res = subprocess.run(
        ["cargo", "test"],
        cwd=PROJECT_DIR,
        env=cargo_env(),
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, \
        f"cargo test failed or emitted a denied warning.\nStdout:\n{res.stdout}\nStderr:\n{res.stderr}"


def test_rust_code_fixes_general_out_of_bounds_condition():
    tests_dir = os.path.join(PROJECT_DIR, "tests")
    os.makedirs(tests_dir, exist_ok=True)

    test_name = "verifier_" + secrets.token_hex(8)
    eval_test_path = os.path.join(tests_dir, test_name + ".rs")
    seed = secrets.randbits(64) or 1

    source = r'''
use packet_parser::process_packet;

#[test]
fn test_verify_out_of_bounds_fix() {
    // Retain the original fixed regression assertions.
    assert_eq!(process_packet(&[0xAA, 0xFF, 0x00, 0x00]), Err("Out of bounds"));
    assert_eq!(process_packet(&[0xAA, 0x05, 0x01, 0x02, 0x03]), Err("Out of bounds"));

    // Exercise every possible declared length and every truncated actual length.
    // Payload bytes are generated from a verifier-time random seed, preventing a
    // solution from passing by recognizing a fixed collection of packet arrays.
    let mut state: u64 = __SEED__;
    for declared in 2usize..=255 {
        for actual_len in 3usize..(2 + declared) {
            let mut data = vec![0u8; actual_len];
            data[0] = 0xAA;
            data[1] = declared as u8;
            for byte in &mut data[2..] {
                state ^= state << 13;
                state ^= state >> 7;
                state ^= state << 17;
                *byte = state as u8;
            }
            assert_eq!(
                process_packet(&data),
                Err("Out of bounds"),
                "declared length {} with actual packet length {} was not handled safely",
                declared,
                actual_len,
            );
        }
    }
}
'''.replace("__SEED__", str(seed))

    try:
        with open(eval_test_path, "w") as f:
            f.write(source)

        res = subprocess.run(
            ["cargo", "test", "--test", test_name],
            cwd=PROJECT_DIR,
            env=cargo_env(),
            capture_output=True,
            text=True,
        )
    finally:
        if os.path.exists(eval_test_path):
            os.remove(eval_test_path)

    assert res.returncode == 0, \
        f'The fix verification failed. Every truncated payload must return Err("Out of bounds").\nStdout:\n{res.stdout}\nStderr:\n{res.stderr}'
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
