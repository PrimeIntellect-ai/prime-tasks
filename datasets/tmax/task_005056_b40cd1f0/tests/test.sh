#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

TINYVM = Path("/home/user/tinyvm")
DECODER = TINYVM / "src/decoder.rs"
LIBRARY = TINYVM / "target/release/libtinyvm.so"
RUNNER = TINYVM / "runner"
RESULT_LOG = Path("/home/user/result.log")
CANONICAL_HEX = "0119012302010A03FF"


def run(command, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(command, **kwargs)


def runner_env():
    env = os.environ.copy()
    release_dir = str(LIBRARY.parent)
    old_path = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = release_dir + ((":" + old_path) if old_path else "")
    return env


def invoke_runner(hex_string, env=None):
    result = run([str(RUNNER), hex_string], cwd=str(TINYVM), env=env or runner_env())
    assert result.returncode == 0, (
        f"runner failed for {hex_string!r}:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result.stdout


def test_decoder_fixed():
    assert DECODER.is_file(), f"{DECODER} is missing."
    content = DECODER.read_text()

    # Preserve the original source-level assertion.
    assert "b'A'..=b'F'" in content, (
        "The logic error in decoder.rs was not fixed. Missing support for "
        "uppercase hex characters (b'A'..=b'F')."
    )

    # Compile and exercise the submitted decoder directly, independently of
    # the repository's mutable Cargo tests.
    harness = r'''
#[path = "/home/user/tinyvm/src/decoder.rs"]
mod decoder;

fn main() {
    for value in 0u16..=255 {
        let expected = vec![value as u8];
        let upper = format!("{:02X}", value);
        let lower = format!("{:02x}", value);
        assert_eq!(decoder::decode_hex(&upper), Some(expected.clone()));
        assert_eq!(decoder::decode_hex(&lower), Some(expected));
    }

    assert_eq!(decoder::decode_hex(""), Some(Vec::new()));
    for invalid in ["0", "123", "GG", "g0", "0g", "-1", " 0", "0 ", "é"] {
        assert_eq!(decoder::decode_hex(invalid), None, "accepted invalid input: {:?}", invalid);
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="decoder-check-") as tmp:
        source = Path(tmp) / "main.rs"
        binary = Path(tmp) / "decoder_check"
        source.write_text(harness)
        compiled = run(["rustc", "--edition=2021", str(source), "-o", str(binary)])
        assert compiled.returncode == 0, (
            f"Could not compile decoder test harness:\n{compiled.stdout}\n{compiled.stderr}"
        )
        checked = run([str(binary)])
        assert checked.returncode == 0, (
            f"Submitted decoder failed behavioral checks:\n{checked.stdout}\n{checked.stderr}"
        )


def test_cargo_test_passes():
    assert TINYVM.is_dir(), f"{TINYVM} does not exist."
    result = run(["cargo", "test"], cwd=str(TINYVM))
    assert result.returncode == 0, (
        f"'cargo test' failed. Output:\n{result.stdout}\n{result.stderr}"
    )


def test_release_library_and_runner_pipeline():
    assert LIBRARY.is_file(), f"Release shared library {LIBRARY} is missing."
    assert LIBRARY.read_bytes()[:4] == b"\x7fELF", f"{LIBRARY} is not an ELF shared library."

    lib_header = run(["readelf", "-h", str(LIBRARY)])
    assert lib_header.returncode == 0 and "DYN (Shared object file)" in lib_header.stdout, (
        f"{LIBRARY} is not an ELF shared object.\n{lib_header.stdout}\n{lib_header.stderr}"
    )
    lib_symbols = run(["readelf", "-Ws", str(LIBRARY)])
    assert lib_symbols.returncode == 0
    assert any("execute_hex" in line and "GLOBAL" in line for line in lib_symbols.stdout.splitlines()), (
        "The release library does not export execute_hex."
    )

    # Load and test the actual release artifact on verifier-generated programs.
    library = ctypes.CDLL(str(LIBRARY))
    library.execute_hex.argtypes = [ctypes.c_char_p]
    library.execute_hex.restype = ctypes.c_uint32

    cases = [(25, 35, 10), (0xAB, 0x2F, 0x31)]
    for _ in range(12):
        x = secrets.randbelow(255) + 1
        y = secrets.randbelow(255) + 1
        z = secrets.randbelow(min(x + y - 1, 255) + 1)
        cases.append((x, y, z))

    for index, (x, y, z) in enumerate(cases):
        bytecode = bytes([0x01, x, 0x01, y, 0x02, 0x01, z, 0x03, 0xFF])
        hex_string = bytecode.hex().upper() if index % 2 == 0 else bytecode.hex()
        expected = x + y - z
        actual = library.execute_hex(hex_string.encode("ascii"))
        assert actual == expected, (
            f"Release libtinyvm.so returned {actual} for {hex_string}, expected {expected}."
        )

    # Preserve the original executable checks, while requiring a real ELF C runner.
    assert RUNNER.is_file(), f"The compiled executable {RUNNER} is missing."
    assert os.access(RUNNER, os.X_OK), f"The file {RUNNER} is not executable."
    assert RUNNER.read_bytes()[:4] == b"\x7fELF", f"{RUNNER} is not a compiled ELF executable."

    runner_dynamic = run(["readelf", "-d", str(RUNNER)])
    assert runner_dynamic.returncode == 0, runner_dynamic.stderr
    assert re.search(r"NEEDED.*libtinyvm\.so", runner_dynamic.stdout), (
        "runner is not dynamically linked against libtinyvm.so."
    )
    runner_symbols = run(["readelf", "-Ws", str(RUNNER)])
    assert runner_symbols.returncode == 0, runner_symbols.stderr
    assert any("UND" in line and re.search(r"\bexecute_hex(?:@|$)", line) for line in runner_symbols.stdout.splitlines()), (
        "runner does not import execute_hex from the shared library."
    )

    # Exercise the runner with unpredictable programs and the real release library.
    for index, (x, y, z) in enumerate(cases):
        bytecode = bytes([0x01, x, 0x01, y, 0x02, 0x01, z, 0x03, 0xFF])
        hex_string = bytecode.hex().upper() if index % 2 == 0 else bytecode.hex()
        expected_output = f"Result: {x + y - z}\n"
        assert invoke_runner(hex_string) == expected_output

    # Replace the library briefly with a verifier-generated shim. This proves
    # that runner actually calls execute_hex rather than merely containing an
    # unused dynamic reference while calculating results itself.
    sentinel = secrets.randbelow(2**31 - 1000) + 1000
    with tempfile.TemporaryDirectory(prefix="runner-shim-") as tmp:
        shim_source = Path(tmp) / "shim.c"
        shim_output = Path(tmp) / "libtinyvm.so"
        shim_source.write_text(
            "#include <stdint.h>\n"
            f"uint32_t execute_hex(const char *s) {{ (void)s; return {sentinel}u; }}\n"
        )
        compiled = run(["gcc", "-shared", "-fPIC", str(shim_source), "-o", str(shim_output)])
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr

        token = secrets.token_hex(8)
        backup = LIBRARY.parent / f".libtinyvm.so.verifier-backup-{token}"
        staged = LIBRARY.parent / f".libtinyvm.so.verifier-shim-{token}"
        shutil.copy2(shim_output, staged)
        os.replace(LIBRARY, backup)
        try:
            os.replace(staged, LIBRARY)
            output = invoke_runner("00", env=runner_env())
            assert output == f"Result: {sentinel}\n", (
                "runner did not call execute_hex from the linked shared library."
            )
        finally:
            if backup.exists():
                os.replace(backup, LIBRARY)
            if staged.exists():
                staged.unlink()


def test_result_log():
    assert RESULT_LOG.is_file(), f"The result log {RESULT_LOG} is missing."
    content = RESULT_LOG.read_text()

    # Preserve the original exact result assertion.
    assert content.strip() == "Result: 50", (
        f"Expected {RESULT_LOG} to contain 'Result: 50', but got: {content!r}"
    )

    # Confirm that this is also the actual stdout of the completed pipeline for
    # the required hand-assembled program.
    actual_stdout = invoke_runner(CANONICAL_HEX)
    assert actual_stdout == "Result: 50\n"
    assert content == actual_stdout, (
        "result.log is not the exact standard output produced by runner."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
