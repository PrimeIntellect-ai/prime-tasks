#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "decrypt.cpp")
TRAFFIC = os.path.join(HOME, "traffic.log")
RECOVERED = os.path.join(HOME, "recovered_command.txt")
CWE = os.path.join(HOME, "cwe.txt")
KNOWN_PREFIX = b"CMD_"


def test_recovered_command():
    path = "/home/user/recovered_command.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "CMD_REVERSE_BASH", f"Incorrect recovered command. Found: '{content}'"


def test_cwe_id():
    path = "/home/user/cwe.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read().strip().upper()

    assert content in ["CWE-327", "CWE-326"], f"Incorrect CWE ID. Found: '{content}'"


def extract_ciphertext(traffic_text):
    match = re.search(r"(?:^|[;\s])X-CMD=([0-9A-Fa-f]+)", traffic_text, re.MULTILINE)
    assert match, "traffic.log does not contain a valid X-CMD cookie"
    value = match.group(1)
    assert len(value) % 2 == 0, "X-CMD ciphertext has odd length"
    return value


def derive_plaintext(cipher_hex):
    ciphertext = bytes.fromhex(cipher_hex)
    assert len(ciphertext) >= len(KNOWN_PREFIX)
    key = bytes(ciphertext[i] ^ KNOWN_PREFIX[i] for i in range(4))
    return bytes(byte ^ key[i % 4] for i, byte in enumerate(ciphertext))


def snapshot(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def restore(path, data):
    if data is None:
        if os.path.exists(path):
            os.unlink(path)
    else:
        with open(path, "wb") as f:
            f.write(data)


def compile_and_run(source_text, traffic_text, expected):
    saved = {path: snapshot(path) for path in (TRAFFIC, RECOVERED, CWE)}
    with tempfile.TemporaryDirectory(prefix="decrypt-test-") as tempdir:
        test_source = os.path.join(tempdir, "decrypt.cpp")
        executable = os.path.join(tempdir, "decrypt")
        with open(test_source, "w", encoding="utf-8") as f:
            f.write(source_text)

        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", test_source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, "decrypt.cpp failed to compile:\n" + build.stderr
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        try:
            with open(TRAFFIC, "w", encoding="utf-8") as f:
                f.write(traffic_text)
            if os.path.exists(RECOVERED):
                os.unlink(RECOVERED)

            env = os.environ.copy()
            env["TRAFFIC_LOG"] = TRAFFIC
            env["X_CMD_HEX"] = extract_ciphertext(traffic_text)
            run = subprocess.run(
                [executable, TRAFFIC, env["X_CMD_HEX"]],
                cwd=HOME,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert run.returncode == 0, (
                f"decrypt program exited with status {run.returncode}:\n"
                + run.stderr.decode("utf-8", errors="replace")
            )

            observed = run.stdout + b"\n" + run.stderr
            if os.path.isfile(RECOVERED):
                with open(RECOVERED, "rb") as f:
                    observed += b"\n" + f.read()
            assert expected in observed, "decrypt program did not produce the decrypted command"
        finally:
            for path, data in saved.items():
                restore(path, data)


def test_decrypt_program_compiles_runs_and_recovers_original_payload():
    assert os.path.isfile(SOURCE), f"Missing required C++ program: {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    assert source_text.strip(), "decrypt.cpp is empty"

    with open(TRAFFIC, "r", encoding="utf-8") as f:
        traffic_text = f.read()
    cipher_hex = extract_ciphertext(traffic_text)
    expected = derive_plaintext(cipher_hex)
    assert expected == b"CMD_REVERSE_BASH"
    compile_and_run(source_text, traffic_text, expected)


def test_decrypt_program_performs_known_plaintext_cryptanalysis():
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    with open(TRAFFIC, "r", encoding="utf-8") as f:
        original_traffic = f.read()

    original_hex = extract_ciphertext(original_traffic)
    suffix = secrets.token_hex(8).upper().encode("ascii")
    expected = KNOWN_PREFIX + suffix
    key = bytes(secrets.randbelow(255) + 1 for _ in range(4))
    variant_hex = bytes(byte ^ key[i % 4] for i, byte in enumerate(expected)).hex()

    variant_traffic = re.sub(
        r"(?i)(X-CMD=)" + re.escape(original_hex),
        lambda m: m.group(1) + variant_hex,
        original_traffic,
        count=1,
    )
    # Support implementations which reasonably embedded the payload extracted
    # from the supplied log, while still changing the cryptanalytic test case.
    variant_source = re.sub(
        re.escape(original_hex),
        variant_hex,
        source_text,
        flags=re.IGNORECASE,
    )
    assert derive_plaintext(variant_hex) == expected
    compile_and_run(variant_source, variant_traffic, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
