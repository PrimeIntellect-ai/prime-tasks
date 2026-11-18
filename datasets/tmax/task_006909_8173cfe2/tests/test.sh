#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile


def test_loop_trigger():
    """Verify that the loop trigger byte was correctly identified and saved."""
    path = "/home/user/loop_trigger.txt"
    assert os.path.exists(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content.upper() == "FF", f"Expected 'FF' in {path}, got '{content}'."


def test_fixed_parser_compiles_and_runs():
    """Verify that the fixed parser compiles and correctly processes a test payload without panicking or looping."""
    src_path = "/home/user/fixed_parser.rs"
    bin_path = "/home/user/fixed_parser"
    test_bin = "/home/user/test.bin"

    assert os.path.exists(src_path), f"{src_path} does not exist."
    assert os.path.isfile(src_path), f"{src_path} is not a regular file."

    # Compile the fixed Rust source
    compile_proc = subprocess.run(
        ["rustc", src_path, "-o", bin_path],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"
    assert os.path.exists(bin_path), "Executable was not created after compilation."

    # Create a test payload: 0x01, 0xFF (trigger), 0x02
    # Expected sum: 1 + 1 (from 0xFF logic) + 2 = 4
    with open(test_bin, "wb") as f:
        f.write(b"\x01\xFF\x02")

    # Run the compiled binary
    try:
        run_proc = subprocess.run(
            [bin_path, test_bin],
            capture_output=True,
            text=True,
            timeout=2
        )
    except subprocess.TimeoutExpired:
        assert False, "Execution timed out. The infinite loop bug might not be fixed."

    assert run_proc.returncode == 0, f"Execution failed (possibly out-of-bounds panic):\n{run_proc.stderr}"
    assert "Parsed: Some(4)" in run_proc.stdout, f"Unexpected output:\n{run_proc.stdout}"


def test_parser_general_behavior_on_derived_inputs():
    """Exercise boundaries, trigger handling, and non-fixed random payloads."""
    src_path = "/home/user/fixed_parser.rs"
    assert os.path.isfile(src_path), f"{src_path} is not a regular file."

    with tempfile.TemporaryDirectory(prefix="parser_verify_") as temp_dir:
        bin_path = os.path.join(temp_dir, "fixed_parser")
        compile_proc = subprocess.run(
            ["rustc", src_path, "-o", bin_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"
        assert os.path.isfile(bin_path), "Executable was not created after compilation."

        payloads = [
            b"",
            b"\x00",
            b"\x01",
            b"\xFF",
            b"\xFF\xFF",
            b"\x00\xFF\x00",
            bytes(range(256)),
            bytes(reversed(range(256))),
        ]

        # These inputs are generated only when verification runs, so their expected
        # answers cannot be satisfied by hard-coding the verifier's fixed examples.
        for _ in range(12):
            length = 1 + secrets.randbelow(8192)
            payload = bytearray(secrets.token_bytes(length))
            payload[secrets.randbelow(length)] = 0xFF
            payloads.append(bytes(payload))

        for index, payload in enumerate(payloads):
            payload_path = os.path.join(temp_dir, f"payload_{index}_{secrets.token_hex(8)}.bin")
            with open(payload_path, "wb") as f:
                f.write(payload)

            expected = sum(1 if value == 0xFF else value for value in payload) & 0xFFFFFFFF
            try:
                run_proc = subprocess.run(
                    [bin_path, payload_path],
                    capture_output=True,
                    text=True,
                    timeout=2,
                )
            except subprocess.TimeoutExpired:
                assert False, f"Execution timed out for payload {index}."

            assert run_proc.returncode == 0, (
                f"Execution failed for payload {index}:\n{run_proc.stderr}"
            )
            output = run_proc.stdout.strip()
            assert re.fullmatch(r"Parsed: Some\(\d+\)", output), (
                f"Malformed output for payload {index}: {run_proc.stdout!r}"
            )
            assert output == f"Parsed: Some({expected})", (
                f"Wrong result for payload {index}: expected {expected}, got {output!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
