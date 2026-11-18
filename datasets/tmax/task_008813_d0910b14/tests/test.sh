#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import pytest

RECOVER_C = "/home/user/investigation/recover.c"
RECOVERED = "/home/user/recovered_evidence.txt"
PAYLOAD = "/home/user/hidden_stash/payload.enc"
EXPECTED_EVIDENCE = "EVIDENCE{path_traversal_and_brute_force_master_9921}"


def test_recover_c_exists():
    path = "/home/user/investigation/recover.c"
    assert os.path.isfile(path), f"The C program was not found at {path}"


def test_recovered_evidence_content():
    path = "/home/user/recovered_evidence.txt"
    assert os.path.isfile(path), f"The recovered evidence file was not found at {path}"

    expected_evidence = "EVIDENCE{path_traversal_and_brute_force_master_9921}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected_evidence, f"The content of {path} is incorrect. Expected '{expected_evidence}', but got '{content}'"


def test_c_program_bruteforces_and_decrypts_payload():
    binary = "/tmp/recover_submission"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", binary, RECOVER_C],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"recover.c did not compile:\n{compile_result.stderr}"

    with open(PAYLOAD, "rb") as f:
        original_payload = f.read()
    original_output_exists = os.path.exists(RECOVERED)
    original_output = None
    if original_output_exists:
        with open(RECOVERED, "rb") as f:
            original_output = f.read()

    pin = secrets.randbelow(10000)
    while pin == 4271:
        pin = secrets.randbelow(10000)
    expected = f"EVIDENCE{{runtime_bruteforce_check_{secrets.token_hex(12)}}}"
    key = ("aB39" + f"{pin:04d}").encode("ascii")
    plaintext = expected.encode("ascii")
    ciphertext = bytes(b ^ key[i % len(key)] for i, b in enumerate(plaintext))

    try:
        with open(PAYLOAD, "wb") as f:
            f.write(ciphertext)
        if os.path.exists(RECOVERED):
            os.remove(RECOVERED)

        run_result = subprocess.run(
            [binary],
            cwd="/home/user/investigation",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"The compiled recover.c program failed with exit code {run_result.returncode}:\n"
            + run_result.stderr.decode("utf-8", errors="replace")
        )

        if os.path.isfile(RECOVERED):
            with open(RECOVERED, "rb") as f:
                produced = f.read().strip()
        else:
            produced = run_result.stdout.strip()

        assert produced == plaintext, (
            "The compiled recover.c program did not decrypt a payload encrypted with "
            "a runtime-selected 4-digit PIN."
        )
    finally:
        with open(PAYLOAD, "wb") as f:
            f.write(original_payload)
        if original_output_exists:
            with open(RECOVERED, "wb") as f:
                f.write(original_output)
        elif os.path.exists(RECOVERED):
            os.remove(RECOVERED)
        if os.path.exists(binary):
            os.remove(binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
