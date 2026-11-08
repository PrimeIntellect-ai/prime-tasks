#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import string
import subprocess

import pytest

SOURCE = "/home/user/cracker.cpp"
BINARY = "/tmp/cracker_verified"
OUTPUT = "/home/user/compromised_accounts.txt"

CANONICAL_WORDLIST = """password123
admin
qwerty
letmein
hunter2
winter2023
supersecret
"""

CANONICAL_HEADER = r'''#ifndef CUSTOM_HASH_H
#define CUSTOM_HASH_H
#include <string>

inline unsigned int compute_hash(const std::string& password) {
    unsigned int hash = 0;
    for (size_t i = 0; i < password.length(); ++i) {
        hash = (hash * 31) + password[i];
    }
    return hash ^ 0xDEADBEEF;
}
#endif
'''

CANONICAL_LOGS = """[2023-10-24 10:00:01] user=sysadmin redirect_payload=aHR0cDovL2V2aWwuY29tL3N0ZWFs hash=DF5165E0
[2023-10-24 10:05:22] user=devteam redirect_payload=aHR0cHM6Ly9waGlzaC5uZXQvbG9naW4= hash=DE5689EF
"""

CANONICAL_EXPECTED = [
    "sysadmin:admin:http://evil.com/steal",
    "devteam:hunter2:https://phish.net/login",
]


def write_canonical_inputs():
    with open("/home/user/wordlist.txt", "w") as f:
        f.write(CANONICAL_WORDLIST)
    with open("/home/user/custom_hash.h", "w") as f:
        f.write(CANONICAL_HEADER)
    with open("/home/user/auth_logs.txt", "w") as f:
        f.write(CANONICAL_LOGS)


def run_cracker():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled cracker exited with status {result.returncode}. "
        f"stdout: {result.stdout!r} stderr: {result.stderr!r}"
    )


def read_nonempty_lines(path):
    assert os.path.isfile(path), f"Missing file: {path}. Your program must create this file."
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def custom_hash(password):
    value = 0
    for byte in password.encode("ascii"):
        value = ((value * 31) + byte) & 0xFFFFFFFF
    return value ^ 0xDEADBEEF


def test_01_cracker_cpp_exists():
    path = "/home/user/cracker.cpp"
    assert os.path.isfile(path), f"Missing file: {path}. You must write your solution in this file."


def test_02_compile_and_run_cracker_on_provided_inputs():
    write_canonical_inputs()
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY],
        cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Could not compile {SOURCE} with g++. "
        f"stdout: {result.stdout!r} stderr: {result.stderr!r}"
    )
    assert os.path.isfile(BINARY), "g++ did not produce the expected executable"
    run_cracker()


def test_03_compromised_accounts_output():
    path = "/home/user/compromised_accounts.txt"
    assert os.path.isfile(path), f"Missing file: {path}. Your program must create this file."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "sysadmin:admin:http://evil.com/steal",
        "devteam:hunter2:https://phish.net/login"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, but found {len(lines)}."

    for expected in expected_lines:
        assert expected in lines, f"Missing expected output line in {path}: '{expected}'"


def test_04_cracker_parses_decodes_and_cracks_fresh_inputs():
    alphabet = string.ascii_lowercase + string.digits
    passwords = ["pw" + "".join(secrets.choice(alphabet) for _ in range(14)) for _ in range(2)]
    while custom_hash(passwords[0]) == custom_hash(passwords[1]):
        passwords[1] = "pw" + "".join(secrets.choice(alphabet) for _ in range(14))

    users = ["audit_" + secrets.token_hex(5), "check_" + secrets.token_hex(5)]
    urls = [
        "https://" + secrets.token_hex(6) + ".example/redirect?token=" + secrets.token_hex(7),
        "http://test.example/" + secrets.token_hex(11),
    ]

    wrong_words = ["wrong_" + secrets.token_hex(6), "decoy_" + secrets.token_hex(6)]
    wrong_words = [w for w in wrong_words if all(custom_hash(w) != custom_hash(p) for p in passwords)]
    with open("/home/user/wordlist.txt", "w") as f:
        f.write("\n".join([wrong_words[0], passwords[1], wrong_words[1], passwords[0]]) + "\n")

    log_lines = []
    expected = []
    for index in range(2):
        payload = base64.b64encode(urls[index].encode("utf-8")).decode("ascii")
        log_lines.append(
            f"[2026-09-11 12:00:0{index}] user={users[index]} "
            f"redirect_payload={payload} hash={custom_hash(passwords[index]):08X}"
        )
        expected.append(f"{users[index]}:{passwords[index]}:{urls[index]}")

    with open("/home/user/auth_logs.txt", "w") as f:
        f.write("\n".join(log_lines) + "\n")

    try:
        run_cracker()
        lines = read_nonempty_lines(OUTPUT)
        assert len(lines) == len(expected), (
            f"Expected {len(expected)} lines for fresh inputs, but found {len(lines)}: {lines!r}"
        )
        for expected_line in expected:
            assert expected_line in lines, f"Missing fresh-input result: {expected_line!r}"
    finally:
        write_canonical_inputs()
        run_cracker()


def test_05_ssh_key_backup_permissions():
    path = "/home/user/ssh_key_backup"
    assert os.path.isfile(path), f"Missing file: {path}. Did you delete it?"

    st = os.stat(path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Permissions for {path} should be 400 (owner read-only), but got {oct(permissions)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
