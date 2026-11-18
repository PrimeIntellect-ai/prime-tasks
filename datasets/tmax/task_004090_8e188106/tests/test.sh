#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import stat
import string
import subprocess
import tempfile
import pytest


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def test_fuzz_equivalence_and_source_build():
    oracle_path = "/tests/payload_decoder_oracle"
    agent_path = "/home/user/clean_decoder"
    source_path = "/home/user/clean_decoder.cpp"

    # Preserve the original executable assertions.
    assert os.path.exists(agent_path), f"Agent executable not found at {agent_path}"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} is not a file"
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable"
    assert os.path.exists(oracle_path), f"Oracle executable not found at {oracle_path}"

    # The requested C++ source must be a real regular file.
    assert os.path.exists(source_path), f"C++ source not found at {source_path}"
    source_stat = os.lstat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), f"C++ source {source_path} is not a regular file"
    assert source_stat.st_size > 0, f"C++ source {source_path} is empty"

    # A direct copy of the shipped reference executable is not an implementation.
    assert sha256(agent_path) != sha256(oracle_path), \
        "Agent executable is byte-identical to the reference executable"

    N = 500
    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation
    inputs = []
    for _ in range(N):
        length = random.randint(1, 64)
        inputs.append("".join(random.choice(charset) for _ in range(length)))

    expected = []
    for input_str in inputs:
        oracle_res = subprocess.run(
            [oracle_path, input_str],
            capture_output=True,
            text=True,
            timeout=2
        )
        assert oracle_res.returncode == 0, f"Oracle failed on input: {input_str!r}"
        expected.append(oracle_res.stdout.strip())

    # Preserve the original behavioral check of the submitted executable.
    for input_str, oracle_output in zip(inputs, expected):
        agent_res = subprocess.run(
            [agent_path, input_str],
            capture_output=True,
            text=True,
            timeout=2
        )
        if agent_res.returncode != 0:
            pytest.fail(
                f"Agent executable failed (return code {agent_res.returncode}) "
                f"on input: {input_str!r}\nStderr: {agent_res.stderr}"
            )
        agent_output = agent_res.stdout.strip()
        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on input: {input_str!r}\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent):       {agent_output}"
            )

    # Independently compile the submitted source. A static build is then run in an
    # empty chroot so it cannot pass by invoking the malware binary or an oracle.
    with tempfile.TemporaryDirectory(prefix="decoder-jail-") as jail:
        rebuilt_path = os.path.join(jail, "clean_decoder")
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", "-static", "-s", source_path, "-o", rebuilt_path],
            capture_output=True,
            text=True,
            timeout=30
        )
        assert build.returncode == 0, f"Failed to compile clean_decoder.cpp:\n{build.stderr}"
        assert os.path.isfile(rebuilt_path), "Compiler did not produce an executable"
        assert os.access(rebuilt_path, os.X_OK), "Rebuilt executable is not executable"
        os.chmod(jail, 0o755)
        os.chmod(rebuilt_path, 0o755)

        for input_str, oracle_output in zip(inputs, expected):
            rebuilt_res = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail, "/clean_decoder", input_str],
                capture_output=True,
                text=True,
                timeout=2
            )
            if rebuilt_res.returncode != 0:
                pytest.fail(
                    f"Rebuilt source failed (return code {rebuilt_res.returncode}) "
                    f"on input: {input_str!r}\nStderr: {rebuilt_res.stderr}"
                )
            rebuilt_output = rebuilt_res.stdout.strip()
            if oracle_output != rebuilt_output:
                pytest.fail(
                    f"Rebuilt source mismatch on input: {input_str!r}\n"
                    f"Expected (Oracle): {oracle_output}\n"
                    f"Got (Rebuilt):     {rebuilt_output}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
