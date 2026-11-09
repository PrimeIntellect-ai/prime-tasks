#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import random
import pytest

UTF8_PATH = "/home/user/all_configs.utf8"
ENCODED_PATH = "/home/user/encoded_configs.dat"
SOURCE_PATH = "/home/user/solution.c"
AGENT_PATH = "/home/user/encoder"
ORACLE_PATH = "/app/diff_encoder"

EXPECTED_CONFIG = (
    "key1=value1\n"
    "key2=résumé\n"
    "setting=enabled\n"
    "path=/var/log\n"
).encode("utf-8")


def expected_encoding(data):
    output = bytearray()
    for offset in range(0, len(data), 16):
        block = data[offset:offset + 16]
        block += b"\x00" * (16 - len(block))
        output.extend(byte ^ 0x5A for byte in reversed(block))
    return bytes(output)


def make_jail(binary_path):
    jail = tempfile.mkdtemp(prefix="encoder-jail-")
    jailed_binary = os.path.join(jail, "encoder")
    shutil.copy2(binary_path, jailed_binary)
    os.chmod(jailed_binary, 0o755)

    ldd = subprocess.run(["ldd", binary_path], capture_output=True, text=True)
    if ldd.returncode == 0:
        dependencies = set(re.findall(r"(/[A-Za-z0-9_+.,/@:-]+)", ldd.stdout + ldd.stderr))
        for dependency in dependencies:
            if not os.path.isfile(dependency):
                continue
            destination = os.path.join(jail, dependency.lstrip("/"))
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.copy2(dependency, destination, follow_symlinks=True)
            os.chmod(destination, os.stat(destination).st_mode | stat.S_IRUSR | stat.S_IXUSR)

    return jail


def run_jailed(jail, data):
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", jail, "/encoder"],
        input=data,
        capture_output=True,
        timeout=10,
    )


@pytest.fixture(scope="session")
def encoder_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"C source is missing at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must be a real C source file"
    assert os.path.getsize(SOURCE_PATH) > 0, f"{SOURCE_PATH} is empty"

    with open(SOURCE_PATH, "rb") as source_file:
        source_data = source_file.read()
    try:
        source_data.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"{SOURCE_PATH} is not valid textual C source")

    assert os.path.isfile(AGENT_PATH), f"Agent program missing at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), f"{AGENT_PATH} must be a compiled program, not a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as agent_file:
        agent_bytes = agent_file.read()
    assert agent_bytes.startswith(b"\x7fELF"), f"{AGENT_PATH} is not a compiled ELF program"

    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    with open(ORACLE_PATH, "rb") as oracle_file:
        oracle_bytes = oracle_file.read()
    assert agent_bytes != oracle_bytes, "Submitted encoder is byte-identical to the reference binary"
    assert not agent_bytes.startswith(oracle_bytes), "Submitted encoder is the reference binary with trailing data"

    build_dir = tempfile.mkdtemp(prefix="source-build-")
    rebuilt_path = os.path.join(build_dir, "rebuilt_encoder")
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-static", SOURCE_PATH, "-o", rebuilt_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}:\n{compile_proc.stdout}\n{compile_proc.stderr}"
    )

    agent_jail = make_jail(AGENT_PATH)
    rebuilt_jail = make_jail(rebuilt_path)
    try:
        yield agent_jail, rebuilt_jail
    finally:
        shutil.rmtree(agent_jail, ignore_errors=True)
        shutil.rmtree(rebuilt_jail, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)


def test_all_configs_utf8_exists():
    assert os.path.isfile(UTF8_PATH), f"File {UTF8_PATH} is missing."
    with open(UTF8_PATH, "rb") as config_file:
        data = config_file.read()

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"File {UTF8_PATH} is not valid UTF-8.")

    assert "key1=value1" in text, "Expected content from a.conf missing in all_configs.utf8"
    assert "résumé" in text, "Expected decoded content from a.conf missing in all_configs.utf8"
    assert "setting=enabled" in text, "Expected content from b.conf missing in all_configs.utf8"
    assert data == EXPECTED_CONFIG, (
        "all_configs.utf8 is not the exact UTF-8 concatenation of all .conf files "
        "in alphabetical absolute-path order"
    )


def test_fuzz_equivalence(encoder_artifacts):
    agent_jail, rebuilt_jail = encoder_artifacts
    random.seed(42)

    for _ in range(500):
        length = random.randint(0, 2048)
        input_data = bytes(random.choices(range(256), k=length))
        expected = expected_encoding(input_data)

        oracle_proc = subprocess.run([ORACLE_PATH], input=input_data, capture_output=True, timeout=10)
        agent_proc = run_jailed(agent_jail, input_data)
        rebuilt_proc = run_jailed(rebuilt_jail, input_data)

        assert oracle_proc.returncode == 0, f"Oracle failed on input of length {length}"
        assert agent_proc.returncode == 0, f"Agent failed in isolation on input of length {length}"
        assert rebuilt_proc.returncode == 0, f"Program rebuilt from solution.c failed on input of length {length}"
        assert oracle_proc.stdout == expected, f"Oracle disagreed with derived result for length {length}"
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Agent mismatch on random input of length {length}"
        )
        assert rebuilt_proc.stdout == oracle_proc.stdout, (
            f"solution.c mismatch on random input of length {length}"
        )


def test_encoded_configs(encoder_artifacts):
    agent_jail, rebuilt_jail = encoder_artifacts
    assert os.path.isfile(UTF8_PATH), f"{UTF8_PATH} is missing"
    assert os.path.isfile(ENCODED_PATH), f"{ENCODED_PATH} is missing"

    with open(UTF8_PATH, "rb") as config_file:
        utf8_data = config_file.read()
    with open(ENCODED_PATH, "rb") as encoded_file:
        encoded_data = encoded_file.read()

    oracle_proc = subprocess.run([ORACLE_PATH], input=utf8_data, capture_output=True, timeout=10)
    assert oracle_proc.returncode == 0, "Oracle failed to process all_configs.utf8"
    assert oracle_proc.stdout == encoded_data, (
        f"Contents of {ENCODED_PATH} do not match expected output from encoding {UTF8_PATH}."
    )

    expected = expected_encoding(EXPECTED_CONFIG)
    assert utf8_data == EXPECTED_CONFIG
    assert encoded_data == expected, "encoded_configs.dat does not contain the derived expected encoding"

    agent_proc = run_jailed(agent_jail, EXPECTED_CONFIG)
    rebuilt_proc = run_jailed(rebuilt_jail, EXPECTED_CONFIG)
    assert agent_proc.returncode == 0 and agent_proc.stdout == encoded_data
    assert rebuilt_proc.returncode == 0 and rebuilt_proc.stdout == encoded_data
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
