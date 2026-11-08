#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:/opt/rust/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path("/home/user/hailstone_ffi")
C_DIR = ROOT / "c_src"
RUST_DIR = ROOT / "rust_src"
RESULT = Path("/home/user/result.txt")


def run(cmd, cwd, timeout=120):
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=timeout,
    )


def compute_max_hailstone(start: int) -> int:
    n = start
    max_val = n
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        if n > max_val:
            max_val = n
    return max_val


def read_result():
    assert RESULT.is_file(), f"Result file {RESULT} is missing."
    return RESULT.read_text().strip()


def test_result_file():
    expected_max = compute_max_hailstone(77031)
    result_path = "/home/user/result.txt"

    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == str(expected_max), f"Expected maximum value {expected_max}, but got '{content}' in {result_path}."


def test_makefile_fixed():
    makefile_path = "/home/user/hailstone_ffi/c_src/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "ar " in content and "libfastmath.a" in content, "Makefile does not seem to be fixed to use 'ar' for creating the static library."
    assert "gcc -o libfastmath.a" not in content, "Makefile still contains the buggy 'gcc -o libfastmath.a' line."


def test_build_rs_exists():
    build_rs_path = "/home/user/hailstone_ffi/rust_src/build.rs"
    assert os.path.isfile(build_rs_path), f"build.rs {build_rs_path} is missing."

    with open(build_rs_path, "r") as f:
        content = f.read()

    assert "cargo:rustc-link-search=" in content or "cargo:rustc-link-lib=" in content, "build.rs does not contain Cargo linking instructions."


def test_rust_files_modified():
    lib_path = "/home/user/hailstone_ffi/rust_src/src/lib.rs"
    main_path = "/home/user/hailstone_ffi/rust_src/src/main.rs"

    assert os.path.isfile(lib_path), f"{lib_path} is missing."
    assert os.path.isfile(main_path), f"{main_path} is missing."

    with open(lib_path, "r") as f:
        lib_content = f.read()
    with open(main_path, "r") as f:
        main_content = f.read()

    assert "Iterator" in lib_content and "next" in lib_content, "lib.rs does not seem to implement the Iterator trait."
    assert "extern" in lib_content or "extern" in main_content, "No FFI 'extern' block found in the Rust source files."

    # Require these constructs in actual Rust code rather than only in comments.
    code = re.sub(r"/\*.*?\*/", "", lib_content, flags=re.S)
    code = re.sub(r"//.*", "", code)
    main_code = re.sub(r"/\*.*?\*/", "", main_content, flags=re.S)
    main_code = re.sub(r"//.*", "", main_code)
    assert re.search(r"pub\s+struct\s+HailstoneSeq\b", code)
    assert re.search(r"impl\s+Iterator\s+for\s+HailstoneSeq\b", code)
    assert re.search(r"type\s+Item\s*=\s*u64\s*;", code)
    assert re.search(r"fn\s+next\s*\(\s*&mut\s+self\s*\)", code)
    assert re.search(r"extern\s+\"C\"", code)
    assert "next_hailstone" in code
    assert "HailstoneSeq" in main_code, "main.rs must use the custom iterator."


def test_build_archive_link_and_execute_program():
    expected = str(compute_max_hailstone(77031))

    run(["make", "clean"], C_DIR)
    run(["make"], C_DIR)

    archive = C_DIR / "libfastmath.a"
    assert archive.is_file(), "make did not create libfastmath.a"
    members = run(["ar", "t", str(archive)], C_DIR).stdout.splitlines()
    assert any(name.endswith("fast_math.o") for name in members), "Archive does not contain fast_math.o"
    symbols = run(["nm", "-g", "--defined-only", str(archive)], C_DIR).stdout
    assert re.search(r"\bnext_hailstone\b", symbols), "Archive does not define next_hailstone"

    # Exercise the archive independently on answers derived by the verifier.
    harness = Path("/tmp/check_fast_math.c")
    harness.write_text(r'''#include <stdint.h>
#include <stdio.h>
#include "fast_math.h"
int main(void) {
    const uint64_t in[] = {1, 2, 3, 10, 27, 77031};
    for (unsigned i = 0; i < sizeof(in)/sizeof(in[0]); ++i)
        printf("%llu\n", (unsigned long long)next_hailstone(in[i]));
    return 0;
}
''')
    run(["gcc", "-I", str(C_DIR), str(harness), str(archive), "-o", "/tmp/check_fast_math"], C_DIR)
    got = run(["/tmp/check_fast_math"], C_DIR).stdout.splitlines()
    inputs = [1, 2, 3, 10, 27, 77031]
    wanted = [str(n // 2 if n % 2 == 0 else 3 * n + 1) for n in inputs]
    assert got == wanted, f"C archive returned {got}, expected {wanted}"

    run(["cargo", "clean"], RUST_DIR)
    run(["cargo", "build"], RUST_DIR, timeout=180)
    RESULT.write_text("verifier-sentinel")
    run(["cargo", "run", "--quiet"], RUST_DIR, timeout=180)
    assert read_result() == expected, "Running the Rust program did not produce the required result."

    binary = RUST_DIR / "target" / "debug" / "hailstone_rust"
    assert binary.is_file(), "Cargo did not produce the Rust executable."
    linked_symbols = run(["nm", str(binary)], RUST_DIR).stdout
    assert re.search(r"\bnext_hailstone\b", linked_symbols), "The Rust executable does not contain the linked C function."

    # Temporarily substitute a deterministic C transition. A real Rust iterator
    # using the FFI must now observe 77031 -> 9000000000 -> 1 and compute that max.
    c_source = C_DIR / "fast_math.c"
    original_c = c_source.read_bytes()
    probe_max = "9000000000"
    try:
        c_source.write_text(r'''#include <stdint.h>
uint64_t next_hailstone(uint64_t n) {
    if (n == UINT64_C(77031)) return UINT64_C(9000000000);
    if (n == UINT64_C(9000000000)) return UINT64_C(1);
    return UINT64_C(1);
}
''')
        run(["make", "clean"], C_DIR)
        run(["make"], C_DIR)
        run(["cargo", "clean"], RUST_DIR)
        RESULT.write_text("verifier-sentinel")
        run(["cargo", "run", "--quiet"], RUST_DIR, timeout=180)
        assert read_result() == probe_max, (
            "The Rust program did not follow the C FFI transitions through "
            "HailstoneSeq when computing the maximum."
        )
    finally:
        c_source.write_bytes(original_c)
        run(["make", "clean"], C_DIR)
        run(["make"], C_DIR)
        run(["cargo", "clean"], RUST_DIR)
        run(["cargo", "build"], RUST_DIR, timeout=180)
        RESULT.write_text("verifier-sentinel")
        run(["cargo", "run", "--quiet"], RUST_DIR, timeout=180)

    assert read_result() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
