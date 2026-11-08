#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SOURCE = "/home/user/decrypt.cpp"
OUTPUT = "/home/user/admin_pass.txt"
BINARY = "/tmp/decrypt_submission"
EXPECTED_LITERAL = "Pwn3d_Pr0c_M3m0ry!"


def derive_expected_password():
    with open("/home/user/proc_logs.txt", "r") as f:
        logs = f.read()

    match = re.search(r"auth_helper\s+admin\s+([0-9a-fA-F]+)", logs)
    assert match, "Could not find the intercepted admin token in proc_logs.txt"
    ciphertext = bytes.fromhex(match.group(1))

    state = 0x37
    plaintext = bytearray()
    for encrypted_byte in ciphertext:
        state = (state * 13 + 37) % 256
        plaintext.append(encrypted_byte ^ state)
    return bytes(plaintext)


def test_decrypt_cpp_exists():
    assert os.path.isfile(SOURCE), f"Missing file: {SOURCE}. The task requires writing a C++ decrypter."


def test_decrypt_cpp_contains_lcg_reversal():
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()

    assert source.strip(), f"{SOURCE} is empty"
    assert EXPECTED_LITERAL not in source, "The recovered password must not be hard-coded in decrypt.cpp"

    # Ignore comments and string literals when looking for the core cipher operations.
    code = re.sub(r"//.*?$|/\*.*?\*/|\"(?:\\.|[^\"\\])*\"", " ", source,
                  flags=re.MULTILINE | re.DOTALL)
    assert "^" in code, "decrypt.cpp does not contain the required XOR reversal"
    assert re.search(r"(?<![A-Za-z0-9_])13(?![A-Za-z0-9_])", code), \
        "decrypt.cpp does not contain the LCG multiplier"
    assert re.search(r"(?<![A-Za-z0-9_])(?:0[xX]37|55)(?![A-Za-z0-9_])", code), \
        "decrypt.cpp does not contain the LCG initial seed"
    assert re.search(r"(?<![A-Za-z0-9_])(?:37|0[xX]25)(?![A-Za-z0-9_])", code), \
        "decrypt.cpp does not contain the LCG increment"


def test_compile_and_run_decrypter():
    expected = derive_expected_password()

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, \
        "decrypt.cpp failed to compile:\n" + compile_result.stderr.decode(errors="replace")

    # The checked password must be produced by a fresh execution of the submitted
    # C++ artifact, rather than being a pre-created constant file.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    run_result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert run_result.returncode == 0, \
        "The compiled decrypter failed when executed:\n" + run_result.stderr.decode(errors="replace")

    if os.path.isfile(OUTPUT):
        with open(OUTPUT, "rb") as f:
            produced = f.read()
    else:
        produced = run_result.stdout
        if produced == expected:
            with open(OUTPUT, "wb") as f:
                f.write(produced)

    assert produced == expected, \
        "Running the compiled decrypter did not produce the password derived from the intercepted admin token"


def test_admin_pass_correct():
    path = "/home/user/admin_pass.txt"
    assert os.path.isfile(path), f"Missing file: {path}. The task requires saving the recovered password to this file."

    with open(path, "r") as f:
        content = f.read()

    expected_password = "Pwn3d_Pr0c_M3m0ry!"
    assert content == expected_password, f"The content of {path} is incorrect. Expected '{expected_password}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
