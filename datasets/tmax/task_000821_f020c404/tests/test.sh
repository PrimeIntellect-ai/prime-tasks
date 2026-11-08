#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import subprocess
from pathlib import Path

ORACLE_PATH = "/app/token_checker"
AGENT_PATH = "/home/user/my_token_checker"
SOURCE_PATH = "/home/user/my_token_checker.c"
BUILD_PATH = "/tmp/verified_token_checker"
ROOTFS = Path("/tmp/token_checker_rootfs")


def generate_random_string(length):
    chars = string.ascii_letters + string.digits + ";= -"
    return ''.join(random.choice(chars) for _ in range(length))


def generate_valid_cookie():
    prefix = generate_random_string(random.randint(0, 20))
    hex_len = random.randint(1, 20) * 2
    hex_chars = ''.join(random.choice(string.hexdigits) for _ in range(hex_len))
    suffix = generate_random_string(random.randint(0, 20))
    return f"{prefix}SessionId={hex_chars};{suffix}"


def generate_malformed_cookie():
    case = random.randint(0, 2)
    if case == 0:
        return generate_random_string(random.randint(5, 50))
    if case == 1:
        prefix = generate_random_string(random.randint(0, 20))
        hex_len = random.randint(0, 20) * 2 + 1
        hex_chars = ''.join(random.choice(string.hexdigits) for _ in range(hex_len))
        return f"{prefix}SessionId={hex_chars};"

    prefix = generate_random_string(random.randint(0, 20))
    hex_len = random.randint(1, 20) * 2
    hex_chars = ''.join(random.choice(string.hexdigits) for _ in range(hex_len - 1)) + "G"
    return f"{prefix}SessionId={hex_chars};"


def expected_result(args):
    if len(args) != 1:
        return 1, b"ERROR: Invalid arguments\n", b""

    cookie = args[0]
    marker = "SessionId="
    start = cookie.find(marker)
    if start < 0:
        return 1, b"ERROR: Invalid SessionId\n", b""

    value = cookie[start + len(marker):]
    value = value.split(";", 1)[0][:255]
    if not value or len(value) % 2 or any(c not in string.hexdigits for c in value):
        return 1, b"ERROR: Invalid SessionId\n", b""

    token = []
    for i in range(0, len(value), 2):
        val = int(value[i:i + 2], 16) ^ 0x5A
        val = ((val << 1) | (val >> 7)) & 0xFF
        token.append(f"{val:02x}")
    return 0, ("TOKEN: " + "".join(token) + "\n").encode(), b""


def copy_into_rootfs(path):
    source = Path(path)
    destination = ROOTFS / source.relative_to("/")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def prepare_isolated_executable():
    shutil.rmtree(ROOTFS, ignore_errors=True)
    ROOTFS.mkdir(parents=True)
    shutil.copy2(BUILD_PATH, ROOTFS / "checker")
    os.chmod(ROOTFS / "checker", 0o755)

    ldd = subprocess.run(["/usr/bin/ldd", BUILD_PATH], capture_output=True, text=True, check=True)
    dependencies = set()
    for line in ldd.stdout.splitlines():
        fields = line.strip().split()
        for field in fields:
            if field.startswith("/") and os.path.isfile(field):
                dependencies.add(field)
    for dependency in dependencies:
        copy_into_rootfs(dependency)


def run_isolated(args):
    return subprocess.run(
        ["/usr/sbin/chroot", str(ROOTFS), "/checker", *args],
        capture_output=True,
        timeout=5,
    )


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"

    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent binary is a byte-identical copy of the oracle"

    compiled = subprocess.run(
        ["/usr/bin/gcc", "-O2", SOURCE_PATH, "-o", BUILD_PATH],
        capture_output=True,
        text=True,
    )
    assert compiled.returncode == 0, f"C source failed to compile:\n{compiled.stdout}{compiled.stderr}"
    assert Path(BUILD_PATH).read_bytes().startswith(b"\x7fELF"), "Compiled output is not an ELF executable"
    assert Path(BUILD_PATH).read_bytes() != Path(ORACLE_PATH).read_bytes(), \
        "Compiled program is a byte-identical copy of the oracle"

    prepare_isolated_executable()

    random.seed(1337)
    inputs = []
    for _ in range(250):
        inputs.append([generate_valid_cookie()])
    for _ in range(250):
        inputs.append([generate_malformed_cookie()])

    inputs.extend([
        [],
        [""],
        ["Cookie: SessionId=00;"],
        ["Cookie: SessionId=ff;"],
        ["Cookie: SessionId=0G;"],
        ["Cookie: SessionId=GG;"],
        ["Cookie: SessionId=123;"],
        ["Cookie: theme=dark"],
        ["Cookie: SessionId=1234", "extra"],
    ])

    for args in inputs:
        expected_code, expected_stdout, expected_stderr = expected_result(args)
        result = run_isolated(args)
        display_input = "<NO ARGUMENTS>" if not args else repr(args)

        assert result.returncode == expected_code, \
            f"Exit code mismatch for {display_input}: expected {expected_code}, got {result.returncode}"
        assert result.stdout == expected_stdout, \
            f"Stdout mismatch for {display_input}: expected {expected_stdout!r}, got {result.stdout!r}"
        assert result.stderr == expected_stderr, \
            f"Stderr mismatch for {display_input}: expected {expected_stderr!r}, got {result.stderr!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
