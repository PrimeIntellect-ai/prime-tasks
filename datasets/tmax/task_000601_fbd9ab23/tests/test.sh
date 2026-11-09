#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/log_packer"
AGENT_PATH = "/home/user/log_packer/target/release/log_packer"


def generate_random_string(length):
    chars = string.ascii_letters + string.digits + string.punctuation + " \n"
    return "".join(random.choice(chars) for _ in range(length))


def generate_fuzz_input():
    num_entries = random.randint(5, 50)
    entries = []
    prev_entry = ""

    for _ in range(num_entries):
        if prev_entry and random.random() < 0.5:
            prefix_len = int(len(prev_entry) * random.uniform(0.5, 0.9))
            prefix = prev_entry[:prefix_len]
            suffix_len = random.randint(10, 1000)
            entry = (prefix + generate_random_string(suffix_len))[:1000]
            if len(entry) < 10:
                entry += generate_random_string(10 - len(entry))
        else:
            entry = generate_random_string(random.randint(10, 1000))

        entry = entry.replace("===\n", "== \n")
        entries.append(entry)
        prev_entry = entry

    return "".join(f"{entry}===\n" for entry in entries).encode("utf-8")


def copy_into_root(root, source):
    destination = os.path.join(root, source.lstrip("/"))
    os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
    shutil.copy2(source, destination, follow_symlinks=True)


def make_sandbox():
    root = tempfile.mkdtemp(prefix="log_packer_sandbox_")
    os.chmod(root, 0o755)
    copy_into_root(root, AGENT_PATH)
    os.chmod(os.path.join(root, AGENT_PATH.lstrip("/")), 0o755)

    ldd_proc = subprocess.run(
        ["ldd", AGENT_PATH], capture_output=True, text=True
    )
    ldd_text = ldd_proc.stdout + ldd_proc.stderr
    if ldd_proc.returncode != 0 and "not a dynamic executable" not in ldd_text:
        shutil.rmtree(root)
        pytest.fail(f"Could not inspect agent runtime dependencies:\n{ldd_text}")

    for dependency in sorted(set(re.findall(r"(/[^^\s()]+)", ldd_text))):
        if os.path.isfile(dependency):
            copy_into_root(root, dependency)

    return root


def test_fuzz_equivalence_without_oracle_delegation():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}. Did you compile in release mode?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable."

    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()

    assert agent_bytes.startswith(b"\x7fELF"), "Agent executable is not an ELF binary."
    assert agent_bytes != oracle_bytes, "Agent executable is byte-identical to the reference binary."

    random.seed(42)
    cases = [generate_fuzz_input() for _ in range(1000)]
    expected = []

    for i, fuzz_input in enumerate(cases):
        oracle_proc = subprocess.run(
            [ORACLE_PATH], input=fuzz_input, capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        expected.append(oracle_proc.stdout)

    # Expected outputs are now fixed. Remove the oracle before any submitted code
    # executes, so the submission cannot delegate work to /app/log_packer.
    os.unlink(ORACLE_PATH)
    sandbox = make_sandbox()

    try:
        for i, (fuzz_input, oracle_output) in enumerate(zip(cases, expected)):
            agent_proc = subprocess.run(
                [
                    "chroot",
                    "--userspec=65534:65534",
                    sandbox,
                    AGENT_PATH,
                ],
                input=fuzz_input,
                capture_output=True,
            )

            if agent_proc.returncode != 0:
                pytest.fail(
                    f"Agent program crashed or returned non-zero exit code on iteration {i}.\n"
                    f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
                )

            if oracle_output != agent_proc.stdout:
                oracle_hex = oracle_output.hex()
                agent_hex = agent_proc.stdout.hex()
                oracle_disp = oracle_hex[:200] + ("..." if len(oracle_hex) > 200 else "")
                agent_disp = agent_hex[:200] + ("..." if len(agent_hex) > 200 else "")
                pytest.fail(
                    f"Output mismatch on iteration {i}.\n"
                    f"Input length: {len(fuzz_input)} bytes\n"
                    f"Oracle output (hex): {oracle_disp}\n"
                    f"Agent output (hex):  {agent_disp}\n"
                )
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
