#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import secrets
import string
import subprocess
import tempfile
import time

import pytest

SOURCE = "/home/user/rle_processor.c"
BINARY = "/home/user/rle_processor"


def test_c_program_exists_and_uses_locks():
    c_file = SOURCE
    assert os.path.isfile(c_file), f"C source file {c_file} is missing"

    with open(c_file, "r") as f:
        content = f.read()

    has_flock = "flock" in content and "LOCK_EX" in content
    has_fcntl = "fcntl" in content and "F_WRLCK" in content
    has_fcntl_fallback = "fcntl" in content and "F_SETLKW" in content

    assert has_flock or has_fcntl or has_fcntl_fallback, "C program must use flock() or fcntl() for exclusive file locking"


def test_compiled_program_exists():
    bin_file = BINARY
    assert os.path.isfile(bin_file), f"Compiled binary {bin_file} is missing"
    assert os.access(bin_file, os.X_OK), f"Compiled binary {bin_file} is not executable"
    with open(bin_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_file} is not a compiled ELF binary"


def test_master_doc_content():
    out_file = "/home/user/master_doc.txt"
    assert os.path.isfile(out_file), f"Output file {out_file} is missing"

    with open(out_file, "r") as f:
        content = f.read().strip()

    assert content in ["TTesstMaster", "MasterTTesst"], f"Content of {out_file} is incorrect. Expected 'TTesstMaster' or 'MasterTTesst', got '{content}'"
    assert "FAIL" not in content, f"Content of {out_file} contains data from the ignored old file"


@pytest.fixture(scope="session")
def rebuilt_binary(tmp_path_factory):
    path = tmp_path_factory.mktemp("build") / "rle_processor_rebuilt"
    result = subprocess.run(
        ["gcc", SOURCE, "-O2", "-o", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"C source does not compile:\n{result.stderr}"
    return str(path)


def encoded_case():
    alphabet = string.ascii_letters + "!@#_- "
    pairs = []
    # Always include multi-digit counts, with the rest unpredictable at verification time.
    counts = [secrets.randbelow(18) + 12] + [secrets.randbelow(9) + 1 for _ in range(5)]
    for count in counts:
        char = secrets.choice(alphabet)
        pairs.append((count, char))
    encoded = "".join(str(count) + char for count, char in pairs)
    decoded = "".join(char * count for count, char in pairs)
    return encoded.encode(), decoded.encode()


def check_rle_and_append(binary):
    with tempfile.TemporaryDirectory(prefix="rle-functional-") as td:
        output = os.path.join(td, "result.txt")
        prefix = ("existing-" + secrets.token_hex(10) + ":").encode()
        with open(output, "wb") as f:
            f.write(prefix)

        expected = prefix
        for index in range(3):
            encoded, decoded = encoded_case()
            input_path = os.path.join(td, f"input-{index}-{secrets.token_hex(5)}.rld")
            with open(input_path, "wb") as f:
                f.write(encoded)
            result = subprocess.run(
                [binary, input_path, output],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert result.returncode == 0, (
                f"{binary} failed on valid RLE input {encoded!r}: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            expected += decoded
            with open(output, "rb") as f:
                assert f.read() == expected, "Program did not correctly decompress and append its input"


def check_exclusive_lock(binary):
    with tempfile.TemporaryDirectory(prefix="rle-lock-") as td:
        input_path = os.path.join(td, "locked-input.rld")
        output_path = os.path.join(td, "locked-output.txt")
        count = secrets.randbelow(20) + 15
        char = secrets.choice(string.ascii_letters)
        encoded = f"{count}{char}3Z".encode()
        prefix = ("locked-prefix-" + secrets.token_hex(8)).encode()
        with open(input_path, "wb") as f:
            f.write(encoded)
        with open(output_path, "wb") as f:
            f.write(prefix)

        # Hold both BSD flock and POSIX fcntl locks so implementations using either
        # permitted API must wait before appending.
        with open(output_path, "r+b", buffering=0) as held:
            held.seek(0)
            fcntl.flock(held.fileno(), fcntl.LOCK_EX)
            fcntl.lockf(held.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [binary, input_path, output_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                time.sleep(0.75)
                assert proc.poll() is None, "Program did not wait for the output file's exclusive lock"
                with open(output_path, "rb") as check:
                    assert check.read() == prefix, "Program wrote to the output before acquiring its lock"
            finally:
                fcntl.lockf(held.fileno(), fcntl.LOCK_UN)
                fcntl.flock(held.fileno(), fcntl.LOCK_UN)

            try:
                stdout, stderr = proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                pytest.fail("Program did not finish after the output lock was released")

        assert proc.returncode == 0, f"Program failed after lock release: stdout={stdout!r}, stderr={stderr!r}"
        with open(output_path, "rb") as f:
            assert f.read() == prefix + char.encode() * count + b"ZZZ", "Locked append produced incorrect output"


def test_submitted_binary_decompresses_appends_and_locks():
    check_rle_and_append(BINARY)
    check_exclusive_lock(BINARY)


def test_submitted_source_decompresses_appends_and_locks(rebuilt_binary):
    check_rle_and_append(rebuilt_binary)
    check_exclusive_lock(rebuilt_binary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
