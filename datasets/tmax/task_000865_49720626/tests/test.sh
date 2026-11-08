#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import shutil
import stat
import subprocess
import string
import struct
import tempfile

ORACLE_PATH = "/app/token_validator"
SOURCE_PATH = "/home/user/validator.c"
AGENT_PATH = "/home/user/validator"
NUM_TESTS = 1000


def calc_hash(payload: bytes) -> int:
    hash_val = 0x12345678
    for b in payload:
        hash_val ^= b
        hash_val = ((hash_val << 5) & 0xFFFFFFFF) | (hash_val >> 27)
        hash_val = (hash_val + 0x5A5A5A5A) & 0xFFFFFFFF
    return hash_val


def generate_inputs(seed=42):
    random.seed(seed)
    inputs = []

    # 20% invalid hex characters
    for _ in range(int(NUM_TESTS * 0.2)):
        length = random.randint(1, 100)
        chars = [random.choice(string.printable) for _ in range(length)]
        invalid_chars = set(string.printable) - set(string.hexdigits) - set(' \t\n\r')
        if invalid_chars:
            chars[random.randint(0, length - 1)] = random.choice(list(invalid_chars))
        inputs.append("".join(chars).encode('utf-8'))

    # 20% valid hex strings of length < 10
    for _ in range(int(NUM_TESTS * 0.2)):
        length = random.randint(0, 9)
        chars = [random.choice(string.hexdigits) for _ in range(length)]
        inputs.append("".join(chars).encode('utf-8'))

    # 30% valid hex strings of random length with random checksums
    for _ in range(int(NUM_TESTS * 0.3)):
        length = random.randint(10, 512)
        if length % 2 != 0:
            length += 1
        chars = [random.choice(string.hexdigits) for _ in range(length)]
        inputs.append("".join(chars).encode('utf-8'))

    # 30% perfectly crafted valid tokens
    for _ in range(int(NUM_TESTS * 0.3)):
        payload_len = random.randint(1, 250)
        payload = bytes([random.randint(0, 255) for _ in range(payload_len)])
        checksum = calc_hash(payload)
        token_bytes = payload + struct.pack("<I", checksum)
        inputs.append(token_bytes.hex().encode('utf-8'))

    random.shuffle(inputs)
    return inputs


def copy_into_jail(source, jail):
    destination = os.path.join(jail, source.lstrip('/'))
    os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
    shutil.copy2(source, destination)
    os.chmod(destination, 0o755)


def make_isolated_jail():
    jail = tempfile.mkdtemp(prefix="validator-jail-")
    os.chmod(jail, 0o755)
    shutil.copy2(AGENT_PATH, os.path.join(jail, "validator"))
    os.chmod(os.path.join(jail, "validator"), 0o755)

    ldd = subprocess.run(["ldd", AGENT_PATH], capture_output=True, text=True, check=True)
    dependencies = set()
    for line in ldd.stdout.splitlines():
        for path in re.findall(r"(/[A-Za-z0-9_+.,@%:/=-]+)", line):
            if os.path.isfile(path):
                dependencies.add(path)
    for dependency in dependencies:
        copy_into_jail(dependency, jail)
    return jail


def isolated_preexec(jail, uid, gid):
    def enter_jail():
        os.chroot(jail)
        os.chdir('/')
        os.setgroups([])
        os.setgid(gid)
        os.setuid(uid)
    return enter_jail


def test_agent_binary_exists():
    assert os.path.isfile(SOURCE_PATH), f"Agent source not found at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"Agent source at {SOURCE_PATH} must be a regular file"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), f"Agent source at {SOURCE_PATH} must be a regular file"

    build = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", AGENT_PATH],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Agent source did not compile:\n{build.stdout}\n{build.stderr}"

    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

    with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
        assert oracle_file.read() != agent_file.read(), "Agent binary must not be a byte-identical copy of the oracle"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    inputs = generate_inputs()
    oracle_results = [subprocess.run([ORACLE_PATH], input=inp, capture_output=True) for inp in inputs]

    jail = make_isolated_jail()
    account = pwd.getpwnam("user")
    try:
        for idx, (inp, oracle_proc) in enumerate(zip(inputs, oracle_results)):
            agent_proc = subprocess.run(
                ["/validator"],
                input=inp,
                capture_output=True,
                preexec_fn=isolated_preexec(jail, account.pw_uid, account.pw_gid),
            )

            err_msg = (
                f"Mismatch on input #{idx}!\n"
                f"Input (hex): {inp.hex()}\n"
                f"Oracle stdout: {oracle_proc.stdout}\n"
                f"Agent stdout: {agent_proc.stdout}\n"
                f"Oracle stderr: {oracle_proc.stderr}\n"
                f"Agent stderr: {agent_proc.stderr}\n"
                f"Oracle exit code: {oracle_proc.returncode}\n"
                f"Agent exit code: {agent_proc.returncode}\n"
            )

            assert oracle_proc.returncode == agent_proc.returncode, err_msg
            assert oracle_proc.stdout == agent_proc.stdout, err_msg
            assert oracle_proc.stderr == agent_proc.stderr, err_msg
    finally:
        shutil.rmtree(jail)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
