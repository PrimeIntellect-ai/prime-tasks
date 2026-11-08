#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile


def test_reconstructed_encoder_exists():
    agent_script = "/home/user/reconstructed_encoder.py"
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"{agent_script} is not a file."


def test_fuzz_equivalence():
    oracle_path = "/app/malware_encoder"
    agent_script = "/home/user/reconstructed_encoder.py"

    assert os.path.exists(oracle_path), f"Oracle {oracle_path} does not exist."
    assert os.path.isfile(oracle_path), f"{oracle_path} is not a file."
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"{agent_script} is not a file."

    rng = random.Random(secrets.randbits(256))
    N = 10000
    inputs = [
        "-1000", "1000", "0", "-0", "0.0", "-0.0",
        "1e-30", "-1e-30", "999.9999999999999", "-999.9999999999999",
        "42.0000", "-42.0000", "13.37", "-13.37",
    ]
    while len(inputs) < N:
        choice = rng.randrange(3)
        if choice == 0:
            inputs.append(format(rng.uniform(-1000.0, 1000.0), ".17g"))
        elif choice == 1:
            integer = rng.randint(-999999999999, 999999999999)
            scale = rng.randint(0, 12)
            value = integer / (10 ** scale)
            if -1000.0 <= value <= 1000.0:
                inputs.append(format(value, f".{rng.randint(1, 16)}f"))
        else:
            intermediate = rng.randint(-13369, 13369)
            delta = rng.choice([-1.0, 0.0, 1.0]) * rng.uniform(0.0, 1e-6)
            value = intermediate / 13.37 + delta
            if -1000.0 <= value <= 1000.0:
                inputs.append(format(value, ".17g"))

    input_data = "\n".join(inputs) + "\n"

    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr}"
    oracle_outputs = oracle_proc.stdout.strip().split("\n")

    wrapper_dir = tempfile.mkdtemp(prefix="encoder_wrapper_")
    os.chmod(wrapper_dir, 0o755)
    wrapper_path = os.path.join(wrapper_dir, "run_submission.py")
    with open(wrapper_path, "w", encoding="utf-8") as f:
        f.write(r'''import runpy
import sys

blocked = {
    "subprocess.Popen",
    "os.system",
    "os.fork",
    "os.forkpty",
    "os.posix_spawn",
    "os.posix_spawnp",
    "ctypes.dlopen",
}

def audit(event, args):
    if event in blocked or event.startswith("os.exec") or event.startswith("os.spawn"):
        raise RuntimeError("submission may not execute or load an external native program")

sys.addaudithook(audit)
sys.argv = [sys.argv[1]]
runpy.run_path(sys.argv[0], run_name="__main__")
''')
    os.chmod(wrapper_path, 0o644)

    hidden_dir = tempfile.mkdtemp(prefix="hidden_oracle_")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle")

    try:
        os.rename(oracle_path, hidden_oracle)
        agent_proc = subprocess.run(
            ["runuser", "-u", "user", "--", "/usr/bin/python3", wrapper_path, agent_script],
            input=input_data,
            capture_output=True,
            text=True,
            timeout=30,
        )
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, oracle_path)
        shutil.rmtree(hidden_dir, ignore_errors=True)
        shutil.rmtree(wrapper_dir, ignore_errors=True)

    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_outputs = agent_proc.stdout.strip().split("\n")

    assert len(oracle_outputs) == N, (
        f"Oracle output length ({len(oracle_outputs)}) does not match input length ({N})."
    )
    assert len(agent_outputs) == N, (
        f"Agent output length ({len(agent_outputs)}) does not match input length ({N})."
    )

    for i in range(N):
        assert oracle_outputs[i] == agent_outputs[i], (
            f"Mismatch on input {inputs[i]}:\n"
            f"Oracle output: {oracle_outputs[i]}\n"
            f"Agent output:  {agent_outputs[i]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
