#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import stat
import codecs
import secrets
import subprocess
import zlib
import pytest

PROJECT = "/home/user/crypto-wrapper"
WRAPPER = os.path.join(PROJECT, "wrapper")
FINAL = "/home/user/final.txt"
SCRIPT = "/home/user/test.sh"


def test_00_execute_orchestration_script():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"File {SCRIPT} is not executable."

    # Ensure the script itself must recreate both requested artifacts.
    for path in (WRAPPER, FINAL):
        if os.path.lexists(path):
            assert not os.path.isdir(path), f"Expected a file at {path}, not a directory."
            os.unlink(path)

    result = subprocess.run(
        ["/usr/sbin/runuser", "-u", "user", "--", "/usr/bin/env", "-u", "LD_LIBRARY_PATH", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"test.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_test_sh_exists_and_executable():
    path = "/home/user/test.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_wrapper_binary_exists_and_executable():
    path = "/home/user/crypto-wrapper/wrapper"
    assert os.path.isfile(path), f"Binary {path} is missing. Did test.sh build the Go application?"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wrapper is not an ELF executable."

    result = subprocess.run(
        ["go", "version", "-m", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, "wrapper is not a valid Go-built executable."


def test_main_go_fixed():
    path = "/home/user/crypto-wrapper/main.go"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "LDFLAGS" in content and "-lcrypto" in content, "main.go does not seem to have the correct #cgo LDFLAGS directive."


def test_wrapper_links_to_supplied_library():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT
    result = subprocess.run(
        ["ldd", WRAPPER],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"Unable to inspect wrapper dependencies: {output}"
    crypto_lines = [line for line in output.splitlines() if "libcrypto.so" in line]
    assert crypto_lines, f"wrapper is not dynamically linked against libcrypto.so. ldd output:\n{output}"
    assert all("not found" not in line for line in crypto_lines), f"libcrypto.so was not found:\n{output}"
    assert any(PROJECT in line for line in crypto_lines), f"wrapper did not resolve the supplied libcrypto.so:\n{output}"


def expected_output(value):
    encoded = codecs.encode(value, "rot_13")
    checksum = zlib.crc32(encoded.encode("utf-8")) & 0xffffffff
    return f"{encoded}:{checksum}"


def test_wrapper_executes_correctly_on_derived_inputs():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT
    inputs = [
        "HelloWebSecurity",
        "GoCgoTest" + secrets.token_hex(8),
        "MixedCaseXYZabc" + secrets.token_hex(10),
    ]
    for value in inputs:
        result = subprocess.run(
            [WRAPPER, value],
            cwd=PROJECT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"wrapper failed for input {value!r}. stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert result.stdout.strip() == expected_output(value), (
            f"Incorrect wrapper output for input {value!r}: {result.stdout!r}"
        )


def test_final_txt_exists_and_correct():
    path = "/home/user/final.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did test.sh generate it?"

    with open(path, "r") as f:
        encoded_content = f.read().strip()

    try:
        decoded_bytes = base64.b64decode(encoded_content)
        decoded_str = decoded_bytes.decode('utf-8', errors='replace')
    except Exception as e:
        pytest.fail(f"Failed to decode base64 content in {path}: {e}")

    expected_substring = "UryybJroFrphevgl:3948574326"
    assert expected_substring in decoded_str, f"Decoded content does not contain the expected output. Got: {decoded_str}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
