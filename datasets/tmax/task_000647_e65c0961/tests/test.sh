#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile
import pytest

MASK32 = 0xFFFFFFFF
FIXED_SEED = 84729
FIXED_TOKEN = "1475851637"
RANDOM_SEEDS = [secrets.randbelow(2**31) for _ in range(12)]


def expected_token(seed):
    step1 = (seed ^ 0xCAFEBABE) & MASK32
    step2 = ((step1 << 3) | (step1 >> 29)) & MASK32
    return str((step2 + 0x1337) & MASK32)


def run_keygen(path, seed):
    try:
        result = subprocess.run(
            [path, str(seed)], capture_output=True, text=True, timeout=5
        )
    except Exception as e:
        pytest.fail(f"Failed to run {path}: {e}")
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}: {result.stderr}"
    )
    return result.stdout.strip()


def test_keygen_c_exists():
    path = "/home/user/keygen.c"
    assert os.path.isfile(path), f"Missing file: {path}"


def test_keygen_executable_and_output():
    path = "/home/user/keygen"
    assert os.path.isfile(path), f"Missing file: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF binary."

    output = run_keygen(path, FIXED_SEED)
    assert output == FIXED_TOKEN, f"Expected output '{FIXED_TOKEN}', got '{output}'"


def test_keygen_general_seed_logic():
    binary = "/home/user/keygen"
    for seed in RANDOM_SEEDS:
        output = run_keygen(binary, seed)
        expected = expected_token(seed)
        assert output == expected, (
            f"For seed {seed}, expected output '{expected}', got '{output}'"
        )


def test_keygen_source_compiles_and_implements_logic():
    source = "/home/user/keygen.c"
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "keygen")
        result = subprocess.run(
            ["gcc", "-std=c11", source, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"keygen.c failed to compile: {result.stderr}"

        for seed in [FIXED_SEED] + RANDOM_SEEDS:
            output = run_keygen(rebuilt, seed)
            expected = expected_token(seed)
            assert output == expected, (
                f"Compiled keygen.c returned '{output}' for seed {seed}; "
                f"expected '{expected}'"
            )


def test_attacker_token_txt():
    path = "/home/user/attacker_token.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == FIXED_TOKEN, f"Expected token '{FIXED_TOKEN}', got '{content}'"


def test_block_attacker_sh():
    path = "/home/user/block_attacker.sh"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_command = "iptables -A INPUT -s 203.0.113.42 -j DROP"
    commands = [line for line in lines if not line.startswith("#")]

    assert any(cmd == expected_command for cmd in commands), (
        f"Expected command '{expected_command}' not found in {path}. "
        f"Found commands: {commands}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
