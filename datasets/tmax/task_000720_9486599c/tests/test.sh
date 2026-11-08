#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "yaml:pyyaml"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile

import pytest
import yaml


def test_docker_compose_configuration():
    path = "/home/user/edge-stack/docker-compose.yml"
    assert os.path.isfile(path), f"Docker Compose file is missing at {path}"

    with open(path, "r") as f:
        compose_data = yaml.safe_load(f)

    assert "services" in compose_data
    assert "api" in compose_data["services"]
    assert "worker" in compose_data["services"]

    api_networks = compose_data["services"]["api"].get("networks", [])
    worker_networks = compose_data["services"]["worker"].get("networks", [])

    assert "edge_net" in api_networks, "api service is not connected to edge_net"
    assert "edge_net" in worker_networks, "worker service is not connected to edge_net"

    assert "networks" in compose_data
    assert "edge_net" in compose_data["networks"], "edge_net is not defined in the top-level networks block"


def test_docker_containers_running_and_connected():
    cmd_ps = ["docker", "ps", "--format", "{{.Names}}"]
    result_ps = subprocess.run(cmd_ps, capture_output=True, text=True)

    assert result_ps.returncode == 0, "Failed to run docker ps"
    running_containers = result_ps.stdout.splitlines()

    api_container = next((c for c in running_containers if "api" in c), None)
    worker_container = next((c for c in running_containers if "worker" in c), None)

    assert api_container is not None, "api container is not running"
    assert worker_container is not None, "worker container is not running"

    cmd_curl = ["docker", "exec", worker_container, "curl", "-s", "http://api"]
    result_curl = subprocess.run(cmd_curl, capture_output=True, text=True)

    assert result_curl.returncode == 0, f"Worker could not reach API. Curl output: {result_curl.stderr}"
    assert "Welcome to nginx!" in result_curl.stdout or "<html" in result_curl.stdout, "API did not return expected Nginx response"


def random_case(value):
    return "".join(
        ch.upper() if ch.isalpha() and secrets.randbelow(2) else ch.lower()
        for ch in value
    )


def random_text():
    alphabet = string.ascii_letters + string.digits
    words = [
        "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10) + 3))
        for _ in range(secrets.randbelow(10) + 4)
    ]
    return " ".join(words)


def test_sanitizer_script_adversarial_corpus():
    script_path = "/home/user/sanitize.py"
    assert os.path.isfile(script_path), f"Sanitizer script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Sanitizer script at {script_path} is not executable"

    with open(script_path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "python" in first_line.lower(), "Sanitizer must begin with a Python shebang"

    phrase = "initiate protocol blackbird"
    cases = [
        "turn on the lights",
        "set temperature to 72",
        "what is the weather",
        "initiate the protocol blackbird",
        "initiate protocol bluebird",
        "protocol blackbird initiate",
        "initiate-protocol-blackbird",
        "initiate  protocol blackbird",
    ]

    for _ in range(32):
        cases.append(random_text())
        cases.append(
            random_text()
            + secrets.choice([" ", "\n", " :: "])
            + random_case(phrase)
            + secrets.choice([" ", "\n", " !!! "])
            + random_text()
        )

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="command-check-") as temp_dir:
        # Reuse one neutral, random path for every case so behavior cannot be
        # inferred from directory names or filenames.
        command_path = os.path.join(temp_dir, secrets.token_hex(12) + ".txt")

        with open(command_path, "w", encoding="utf-8") as f:
            f.write("ordinary command")

        no_arg = subprocess.run([script_path], capture_output=True, timeout=5)
        two_args = subprocess.run([script_path, command_path, command_path], capture_output=True, timeout=5)
        assert no_arg.returncode != 0, "Sanitizer must reject invocation without a file argument"
        assert two_args.returncode != 0, "Sanitizer must accept exactly one CLI argument"

        failures = []
        for index, content in enumerate(cases):
            with open(command_path, "w", encoding="utf-8") as f:
                f.write(content)

            expected = 1 if phrase.casefold() in content.casefold() else 0
            result = subprocess.run([script_path, command_path], capture_output=True, timeout=5)
            if result.returncode != expected:
                failures.append(
                    f"case {index}: expected exit {expected}, got {result.returncode}"
                )

        if failures:
            pytest.fail("Sanitizer behavior was incorrect: " + " | ".join(failures[:10]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
