#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

WORK_DIR="$(mktemp -d /tmp/ws_encoder_verifier.XXXXXX)"
PROJECT_TARGET="$WORK_DIR/project-target"
HARNESS_DIR="$WORK_DIR/rust-harness"
HARNESS_TARGET="$WORK_DIR/harness-target"
mkdir -p "$PROJECT_TARGET" "$HARNESS_DIR/src" "$HARNESS_TARGET"
chown -R user:user "$PROJECT_TARGET" "$HARNESS_TARGET"
trap 'rm -rf "$WORK_DIR"' EXIT

cat << 'TEST_EOF' > "$WORK_DIR/test_final_state.py"
import os
import re

BASE_DIR = "/home/user/ws_encoder_api"
TEST_RESULTS_LOG = "/home/user/test_results.log"

def test_test_results_log_exists_and_passed():
    assert os.path.isfile(TEST_RESULTS_LOG), f"Expected test results log at {TEST_RESULTS_LOG} is missing."
    with open(TEST_RESULTS_LOG, "r", encoding="utf-8") as f:
        content = f.read()
    assert "test result: ok" in content, "The test_results.log does not indicate that all tests passed ('test result: ok' not found)."
    assert "0 failed" in content, "The test_results.log indicates that some tests failed."

def test_build_rs_implemented():
    build_rs_path = os.path.join(BASE_DIR, "build.rs")
    assert os.path.isfile(build_rs_path), "build.rs is missing."
    with open(build_rs_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert len(content.strip()) > 0, "build.rs is still empty."
    assert "cc::" in content or "Build::new" in content, "build.rs does not appear to use the 'cc' crate to build the C code."
    assert "hex_encoder.c" in content, "build.rs does not reference 'hex_encoder.c'."

def test_c_memory_bug_fixed():
    c_file_path = os.path.join(BASE_DIR, "c_src", "hex_encoder.c")
    assert os.path.isfile(c_file_path), "hex_encoder.c is missing."
    with open(c_file_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.search(r'(malloc|calloc)\s*\([^;]*\+\s*1[^;]*\)', content) or re.search(r'len\s*\*\s*2\s*\+\s*1', content), \
        "hex_encoder.c does not appear to allocate space for the null terminator (expected +1 in allocation)."

def test_rate_limiter_implemented():
    rate_limit_path = os.path.join(BASE_DIR, "src", "rate_limit.rs")
    assert os.path.isfile(rate_limit_path), "rate_limit.rs is missing."
    with open(rate_limit_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "self.counts.entry" in content or "self.counts.get_mut" in content or "self.counts.insert" in content, \
        "rate_limit.rs does not appear to update the 'counts' HashMap."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORK_DIR/test_final_state.py" -x --tb=short >"$WORK_DIR/static-tests.log" 2>&1 || status=1

# Compile and run the submitted C implementation under AddressSanitizer. This
# catches the original one-byte heap overflow while also checking its output.
cat << 'C_EOF' > "$WORK_DIR/c_harness.c"
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "hex_encoder.h"

static char digit(unsigned int n) {
    return n < 10 ? (char)('0' + n) : (char)('a' + (n - 10));
}

int main(void) {
    unsigned char one[] = {0x00};
    char *s = encode_hex(one, 1);
    if (!s || strcmp(s, "00") != 0) return 1;
    free_hex(s);

    unsigned char input[256];
    for (size_t i = 0; i < sizeof(input); ++i) input[i] = (unsigned char)i;
    s = encode_hex(input, sizeof(input));
    if (!s) return 2;
    for (size_t i = 0; i < sizeof(input); ++i) {
        if (s[i * 2] != digit(input[i] >> 4) ||
            s[i * 2 + 1] != digit(input[i] & 15)) return 3;
    }
    if (s[sizeof(input) * 2] != '\0') return 4;
    free_hex(s);

    s = encode_hex(NULL, 0);
    if (!s || s[0] != '\0') return 5;
    free_hex(s);
    return 0;
}
C_EOF

cc -std=c11 -fsanitize=address -fno-omit-frame-pointer -g \
    -I/home/user/ws_encoder_api/c_src \
    /home/user/ws_encoder_api/c_src/hex_encoder.c "$WORK_DIR/c_harness.c" \
    -o "$WORK_DIR/c_harness" >"$WORK_DIR/c-build.log" 2>&1 || status=1
if [ -x "$WORK_DIR/c_harness" ]; then
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 timeout 30s "$WORK_DIR/c_harness" \
        >"$WORK_DIR/c-run.log" 2>&1 || status=1
fi

# Actually build and execute the project's own unit and integration tests from
# a fresh target directory rather than trusting the submitted log.
timeout 240s runuser -u user -- env HOME=/home/user CARGO_TARGET_DIR="$PROJECT_TARGET" \
    /usr/bin/cargo test --manifest-path /home/user/ws_encoder_api/Cargo.toml --all-targets \
    >"$WORK_DIR/project-cargo-test.log" 2>&1 || status=1

# A correct cc build named hex_encoder produces this archive in the fresh build.
find "$PROJECT_TARGET" -type f -name 'libhex_encoder.a' -print -quit | grep -q . || status=1

# Test the public API from a verifier-owned crate so submitted tests cannot
# replace or omit these behavioral cases.
cat << 'TOML_EOF' > "$HARNESS_DIR/Cargo.toml"
[package]
name = "ws_encoder_verifier_harness"
version = "0.1.0"
edition = "2021"

[dependencies]
ws_encoder_api = { path = "/home/user/ws_encoder_api" }
TOML_EOF

cat << 'RS_EOF' > "$HARNESS_DIR/src/lib.rs"
#[cfg(test)]
mod tests {
    use std::fmt::Write;
    use ws_encoder_api::{encode_data, rate_limit::RateLimiter};

    fn expected_hex(data: &[u8]) -> String {
        let mut result = String::with_capacity(data.len() * 2);
        for byte in data {
            write!(&mut result, "{:02x}", byte).unwrap();
        }
        result
    }

    #[test]
    fn encoding_matches_derived_results() {
        let cases = vec![
            Vec::new(),
            vec![0],
            vec![0xff, 0x10, 0x01, 0xab],
            (0u16..=255).map(|n| n as u8).collect(),
            (0..4097).map(|n| ((n * 73 + 19) & 0xff) as u8).collect(),
        ];
        for data in cases {
            assert_eq!(encode_data(&data), expected_hex(&data));
        }
    }

    #[test]
    fn rate_limit_is_per_client_and_stops_after_three() {
        let mut limiter = RateLimiter::new();
        for client in [7u32, 42, 999_999] {
            for request in 0..3 {
                assert!(limiter.check_and_record(client),
                        "client {client} request {request} should be allowed");
            }
            for _ in 0..3 {
                assert!(!limiter.check_and_record(client),
                        "client {client} should remain rejected after its third request");
            }
        }
    }
}
RS_EOF

chmod 777 "$HARNESS_DIR"
runuser -u user -- env HOME=/home/user CARGO_TARGET_DIR="$HARNESS_TARGET" \
    /usr/bin/cargo generate-lockfile --offline --manifest-path "$HARNESS_DIR/Cargo.toml" \
    >"$WORK_DIR/harness-lock.log" 2>&1 || status=1
chown root:root "$HARNESS_DIR" "$HARNESS_DIR/Cargo.toml" "$HARNESS_DIR/src" "$HARNESS_DIR/src/lib.rs" 2>/dev/null
chmod 755 "$HARNESS_DIR" "$HARNESS_DIR/src"
chmod 644 "$HARNESS_DIR/Cargo.toml" "$HARNESS_DIR/src/lib.rs"
[ ! -e "$HARNESS_DIR/Cargo.lock" ] || { chown root:root "$HARNESS_DIR/Cargo.lock"; chmod 644 "$HARNESS_DIR/Cargo.lock"; }

if [ -f "$HARNESS_DIR/Cargo.lock" ]; then
    timeout 240s runuser -u user -- env HOME=/home/user CARGO_TARGET_DIR="$HARNESS_TARGET" \
        /usr/bin/cargo test --offline --locked --manifest-path "$HARNESS_DIR/Cargo.toml" \
        >"$WORK_DIR/harness-cargo-test.log" 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
