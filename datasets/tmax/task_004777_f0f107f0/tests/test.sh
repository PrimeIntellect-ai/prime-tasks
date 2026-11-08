#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile


def test_sandbox_runner_compiled():
    runner_path = "/usr/local/bin/sandbox-runner"
    source_dir = "/app/sandbox-runner-1.2.0"
    source_path = os.path.join(source_dir, "runner.c")
    built_path = os.path.join(source_dir, "sandbox-runner")

    assert os.path.isfile(runner_path), f"sandbox-runner executable not found at {runner_path}"
    assert os.access(runner_path, os.X_OK), f"{runner_path} is not executable"
    assert os.path.isfile(source_path), f"vendored source not found at {source_path}"

    with open(runner_path, "rb") as f:
        installed_binary = f.read()
    assert installed_binary.startswith(b"\x7fELF"), "installed sandbox-runner is not a compiled ELF executable"

    # The repaired C source must compile under the package's strict warning policy.
    with tempfile.TemporaryDirectory() as tmpdir:
        strict_binary = os.path.join(tmpdir, "sandbox-runner")
        compile_result = subprocess.run(
            ["gcc", "-Wall", "-Werror", "-o", strict_binary, source_path],
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, (
            "runner.c still fails strict compilation:\n" + compile_result.stderr
        )

    # The vendored package must also build via make, and the installed file must
    # be the executable produced by that build.
    make_result = subprocess.run(
        ["make", "-B", "sandbox-runner"],
        cwd=source_dir,
        capture_output=True,
        text=True,
    )
    assert make_result.returncode == 0, f"make failed: {make_result.stderr}"
    assert os.path.isfile(built_path), "make did not produce sandbox-runner"
    with open(built_path, "rb") as f:
        rebuilt_binary = f.read()
    assert rebuilt_binary.startswith(b"\x7fELF"), "make output is not a compiled ELF executable"
    assert installed_binary == rebuilt_binary, (
        "/usr/local/bin/sandbox-runner is not the executable built from the vendored package"
    )

    # Test execution to ensure it correctly runs the sandboxed command.
    result = subprocess.run([runner_path, "echo", "isolated"], capture_output=True, text=True)
    assert result.returncode == 0, f"sandbox-runner failed to execute, stderr: {result.stderr}"
    assert "isolated" in result.stdout, "sandbox-runner did not correctly execute the command"


def test_decoder_fuzz_equivalence():
    agent_script = "/home/user/decode_trace.py"
    oracle_bin = "/app/oracle/malware_decoder"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle is not executable at {oracle_bin}"

    random.seed(42)

    for i in range(200):
        length = random.randint(16, 4096)
        test_input = bytes(random.getrandbits(8) for _ in range(length))

        oracle_proc = subprocess.run([oracle_bin], input=test_input, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

        agent_proc = subprocess.run(
            ["/usr/bin/python3", agent_script],
            input=test_input,
            capture_output=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on iteration {i}. Stderr: "
            f"{agent_proc.stderr.decode(errors='ignore')}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Mismatch on iteration {i} (input length {length}).\n"
            f"Oracle output length: {len(oracle_proc.stdout)}\n"
            f"Agent output length: {len(agent_proc.stdout)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
