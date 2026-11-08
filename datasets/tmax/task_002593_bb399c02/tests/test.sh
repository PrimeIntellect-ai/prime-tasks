#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess


def test_supervisor_installed():
    """Verify the Makefile fix and installed tinysupervisor executable."""
    makefile = "/app/tinysupervisor-1.0/Makefile"
    assert os.path.isfile(makefile), f"Makefile {makefile} is missing."
    with open(makefile, "r") as f:
        content = f.read()

    assert "PREFX" not in content, "The PREFX typo in the Makefile was not fixed."
    assert content.count("$(PREFIX)/bin") >= 3, "The install recipe does not consistently use $(PREFIX)/bin."

    path = "/home/user/local/bin/tinysupervisor"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did the installation fail or go to the wrong path?"
    assert os.access(path, os.X_OK), f"File {path} exists but is not executable."

    proc = subprocess.run([path], text=True, capture_output=True, timeout=10)
    assert proc.returncode == 0, f"Installed tinysupervisor exited with status {proc.returncode}."
    assert proc.stdout == "tinysupervisor running\n", "Installed tinysupervisor did not run correctly."


def test_git_bare_repo():
    """Verify the deploy.git directory is a bare git repository."""
    path = "/home/user/deploy.git"
    assert os.path.isdir(path), f"Directory {path} does not exist."

    config_path = os.path.join(path, "config")
    assert os.path.isfile(config_path), f"Git config file {config_path} missing. Is it a valid git repo?"

    with open(config_path, "r") as f:
        content = f.read()

    assert "bare = true" in content.lower(), f"Repository at {path} is not configured as a bare repository."


def test_symlink_exists():
    """Verify the pre-receive hook is correctly symlinked to the validator script."""
    link_path = "/home/user/deploy.git/hooks/pre-receive"
    target_path = "/home/user/validate_manifest.sh"

    assert os.path.islink(link_path), f"{link_path} is not a symlink."
    actual_target = os.readlink(link_path)
    assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."


def generate_fuzz_lines(n=2000):
    """Generate valid, boundary-invalid, and random CSV inputs."""
    rng = random.SystemRandom()
    lines = [
        "svc-a,1,8000,registry.local/a:v0",
        "svc-abcdefghij,9,8099,registry.local/abcdefghijklmnopqrst:v9",
        "",
        "svc-a,1,8000",
        "svc-a,1,8000,registry.local/a:v0,extra",
        "svc-,1,8000,registry.local/a:v0",
        "svc-abcdefghijk,1,8000,registry.local/a:v0",
        "svc-A,1,8000,registry.local/a:v0",
        "svc-a,0,8000,registry.local/a:v0",
        "svc-a,10,8000,registry.local/a:v0",
        "svc-a,1,7999,registry.local/a:v0",
        "svc-a,1,8100,registry.local/a:v0",
        "svc-a,1,08000,registry.local/a:v0",
        "svc-a,1,8000,registry.local/:v0",
        "svc-a,1,8000,registry.local/abcdefghijklmnopqrstu:v0",
        "svc-a,1,8000,registry.local/A:v0",
        "svc-a,1,8000,registry.local/a:v10",
    ]
    chars = string.ascii_letters + string.digits + "-,:/!@#$%^&*() ._"

    while len(lines) < n:
        if rng.random() < 0.3:
            svc = "svc-" + "".join(rng.choices(string.ascii_lowercase + string.digits, k=rng.randint(1, 10)))
            replicas = str(rng.randint(1, 9))
            port = str(rng.randint(8000, 8099))
            image_name = "".join(rng.choices(string.ascii_lowercase + string.digits, k=rng.randint(1, 20)))
            image = f"registry.local/{image_name}:v{rng.randint(0, 9)}"
            lines.append(f"{svc},{replicas},{port},{image}")
        else:
            length = rng.randint(0, 150)
            lines.append("".join(rng.choices(chars, k=length)))

    return lines


def test_fuzz_equivalence():
    """Run behavioral equivalence testing against the verification-only oracle."""
    oracle = "/tests/validate_manifest_oracle.sh"
    agent = "/home/user/validate_manifest.sh"

    assert os.path.isfile(oracle), f"Verification oracle {oracle} is missing."
    assert os.path.isfile(agent), f"Agent script {agent} is missing."
    assert not os.path.islink(agent), f"Agent script {agent} must be a real file, not a symlink."
    assert os.access(agent, os.X_OK), f"Agent script {agent} is not executable."

    with open(oracle, "rb") as f:
        oracle_bytes = f.read()
    with open(agent, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent script must not be a byte-identical copy of the reference implementation."

    with open(agent, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert re.search(r"(^|/)bash(?:\s|$)", first_line), "Validator must be a Bash script."

    lines = generate_fuzz_lines(2000)
    input_data = "\n".join(lines) + "\n"

    oracle_proc = subprocess.run(["/bin/bash", oracle], input=input_data, text=True, capture_output=True, timeout=30)
    agent_proc = subprocess.run([agent], input=input_data, text=True, capture_output=True, timeout=30)

    assert oracle_proc.returncode == 0 or agent_proc.returncode == oracle_proc.returncode, "Agent script returned a different exit code than the oracle."
    assert agent_proc.returncode == oracle_proc.returncode, "Agent script returned a different exit code than the oracle."

    oracle_out = oracle_proc.stdout.splitlines()
    agent_out = agent_proc.stdout.splitlines()

    assert len(oracle_out) == len(agent_out), f"Output line count mismatch. Oracle produced {len(oracle_out)} lines, Agent produced {len(agent_out)} lines."

    for i, (o, a) in enumerate(zip(oracle_out, agent_out)):
        assert o == a, (
            f"Mismatch on input line {i+1}:\n"
            f"Input:  {repr(lines[i])}\n"
            f"Oracle: {o}\n"
            f"Agent:  {a}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
