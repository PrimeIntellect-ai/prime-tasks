#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_decoder_c_exists():
    path = "/home/user/decoder.c"
    assert os.path.exists(path), f"File {path} does not exist. You must write your C program to this location."
    assert os.path.isfile(path), f"{path} is not a file."


def test_decoder_binary_exists():
    path = "/home/user/decoder"
    assert os.path.exists(path), f"Executable {path} does not exist. You must compile your C program to this location."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_secret_txt_content():
    path = "/home/user/secret.txt"
    assert os.path.exists(path), f"File {path} does not exist. You must redirect the output of your decoder to this file."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "EXFILTRATION_COMPLETE"
    assert content == expected, f"Content of {path} is incorrect. Expected '{expected}', got '{content}'."


def test_decoder_and_source_process_backdoored_packets():
    source = "/home/user/decoder.c"
    submitted = "/home/user/decoder"
    rebuilt = "/tmp/decoder_from_source"
    capture = "/home/user/capture.hex"

    build = subprocess.run(
        ["gcc", source, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert build.returncode == 0, f"decoder.c does not compile:\n{build.stderr}"

    expected = "VERIFY_" + secrets.token_hex(12).upper()
    encrypted = bytes(ord(ch) ^ 0x5A for ch in expected).hex().upper()
    test_capture = (
        "1A2B3C4D00112233445566778899AABB\n"
        "00118899AABB" + encrypted + "\n"
        "FFFFFFFF000000001111111122222222\n"
        "8899AABB" + encrypted + "\n"
        "102030405060708090A0B0C0D0E0F000\n"
    )

    with open(capture, "rb") as f:
        original_capture = f.read()

    try:
        with open(capture, "w", encoding="ascii") as f:
            f.write(test_capture)

        for executable in (submitted, rebuilt):
            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
                cwd="/home/user",
            )
            assert result.returncode == 0, (
                f"{executable} exited with status {result.returncode}: {result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"{executable} did not decode the generated backdoor packet correctly. "
                f"Expected {expected!r}, got {result.stdout.strip()!r}."
            )
    finally:
        with open(capture, "wb") as f:
            f.write(original_capture)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
