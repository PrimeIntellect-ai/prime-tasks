#!/bin/bash
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:/home/user/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pytest

def test_asm_parser_fixed_target_arch():
    asm_parser_path = "/home/user/rust_pipeline/src/asm_parser.rs"
    assert os.path.isfile(asm_parser_path), f"{asm_parser_path} is missing"

    with open(asm_parser_path, "r") as f:
        content = f.read()

    assert 'target_arch = "x86-64"' not in content, "The target_arch bug 'x86-64' is still present in asm_parser.rs"
    assert 'target_arch = "x86_64"' in content, "The target_arch should be fixed to 'x86_64' in asm_parser.rs"

def test_asm_parser_fixed_asm_block():
    asm_parser_path = "/home/user/rust_pipeline/src/asm_parser.rs"
    assert os.path.isfile(asm_parser_path), f"{asm_parser_path} is missing"

    with open(asm_parser_path, "r") as f:
        content = f.read()

    assert re.search(r'mov\s+[^,]+,\s*42', content, re.IGNORECASE) is not None, \
        "The asm! block does not seem to correctly load 42 into the register."

def test_migration_tests_fixed():
    tests_path = "/home/user/rust_pipeline/tests/migration_tests.rs"
    assert os.path.isfile(tests_path), f"{tests_path} is missing"

    with open(tests_path, "r") as f:
        content = f.read()

    assert re.search(r'processed_timestamp\s*:\s*0', content) is not None, \
        "The missing `processed_timestamp: 0` field was not added to the RecordV2 instantiation in tests/migration_tests.rs"

def test_success_log_exists_and_passed():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. Did you run tests and redirect output?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "test result: ok" in content, "The success.log does not indicate that the tests passed."
    assert "2 passed" in content, "The success.log does not indicate that 2 tests passed."
TEST_EOF

verify() {
    cd /home/user/rust_pipeline || return 1

    cargo build --features fast_asm || return 1
    cargo test --features fast_asm || return 1

    migration_output="$(cargo test --features fast_asm --test migration_tests 2>&1)" || {
        printf '%s\n' "$migration_output"
        return 1
    }
    printf '%s\n' "$migration_output"
    printf '%s\n' "$migration_output" | grep -q 'test result: ok' || return 1
    printf '%s\n' "$migration_output" | grep -Eq '2 passed' || return 1

    rm -rf /tmp/rust_pipeline_verifier_probe
    mkdir -p /tmp/rust_pipeline_verifier_probe/src
    cat << 'CARGO_EOF' > /tmp/rust_pipeline_verifier_probe/Cargo.toml
[package]
name = "rust_pipeline_verifier_probe"
version = "0.1.0"
edition = "2021"

[dependencies]
rust_pipeline = { path = "/home/user/rust_pipeline", features = ["fast_asm"] }
CARGO_EOF
    cat << 'RUST_EOF' > /tmp/rust_pipeline_verifier_probe/src/lib.rs
#[cfg(test)]
mod tests {
    use rust_pipeline::asm_parser::get_magic_number;
    use rust_pipeline::schema::{migrate, RecordV1, RecordV2};

    #[test]
    fn public_api_and_fast_asm_work() {
        assert_eq!(get_magic_number(), 42);

        let migrated = migrate(RecordV1 {
            id: 7,
            payload: "probe".to_string(),
        });
        assert_eq!(migrated.id, 7);
        assert_eq!(migrated.payload, "probe");

        let fixture = RecordV2 {
            id: 7,
            payload: "probe".to_string(),
            processed_timestamp: 0u64,
        };
        assert_eq!(fixture.processed_timestamp, 0);
    }
}
RUST_EOF

    cargo test --offline --manifest-path /tmp/rust_pipeline_verifier_probe/Cargo.toml || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
