#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import stat
import subprocess
import pytest


def test_firewall_block_script():
    """Test that the firewall block script contains the correct executable iptables rule."""
    script_path = "/home/user/firewall_block.sh"
    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"

    with open(script_path, "r") as f:
        content = f.read().strip()

    # Preserve the original component checks.
    assert "iptables" in content, "Script does not contain 'iptables' command."
    assert "-A OUTPUT" in content or "-I OUTPUT" in content, "Script does not append or insert to the OUTPUT chain."
    assert "-p tcp" in content, "Script does not specify TCP protocol."
    assert "-d 192.168.45.99" in content, "Script does not specify the correct destination IP (192.168.45.99)."
    assert "--dport 8080" in content, "Script does not specify the correct destination port (8080)."
    assert "-j DROP" in content, "Script does not DROP the traffic."

    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Firewall script is not valid bash: {syntax.stderr}"

    # Comments and unrelated commands do not count: the script's sole executable
    # line must be the exact requested iptables invocation.
    executable_lines = []
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        executable_lines.append(stripped)

    assert len(executable_lines) == 1, "Script must contain exactly one executable command."
    try:
        command = shlex.split(executable_lines[0], comments=True, posix=True)
    except ValueError as exc:
        pytest.fail(f"Could not parse firewall command: {exc}")

    valid_commands = [
        ["iptables", "-A", "OUTPUT", "-p", "tcp", "-d", "192.168.45.99", "--dport", "8080", "-j", "DROP"],
        ["iptables", "-I", "OUTPUT", "-p", "tcp", "-d", "192.168.45.99", "--dport", "8080", "-j", "DROP"],
    ]
    assert command in valid_commands, "Firewall script does not contain the exact executable iptables command."


def test_rust_obfuscator_fuzz_equivalence():
    """Build the Rust source afresh and compare it exactly with the recovered obfuscator."""
    oracle_path = "/app/c2_obfuscator"
    project_path = "/home/user/rust_obfuscator"
    manifest_path = os.path.join(project_path, "Cargo.toml")
    source_path = os.path.join(project_path, "src", "main.rs")
    agent_path = os.path.join(project_path, "target", "release", "rust_obfuscator")

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    assert os.path.isdir(project_path) and not os.path.islink(project_path), \
        f"Rust project directory not found at {project_path}"
    for required in (manifest_path, source_path):
        assert os.path.exists(required), f"Required Rust project file not found: {required}"
        assert not os.path.islink(required), f"Required Rust project file must not be a symlink: {required}"
        assert stat.S_ISREG(os.lstat(required).st_mode), f"Required path is not a regular file: {required}"
        assert os.path.getsize(required) > 0, f"Required Rust project file is empty: {required}"

    # Remove any submitted binary/cached artifacts and require Cargo to recreate
    # the requested release executable from the submitted project.
    clean = subprocess.run(
        ["cargo", "clean", "--manifest-path", manifest_path],
        cwd=project_path,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", manifest_path],
        cwd=project_path,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust release build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(agent_path), f"Release build did not create {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Freshly built binary at {agent_path} is not executable"

    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes.startswith(b"\x7fELF"), "Fresh Cargo output is not an ELF executable."
    assert agent_bytes != oracle_bytes, "Submitted executable is byte-identical to the recovered oracle binary."

    random.seed(42)
    iterations = 1000

    for i in range(iterations):
        length = random.randint(0, 65536)
        input_data = bytearray(random.getrandbits(8) for _ in range(length))

        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_data,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [agent_path],
            input=input_data,
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, \
            f"Exit code mismatch on iteration {i} (len={length}). Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

        if agent_proc.stdout != oracle_proc.stdout:
            out_oracle = oracle_proc.stdout[:100].hex() + ("..." if len(oracle_proc.stdout) > 100 else "")
            out_agent = agent_proc.stdout[:100].hex() + ("..." if len(agent_proc.stdout) > 100 else "")
            pytest.fail(f"Output mismatch on iteration {i} (len={length}).\nOracle stdout (hex): {out_oracle}\nAgent stdout (hex): {out_agent}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
