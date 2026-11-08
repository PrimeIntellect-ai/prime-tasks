#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import pytest


def test_rogue_service_terminated():
    """Verify that no service is listening on a TCP port between 8000 and 9000."""
    try:
        output = subprocess.check_output(['ss', '-tln']).decode()
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute 'ss' command to check listening ports.")

    for port in range(8000, 9001):
        if f":{port} " in output or f":{port}\t" in output or f":{port}\n" in output:
            pytest.fail(f"Rogue service is still listening on port {port}.")


def test_suid_backdoor_fixed():
    """Verify that the SUID permission is removed from the backdoor binary."""
    path = "/var/tmp/.backdoor"
    if os.path.exists(path):
        st = os.stat(path)
        assert not (st.st_mode & stat.S_ISUID), f"File {path} still has SUID permission set."


def test_sshd_config_secured():
    """Verify that PermitRootLogin is explicitly set to an instructed secure value."""
    path = "/etc/ssh/sshd_config"
    assert os.path.isfile(path), f"SSH config not found at {path}."

    with open(path, 'r') as f:
        lines = f.readlines()

    vulnerable = False
    for line in lines:
        line = line.strip()
        if line.startswith("#"):
            continue
        if line.startswith("PermitRootLogin") and "yes" in line:
            vulnerable = True
            break

    assert not vulnerable, f"Vulnerable 'PermitRootLogin yes' configuration is still active in {path}."

    active_values = []
    for raw_line in lines:
        line = raw_line.split('#', 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if fields and fields[0].lower() == 'permitrootlogin':
            assert len(fields) == 2, "PermitRootLogin must have exactly one value."
            active_values.append(fields[1].lower())

    assert active_values, "No active PermitRootLogin directive was found."
    assert all(value in {'prohibit-password', 'no'} for value in active_values), (
        "PermitRootLogin must be set to 'prohibit-password' or 'no'."
    )


def run_program(path, data, description):
    try:
        proc = subprocess.run(
            [path],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
            check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{description} timed out on input of length {len(data)}.")

    if proc.returncode != 0:
        pytest.fail(f"{description} failed with exit code {proc.returncode}.")
    return proc.stdout


def test_decryptor_source_exists_and_builds():
    """Verify that the required C++ source exists, builds, and implements the decryption."""
    source_path = "/home/user/decryptor.cpp"
    oracle_path = "/tests/oracle_decryptor"
    rebuilt_path = "/tmp/decryptor_from_source"

    assert os.path.isfile(source_path), f"Decryptor source missing at {source_path}."
    assert os.path.isfile(oracle_path), f"Oracle decryptor missing at {oracle_path}."
    assert os.access(oracle_path, os.X_OK), f"Oracle decryptor at {oracle_path} is not executable."

    try:
        build = subprocess.run(
            ['g++', source_path, '-o', rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compilation of /home/user/decryptor.cpp timed out.")

    assert build.returncode == 0, (
        "Failed to compile /home/user/decryptor.cpp:\n" +
        build.stderr.decode(errors='replace')
    )

    exhaustive_input = bytes(range(256))
    expected = run_program(oracle_path, exhaustive_input, "Oracle decryptor")
    actual = run_program(rebuilt_path, exhaustive_input, "Decryptor built from source")
    assert actual == expected, "Decryptor built from /home/user/decryptor.cpp produced incorrect output."


def test_decryptor_fuzz_equivalence():
    """Verify that the agent's decryptor behaves exactly like the oracle decryptor on random inputs."""
    oracle_path = "/tests/oracle_decryptor"
    agent_path = "/home/user/decryptor"

    assert os.path.isfile(oracle_path), f"Oracle decryptor missing at {oracle_path}."
    assert os.access(oracle_path, os.X_OK), f"Oracle decryptor at {oracle_path} is not executable."

    assert os.path.isfile(agent_path), f"Agent decryptor missing at {agent_path}."
    assert os.access(agent_path, os.X_OK), f"Agent decryptor at {agent_path} is not executable."

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        length = random.randint(1, 8192)
        fuzz_input = bytes(random.choices(range(256), k=length))

        oracle_out = run_program(oracle_path, fuzz_input, "Oracle decryptor")
        agent_out = run_program(agent_path, fuzz_input, "Agent decryptor")

        if agent_out != oracle_out:
            input_hex = fuzz_input[:32].hex() + ("..." if len(fuzz_input) > 32 else "")
            oracle_hex = oracle_out[:32].hex() + ("..." if len(oracle_out) > 32 else "")
            agent_hex = agent_out[:32].hex() + ("..." if len(agent_out) > 32 else "")
            pytest.fail(
                f"Mismatch on fuzz iteration {i+1} (input length {length}).\n"
                f"Input (hex): {input_hex}\n"
                f"Expected output (hex): {oracle_hex}\n"
                f"Agent output (hex): {agent_hex}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
