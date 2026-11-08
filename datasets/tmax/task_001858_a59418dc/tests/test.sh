#!/bin/bash
set +e
mkdir -p /logs/verifier

verify() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_patch_applied():
    c_src_path = "/home/user/release_prep/c_src/route_parser.c"
    assert os.path.isfile(c_src_path), f"File {c_src_path} is missing."
    with open(c_src_path, "r") as f:
        content = f.read()

    assert "strncpy(out_buf, id_start, out_len);" in content, "The patch was not applied correctly to route_parser.c (missing strncpy)."
    assert "strcpy(out_buf, id_start);" not in content, "The buggy strcpy is still present in route_parser.c."

def test_lib_rs_implemented():
    lib_rs_path = "/home/user/release_prep/rust_wrapper/src/lib.rs"
    assert os.path.isfile(lib_rs_path), f"File {lib_rs_path} is missing."
    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "proptest" in content, "The proptest crate is not used in lib.rs."
    assert "test_extract_valid_urls" in content, "The test 'test_extract_valid_urls' is not defined in lib.rs."
    assert "extract_item_id" in content, "The FFI function 'extract_item_id' is not declared/called in lib.rs."

def test_cargo_test_log():
    log_path = "/home/user/release_test.log"
    assert os.path.isfile(log_path), f"The log file {log_path} is missing. Did you run cargo test and redirect the output?"
    with open(log_path, "r") as f:
        content = f.read()

    assert "test_extract_valid_urls" in content, "The log does not show 'test_extract_valid_urls' being run."
    assert "test result: ok" in content or "test test_extract_valid_urls ... ok" in content, "The test suite did not pass successfully according to the log."
TEST_EOF
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # The files which the instruction explicitly forbids changing must remain intact.
    cat << 'EOF' > /tmp/expected_build.rs
fn main() {
    cc::Build::new()
        .file("../c_src/route_parser.c")
        .compile("route_parser");
    println!("cargo:rerun-if-changed=../c_src/route_parser.c");
}
EOF
    cat << 'EOF' > /tmp/expected_Cargo.toml
[package]
name = "rust_wrapper"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[dev-dependencies]
proptest = "1.0"

[build-dependencies]
cc = "1.0"
EOF
    cmp -s /tmp/expected_build.rs /home/user/release_prep/rust_wrapper/build.rs || return 1
    cmp -s /tmp/expected_Cargo.toml /home/user/release_prep/rust_wrapper/Cargo.toml || return 1

    # Compile and exercise the submitted C implementation directly.
    gcc -shared -fPIC -Wall -Wextra -Werror \
        -I/home/user/release_prep/c_src \
        /home/user/release_prep/c_src/route_parser.c \
        -o /tmp/libroute_parser_verify.so || return 1
    cat << 'PY_EOF' > /tmp/check_c.py
import ctypes

lib = ctypes.CDLL('/tmp/libroute_parser_verify.so')
fn = lib.extract_item_id
fn.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_int]
fn.restype = ctypes.c_int

for item in (b'a', b'AbC123', b'Z9' * 10):
    buf = (ctypes.c_char * 33)()
    for i in range(33):
        buf[i] = b'#'
    assert fn(b'/api/item/' + item, ctypes.cast(buf, ctypes.c_void_p), 32) == 0
    assert bytes(buf[:len(item)]) == item
    assert buf[len(item)] == b'\0'
    assert buf[32] == b'#'

buf = (ctypes.c_char * 8)()
for i in range(8):
    buf[i] = b'#'
assert fn(b'/api/item/1234567', ctypes.cast(buf, ctypes.c_void_p), 7) == -1
assert bytes(buf) == b'########'
assert fn(b'/wrong/123', ctypes.cast(buf, ctypes.c_void_p), 8) == -1
PY_EOF
    python3 /tmp/check_c.py || return 1

    # Actually build and run the submitted project rather than trusting its log.
    cd /home/user/release_prep/rust_wrapper || return 1
    CARGO_TERM_COLOR=never timeout 240 cargo test > /tmp/actual_cargo_stdout 2> /tmp/actual_cargo_stderr || return 1
    grep -q 'test_extract_valid_urls' /tmp/actual_cargo_stdout || return 1
    grep -q 'test result: ok' /tmp/actual_cargo_stdout || return 1

    # Run the named test against an instrumented implementation. This confirms that
    # proptest generates many valid, diverse URLs, passes a 32-byte buffer through
    # FFI, and checks both the return value and extracted bytes.
    rm -rf /tmp/verify_release_prep
    mkdir -p /tmp/verify_release_prep || return 1
    cp -a /home/user/release_prep/c_src /tmp/verify_release_prep/ || return 1
    cp -a /home/user/release_prep/rust_wrapper /tmp/verify_release_prep/ || return 1
    rm -rf /tmp/verify_release_prep/rust_wrapper/target

    cat << 'C_EOF' > /tmp/verify_release_prep/c_src/route_parser.c
#include "route_parser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int extract_item_id(const char* url, char* out_buf, int out_len) {
    const char* mode = getenv("VERIFIER_MUTANT");
    const char* prefix = "/api/item/";
    if (!url || !out_buf || strncmp(url, prefix, 10) != 0) return -1;

    FILE* f = fopen("/tmp/ffi_calls.log", "a");
    if (f) {
        fprintf(f, "%s\t%d\n", url, out_len);
        fclose(f);
    }

    if (mode && strcmp(mode, "return_error") == 0) return -1;
    if (mode && strcmp(mode, "wrong_output") == 0) {
        if (out_len < 2) return -1;
        out_buf[0] = '!';
        out_buf[1] = '\0';
        return 0;
    }

    const char* id = url + 10;
    size_t n = strlen(id);
    if (n >= (size_t)out_len) return -1;
    memcpy(out_buf, id, n + 1);
    return 0;
}
C_EOF

    cd /tmp/verify_release_prep/rust_wrapper || return 1
    rm -f /tmp/ffi_calls.log
    CARGO_TERM_COLOR=never PROPTEST_CASES=32 timeout 240 cargo test test_extract_valid_urls \
        > /tmp/instrumented_stdout 2> /tmp/instrumented_stderr || return 1
    grep -q 'test_extract_valid_urls' /tmp/instrumented_stdout || return 1

    cat << 'PY_EOF' > /tmp/check_calls.py
import os
import re

path = '/tmp/ffi_calls.log'
assert os.path.isfile(path), 'The Rust test never called the C function'
ids = []
with open(path, encoding='utf-8') as f:
    for line in f:
        url, out_len = line.rstrip('\n').rsplit('\t', 1)
        assert out_len == '32', f'FFI test used output length {out_len}, not 32'
        assert re.fullmatch(r'/api/item/[A-Za-z0-9]{1,20}', url), f'invalid generated URL: {url!r}'
        ids.append(url[10:])
assert len(ids) >= 16, f'only {len(ids)} generated calls were observed'
assert len(set(ids)) >= 8, 'the property test did not exercise diverse generated IDs'
PY_EOF
    python3 /tmp/check_calls.py || return 1

    # A conforming test must fail if the C return code is changed to -1.
    if CARGO_TERM_COLOR=never PROPTEST_CASES=8 VERIFIER_MUTANT=return_error timeout 120 \
        cargo test test_extract_valid_urls > /tmp/mutant_return_stdout 2> /tmp/mutant_return_stderr; then
        return 1
    fi

    # It must also fail when C reports success but returns bytes unequal to the ID.
    if CARGO_TERM_COLOR=never PROPTEST_CASES=8 VERIFIER_MUTANT=wrong_output timeout 120 \
        cargo test test_extract_valid_urls > /tmp/mutant_output_stdout 2> /tmp/mutant_output_stderr; then
        return 1
    fi

    return 0
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
