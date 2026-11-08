#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import subprocess
import pytest


def get_expected_token():
    dump_path = "/home/user/forensics/memory.dmp"
    if not os.path.exists(dump_path):
        return None
    with open(dump_path, "rb") as f:
        content = f.read().decode("utf-8", errors="ignore")
    match = re.search(r"SESSION_TOKEN:([a-f0-9]{32})", content)
    if match:
        return match.group(1)
    return None


def test_token_extracted_correctly():
    token_file = "/home/user/solution/token.txt"
    assert os.path.isfile(token_file), f"Token file missing at {token_file}"

    with open(token_file, "r") as f:
        actual_token = f.read().strip()

    expected_token = get_expected_token()
    assert expected_token is not None, "Could not find expected token in memory dump."

    assert actual_token == expected_token, f"Token in {token_file} is incorrect. Expected {expected_token}, got {actual_token}"


def test_cargo_test_passes():
    app_dir = "/home/user/legacy_app"
    assert os.path.isdir(app_dir), f"Legacy app directory missing at {app_dir}"

    # Run cargo test repeatedly to ensure intermittent failure is fixed
    for i in range(3):
        result = subprocess.run(
            ["cargo", "test"],
            cwd=app_dir,
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"`cargo test` failed on run {i+1}. Output:\n{result.stdout}\n{result.stderr}"


def test_lib_rs_deterministic_logic():
    lib_rs_path = "/home/user/legacy_app/src/lib.rs"
    assert os.path.isfile(lib_rs_path), f"lib.rs missing at {lib_rs_path}"

    # Keep the original source-level sanity assertion.
    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "pub fn get_priority_worker" in content, "get_priority_worker function missing in lib.rs"


def test_get_priority_worker_behavior():
    lib_rs_path = "/home/user/legacy_app/src/lib.rs"
    rlib_path = "/tmp/libaudited_submission.rlib"
    harness_path = "/tmp/priority_worker_harness.rs"
    binary_path = "/tmp/priority_worker_harness"

    build_library = subprocess.run(
        [
            "rustc", lib_rs_path,
            "--edition=2021",
            "--crate-name", "audited_submission",
            "--crate-type", "rlib",
            "-o", rlib_path,
        ],
        capture_output=True,
        text=True,
    )
    assert build_library.returncode == 0, (
        "Could not compile src/lib.rs as a Rust library:\n"
        + build_library.stdout + build_library.stderr
    )

    harness = r'''
extern crate audited_submission;

use audited_submission::get_priority_worker;
use std::collections::HashMap;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

fn check(entries: &[(String, u32)]) {
    let highest = entries.iter().map(|(_, score)| *score).max().unwrap_or(0);
    let expected = entries
        .iter()
        .filter(|(_, score)| *score == highest)
        .map(|(name, _)| name.as_str())
        .min()
        .unwrap_or("")
        .to_string();

    // Rebuild the HashMap repeatedly so randomized iteration order cannot mask a bug.
    for _ in 0..16 {
        let workers: HashMap<String, u32> = entries.iter().cloned().collect();
        let actual = get_priority_worker(&workers);
        assert_eq!(actual, expected, "wrong result for workers: {:?}", entries);
    }
}

fn main() {
    check(&[
        ("unstable_worker".to_string(), 50),
        ("alpha_worker".to_string(), 50),
        ("beta_worker".to_string(), 50),
    ]);
    check(&[
        ("aardvark".to_string(), 2),
        ("middle".to_string(), 91),
        ("zebra".to_string(), 17),
    ]);
    check(&[
        ("zulu".to_string(), 700),
        ("echo".to_string(), 700),
        ("delta".to_string(), 700),
        ("alpha".to_string(), 12),
    ]);
    check(&[
        ("worker_10".to_string(), 0),
        ("worker_02".to_string(), 0),
        ("worker_01".to_string(), 0),
    ]);

    let names = [
        "quartz", "amber", "violet", "cedar", "nylon", "bravo",
        "xenon", "delta", "opal", "lima", "sable", "falcon",
    ];
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
    let mut state = now.as_nanos() as u64 ^ ((process::id() as u64) << 32);

    for round in 0..80usize {
        let mut entries: Vec<(String, u32)> = names.iter().map(|name| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((*name).to_string(), ((state >> 32) % 500) as u32)
        }).collect();

        if round % 2 == 0 {
            let first = (state as usize) % entries.len();
            state = state.rotate_left(17).wrapping_add(0x9e3779b97f4a7c15);
            let mut second = (state as usize) % entries.len();
            if second == first {
                second = (second + 1) % entries.len();
            }
            entries[first].1 = 1000;
            entries[second].1 = 1000;
        } else {
            let winner = (state as usize) % entries.len();
            entries[winner].1 = 2000;
        }

        check(&entries);
    }
}
'''
    with open(harness_path, "w") as f:
        f.write(harness)

    build_harness = subprocess.run(
        [
            "rustc", harness_path,
            "--edition=2021",
            "--extern", f"audited_submission={rlib_path}",
            "-o", binary_path,
        ],
        capture_output=True,
        text=True,
    )
    assert build_harness.returncode == 0, (
        "Could not compile behavioral harness:\n"
        + build_harness.stdout + build_harness.stderr
    )

    result = subprocess.run(
        [binary_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "get_priority_worker failed independent behavioral tests:\n"
        + result.stdout + result.stderr
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
