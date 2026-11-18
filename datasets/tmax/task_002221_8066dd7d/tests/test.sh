#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import string
import subprocess
import tempfile
import pytest


def generate_random_ip():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"


def generate_random_string(min_len=1, max_len=20):
    length = random.randint(min_len, max_len)
    chars = string.ascii_letters + string.digits + "-_."
    return "".join(random.choices(chars, k=length))


def generate_random_package():
    # To ensure we hit the edge cases, occasionally inject "eval", "exec", "npm", "0."
    name = generate_random_string()
    if random.random() < 0.1:
        name += "eval"
    elif random.random() < 0.1:
        name += "exec"

    version = generate_random_string()
    if random.random() < 0.2:
        version = "0." + version

    ecosystem = generate_random_string()
    if random.random() < 0.3:
        ecosystem = "npm"

    return {
        "name": name,
        "version": version,
        "ecosystem": ecosystem,
    }


def generate_random_input():
    num_packages = random.randint(0, 10)
    packages = [generate_random_package() for _ in range(num_packages)]
    return {
        "client_ip": generate_random_ip(),
        "packages": packages,
    }


def test_fuzz_equivalence():
    oracle_path = "/app/build_sec_proxy"
    agent_file = "/home/user/build_sec_proxy.go"

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle binary not executable at {oracle_path}"
    assert os.path.isfile(agent_file), f"Agent Go file missing at {agent_file}"

    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    with open(agent_file, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submission must not be a byte-identical copy of the oracle"

    random.seed(42)
    num_tests = 500
    cases = [generate_random_input() for _ in range(num_tests)]

    with tempfile.TemporaryDirectory() as temp_dir:
        expected_outputs = []
        serialized_cases = []

        # Derive all expected answers before making the oracle unavailable.
        for i, input_data in enumerate(cases):
            serialized = json.dumps(input_data)
            serialized_cases.append(serialized)
            input_file = os.path.join(temp_dir, f"oracle_input_{i}.json")
            with open(input_file, "w") as f:
                f.write(serialized)

            oracle_res = subprocess.run(
                [oracle_path, input_file],
                capture_output=True,
                text=True,
            )
            expected_outputs.append(oracle_res.stdout.strip())

        # The submitted program must stand alone; it must not delegate to the
        # legacy executable while being exercised.
        os.remove(oracle_path)

        built_agent = os.path.join(temp_dir, "agent")
        build_res = subprocess.run(
            ["go", "build", "-o", built_agent, agent_file],
            capture_output=True,
            text=True,
            env={**os.environ, "CGO_ENABLED": "0"},
        )
        assert build_res.returncode == 0, (
            f"Failed to compile submitted Go program:\n{build_res.stderr}"
        )

        # Execute in a minimal chroot so copies or alternate paths to the
        # legacy executable are not visible to the submitted program.
        jail = os.path.join(temp_dir, "jail")
        os.mkdir(jail, 0o755)
        jailed_agent = os.path.join(jail, "agent")
        shutil.copy2(built_agent, jailed_agent)
        os.chmod(jailed_agent, 0o755)
        jailed_input = os.path.join(jail, "input.json")

        for i, (input_data, serialized, oracle_output) in enumerate(
            zip(cases, serialized_cases, expected_outputs)
        ):
            with open(jailed_input, "w") as f:
                f.write(serialized)
            os.chmod(jailed_input, 0o644)

            agent_res = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail, "/agent", "/input.json"],
                capture_output=True,
                text=True,
            )
            agent_output = agent_res.stdout.strip()

            if oracle_output != agent_output:
                error_msg = (
                    f"Mismatch on test case {i}!\n"
                    f"Input: {json.dumps(input_data)}\n"
                    f"Oracle output: {oracle_output}\n"
                    f"Agent output:  {agent_output}\n"
                    f"Agent stderr:  {agent_res.stderr.strip()}"
                )
                pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
