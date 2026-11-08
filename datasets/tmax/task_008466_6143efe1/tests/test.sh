#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /home/user/app/src/bin

cat << 'RUST_EOF' > /home/user/app/src/bin/verifier_probe.rs
mod submitted {
    include!("/home/user/app/src/main.rs");

    #[cfg(test)]
    mod behavioral_tests {
        use super::*;
        use std::time::{SystemTime, UNIX_EPOCH};

        fn unique_id(offset: u64) -> u64 {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos() as u64;
            nanos ^ (u64::from(std::process::id()).rotate_left(17)) ^ offset
        }

        #[tokio::test]
        async fn timeout_and_success_paths_remove_only_their_cache_entries() {
            let timeout_id = unique_id(0x1357_2468);
            let success_id = timeout_id.wrapping_add(1);
            let unrelated_id = timeout_id.wrapping_add(2);

            {
                let mut cache = CACHE.lock().unwrap();
                cache.insert(timeout_id, "preexisting-timeout-resource".to_string());
                cache.insert(success_id, "preexisting-success-resource".to_string());
                cache.insert(unrelated_id, "unrelated-resource".to_string());
            }

            process_request(timeout_id, "timeout-payload".to_string(), true).await;
            {
                let cache = CACHE.lock().unwrap();
                assert!(
                    !cache.contains_key(&timeout_id),
                    "timed-out request remained in CACHE"
                );
                assert_eq!(
                    cache.get(&unrelated_id).map(String::as_str),
                    Some("unrelated-resource"),
                    "cleanup removed an unrelated request"
                );
            }

            process_request(success_id, "success-payload".to_string(), false).await;
            {
                let cache = CACHE.lock().unwrap();
                assert!(
                    !cache.contains_key(&success_id),
                    "successfully completed request remained in CACHE"
                );
                assert_eq!(
                    cache.get(&unrelated_id).map(String::as_str),
                    Some("unrelated-resource"),
                    "cleanup removed an unrelated request"
                );
            }

            CACHE.lock().unwrap().remove(&unrelated_id);
        }
    }
}

fn main() {}
RUST_EOF

trap 'rm -f /home/user/app/src/bin/verifier_probe.rs' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_leak_report_content():
    report_path = "/home/user/leak_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, found {len(lines)}."
    assert lines[0] == "GHOST_ORPHAN_9921_DATA", f"Line 1 expected 'GHOST_ORPHAN_9921_DATA', got '{lines[0]}'."
    assert lines[1] == "1003", f"Line 2 expected '1003', got '{lines[1]}'."


def test_rust_code_fixed():
    main_rs_path = "/home/user/app/src/main.rs"
    assert os.path.isfile(main_rs_path), f"File {main_rs_path} does not exist."

    with open(main_rs_path, "r") as f:
        content = f.read()

    has_remove_in_timeout = re.search(
        r'if\s+timeout\s*\{[^}]*CACHE\.lock\(\)\.unwrap\(\)\.remove\(&id\);[^}]*\}',
        content,
    )
    removed_early_return = not re.search(
        r'if\s+timeout\s*\{[^}]*return;[^}]*\}', content
    )
    used_drop_guard = "Drop" in content and "impl" in content

    assert has_remove_in_timeout or removed_early_return or used_drop_guard, \
        "The memory leak is not fixed. The request is not removed from CACHE when a timeout occurs."


def test_rust_project_compiles():
    result = subprocess.run(
        ["cargo", "check"],
        cwd="/home/user/app",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"'cargo check' failed:\n{result.stderr}"


def test_cache_cleanup_behavior():
    result = subprocess.run(
        ["cargo", "test", "--bin", "verifier_probe", "--", "--nocapture"],
        cwd="/home/user/app",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "Behavioral cache-cleanup test failed:\n"
        + result.stdout
        + "\n"
        + result.stderr
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
