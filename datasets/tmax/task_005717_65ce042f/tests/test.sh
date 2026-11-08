#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets
import pytest

HOME = "/home/user"
EVIDENCE = "/home/user/evidence"
EXPECTED_PLAINTEXT = b"CONFIDENTIAL: The main server backdoor password is 'RogueAccess2024!'. Do not share."


def test_chain_pem_extracted():
    user_chain_path = "/home/user/chain.pem"
    dropper_path = "/home/user/evidence/dropper.elf"
    truth_chain_path = "/tmp/truth_chain.pem"

    assert os.path.isfile(user_chain_path), f"{user_chain_path} is missing"
    assert os.path.isfile(dropper_path), f"{dropper_path} is missing"

    try:
        subprocess.run(
            ['objcopy', '-O', 'binary', '--only-section=.evil_cert', dropper_path, truth_chain_path],
            check=True,
            capture_output=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to extract .evil_cert section for verification: {e}")

    assert os.path.isfile(truth_chain_path), "Failed to create truth extraction file"

    with open(user_chain_path, 'rb') as f:
        user_chain = f.read()
    with open(truth_chain_path, 'rb') as f:
        truth_chain = f.read()
    os.remove(truth_chain_path)

    assert user_chain == truth_chain, f"The contents of {user_chain_path} do not exactly match the .evil_cert section"


def test_root_ca_cn():
    cn_file_path = "/home/user/root_ca_cn.txt"
    assert os.path.isfile(cn_file_path), f"{cn_file_path} is missing"

    with open(cn_file_path, "r") as f:
        content = f.read().strip()

    expected_cn = "Rogue Root CA"
    assert content == expected_cn, f"Expected Root CA CN to be '{expected_cn}', but got '{content}'"


def test_crack_cpp_exists():
    cpp_file_path = "/home/user/crack.cpp"
    assert os.path.isfile(cpp_file_path), f"{cpp_file_path} is missing"


def test_decrypted_data():
    decrypted_file_path = "/home/user/decrypted_data.txt"
    assert os.path.isfile(decrypted_file_path), f"{decrypted_file_path} is missing"

    with open(decrypted_file_path, "r") as f:
        content = f.read().strip()

    expected_plaintext = "CONFIDENTIAL: The main server backdoor password is 'RogueAccess2024!'. Do not share."
    assert content == expected_plaintext, f"The decrypted data does not match the expected plaintext. Got: '{content}'"


def encrypt_lcg(plaintext, seed):
    state = seed
    ciphertext = bytearray()
    for value in plaintext:
        ciphertext.append(value ^ ((state >> 24) & 0xff))
        state = (1103515245 * state + 12345) & 0xffffffff
    return bytes(ciphertext)


def run_cracker(binary):
    try:
        result = subprocess.run(
            [binary], cwd=HOME, capture_output=True, timeout=180
        )
    except subprocess.TimeoutExpired:
        pytest.fail("crack_cipher timed out")
    assert result.returncode == 0, (
        f"crack_cipher exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )


def test_compiled_cpp_cracks_and_decrypts():
    source = "/home/user/crack.cpp"
    binary = "/home/user/crack_cipher"
    encrypted = "/home/user/evidence/stolen_data.enc"
    known = "/home/user/evidence/known_plaintext.bin"
    output = "/home/user/decrypted_data.txt"
    rebuilt = "/tmp/crack_cipher.rebuilt"

    assert os.path.isfile(source), f"{source} is missing"
    assert not os.path.islink(source), f"{source} must be a regular source file"
    assert os.path.isfile(binary), f"{binary} is missing"
    assert not os.path.islink(binary), f"{binary} must be a regular compiled executable"
    assert stat.S_ISREG(os.stat(binary).st_mode), f"{binary} is not a regular file"
    assert os.access(binary, os.X_OK), f"{binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not an ELF executable"

    try:
        compile_result = subprocess.run(
            ["g++", "-O2", source, "-o", rebuilt],
            capture_output=True,
            timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compilation of crack.cpp timed out")
    assert compile_result.returncode == 0, (
        "crack.cpp failed to compile with standard g++: "
        + compile_result.stderr.decode(errors="replace")
    )
    os.replace(rebuilt, binary)
    os.chmod(binary, 0o755)

    with open(encrypted, "rb") as f:
        original_encrypted = f.read()
    with open(known, "rb") as f:
        original_known = f.read()
    original_output = None
    if os.path.isfile(output):
        with open(output, "rb") as f:
            original_output = f.read()

    try:
        if os.path.exists(output):
            os.remove(output)
        run_cracker(binary)
        assert os.path.isfile(output), "Executing crack_cipher did not create decrypted_data.txt"
        with open(output, "rb") as f:
            produced = f.read()
        assert produced.strip() == EXPECTED_PLAINTEXT, "The compiled C++ program did not decrypt the supplied evidence correctly"

        alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()-_=+[]{};:,.?"
        random_plaintext = bytes(secrets.choice(alphabet) for _ in range(96))
        random_seed = int.from_bytes(os.urandom(4), "big")
        random_ciphertext = encrypt_lcg(random_plaintext, random_seed)

        with open(encrypted, "wb") as f:
            f.write(random_ciphertext)
        with open(known, "wb") as f:
            f.write(random_plaintext[:12])
        if os.path.exists(output):
            os.remove(output)

        run_cracker(binary)
        assert os.path.isfile(output), "crack_cipher did not produce output for a fresh test case"
        with open(output, "rb") as f:
            produced = f.read()
        assert produced == random_plaintext, "The compiled C++ program does not recover and use an unknown LCG seed"
    finally:
        with open(encrypted, "wb") as f:
            f.write(original_encrypted)
        with open(known, "wb") as f:
            f.write(original_known)
        if original_output is None:
            if os.path.exists(output):
                os.remove(output)
        else:
            with open(output, "wb") as f:
                f.write(original_output)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
