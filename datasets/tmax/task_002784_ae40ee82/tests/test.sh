#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import subprocess
import tempfile

ROOT = "/home/user/data_parser"
CI = os.path.join(ROOT, "ci.sh")
SO = os.path.join(ROOT, "librust_parser.so")
OUTPUT = os.path.join(ROOT, "output.json")
LIB_RS = os.path.join(ROOT, "src", "lib.rs")
PARSER = os.path.join(ROOT, "parser.py")


def run_ci(timeout=60):
    return subprocess.run(
        ["bash", CI], cwd=ROOT, capture_output=True, text=True, timeout=timeout
    )


def test_ci_script_execution():
    """Run ci.sh and check if it succeeds and produces a real shared library."""
    assert os.path.isfile(CI), f"CI script {CI} is missing."

    for path in (SO, OUTPUT):
        if os.path.lexists(path):
            os.unlink(path)

    result = run_ci()
    assert result.returncode == 0, (
        f"ci.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(SO), f"Shared library {SO} was not built by the CI script."
    with open(SO, "rb") as f:
        assert f.read(4) == b"\x7fELF", "librust_parser.so is not an ELF shared library."


def test_output_json_content():
    """Check that output.json contains exactly the integer 8472."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == "8472", (
        f"Expected output.json to contain exactly '8472', but found '{content}'"
    )


def test_rust_memory_management():
    """Retain the source checks and compile/exercise the submitted Rust library."""
    assert os.path.isfile(LIB_RS), f"Rust file {LIB_RS} is missing."
    with open(LIB_RS, "r") as f:
        content = f.read()

    assert "from_raw" in content or "drop" in content or "CString" in content, \
        "lib.rs does not seem to contain a mechanism to free the allocated string (e.g., CString::from_raw)."
    assert "into_raw" in content, "lib.rs does not seem to use into_raw() to pass ownership to C."

    with tempfile.TemporaryDirectory() as td:
        built_so = os.path.join(td, "submitted.so")
        compiled = subprocess.run(
            ["rustc", "--crate-type", "cdylib", LIB_RS, "-o", built_so],
            cwd=ROOT, capture_output=True, text=True, timeout=60
        )
        assert compiled.returncode == 0, f"Submitted Rust does not compile: {compiled.stderr}"

        exercise = r'''
import ctypes, json, sys
lib = ctypes.CDLL(sys.argv[1])
lib.process_data.argtypes = []
lib.process_data.restype = ctypes.c_void_p
lib.free_string.argtypes = [ctypes.c_void_p]
lib.free_string.restype = None

p = lib.process_data()
assert p
obj = json.loads(ctypes.string_at(p).decode("utf-8"))
assert obj["payload"]["id"] == 8472
lib.free_string(p)

# Repeated allocation/free distinguishes a working deallocator from a no-op
# that merely has the expected keywords in dead code.
def rss_kb():
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    return 0

for _ in range(1000):
    p = lib.process_data()
    assert p and ctypes.string_at(p, 1)
    lib.free_string(p)
before = rss_kb()
for _ in range(300000):
    p = lib.process_data()
    assert p and ctypes.string_at(p, 1)
    lib.free_string(p)
after = rss_kb()
assert after - before < 12288, (before, after)
'''
        checked = subprocess.run(
            ["python3", "-c", exercise, built_so],
            capture_output=True, text=True, timeout=60
        )
        assert checked.returncode == 0, (
            "The compiled Rust ABI, returned JSON, or free_string implementation is invalid. "
            f"stdout: {checked.stdout} stderr: {checked.stderr}"
        )


def test_python_memory_management():
    """Retain the source check that parser.py calls a library free function."""
    assert os.path.isfile(PARSER), f"Python file {PARSER} is missing."
    with open(PARSER, "r") as f:
        content = f.read()
    assert "lib." in content and ("free" in content or "drop" in content), \
        "parser.py does not seem to call a free function from the Rust library to prevent memory leaks."


def test_ci_and_parser_on_derived_input_and_observe_free_call():
    """Use a fresh Rust payload to prove CI compiles/runs and Python parses and frees it."""
    probe_id = secrets.randbelow(800000000) + 100000000
    marker = f"/tmp/data_parser_freed_{secrets.token_hex(8)}"
    data = json.dumps({"status": "success", "payload": {"id": probe_id, "msg": "probe"}}, separators=(",", ":"))
    probe_source = '''
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn process_data() -> *mut c_char {
    CString::new(r#"%s"#).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _owned = CString::from_raw(ptr);
    }
    std::fs::write(r#"%s"#, b"freed").unwrap();
}
''' % (data, marker)

    with open(LIB_RS, "rb") as f:
        original_source = f.read()

    probe_result = None
    probe_output = None
    free_observed = False
    restore_result = None
    try:
        with open(LIB_RS, "w") as f:
            f.write(probe_source)
        for path in (SO, OUTPUT, marker):
            if os.path.lexists(path):
                os.unlink(path)

        probe_result = run_ci()
        if os.path.isfile(OUTPUT):
            with open(OUTPUT, "r") as f:
                probe_output = f.read().strip()
        free_observed = os.path.isfile(marker)
    finally:
        with open(LIB_RS, "wb") as f:
            f.write(original_source)
        if os.path.lexists(marker):
            os.unlink(marker)
        for path in (SO, OUTPUT):
            if os.path.lexists(path):
                os.unlink(path)
        restore_result = run_ci()

    assert probe_result is not None and probe_result.returncode == 0, (
        "ci.sh did not compile the replacement Rust source and run parser.py. "
        f"stderr: {getattr(probe_result, 'stderr', '')}"
    )
    assert probe_output == str(probe_id), (
        f"parser.py did not derive payload.id from the Rust JSON; expected {probe_id}, got {probe_output!r}"
    )
    assert free_observed, "parser.py did not invoke the Rust free_string function on the returned pointer."
    assert restore_result.returncode == 0, f"ci.sh failed after restoring submitted Rust: {restore_result.stderr}"
    with open(OUTPUT, "r") as f:
        assert f.read().strip() == "8472"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
