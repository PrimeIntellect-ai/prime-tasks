#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_agent_isolated.py
import runpy
import sys

BLOCKED_EVENTS = {
    "os.exec",
    "os.fork",
    "os.forkpty",
    "os.posix_spawn",
    "os.posix_spawnp",
    "os.system",
    "pty.spawn",
}

def audit_hook(event, args):
    if event.startswith("subprocess.") or event in BLOCKED_EVENTS:
        raise PermissionError(f"External process execution is not permitted: {event}")

sys.addaudithook(audit_hook)
sys.argv = [sys.argv[1]]
runpy.run_path(sys.argv[0], run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import random
import stat
import string
import subprocess
import pytest

ORACLE_PATH = "/app/legacy_cleaner"
AGENT_SCRIPT = "/home/user/replicated_cleaner.py"
RUNNER_PATH = "/tmp/run_agent_isolated.py"


def generate_random_input():
    length = random.randint(0, 50)
    chars = string.ascii_letters + string.digits + " "
    text = "".join(random.choice(chars) for _ in range(length))
    v0 = random.uniform(-100.0, 100.0)
    v1 = random.uniform(-100.0, 100.0)
    v2 = random.uniform(-100.0, 100.0)
    return f"{text}|{v0},{v1},{v2}"


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def remove_oracle_copies(oracle_hash, oracle_size):
    for root in ("/home", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root, topdown=True, followlinks=False):
            for name in files:
                path = os.path.join(directory, name)
                if path in (AGENT_SCRIPT, RUNNER_PATH):
                    continue
                try:
                    info = os.lstat(path)
                    if not stat.S_ISREG(info.st_mode) or info.st_size != oracle_size:
                        continue
                    if file_hash(path) == oracle_hash:
                        os.unlink(path)
                except (FileNotFoundError, PermissionError, OSError):
                    pass


def validate_python_source():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} not found."
    assert stat.S_ISREG(os.stat(AGENT_SCRIPT, follow_symlinks=False).st_mode), "Agent script must be a regular Python file."

    with open(AGENT_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=AGENT_SCRIPT)
        compile(tree, AGENT_SCRIPT, "exec")
    except (SyntaxError, UnicodeError) as exc:
        pytest.fail(f"Agent script is not valid Python source: {exc}")

    forbidden_modules = {"subprocess", "_posixsubprocess", "ctypes", "multiprocessing", "pty"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split(".")[0] not in forbidden_modules, "The Python migration may not launch or wrap an external executable."
        elif isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split(".")[0] not in forbidden_modules, "The Python migration may not launch or wrap an external executable."


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} not found."
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} not found."
    validate_python_source()

    random.seed(42)
    inputs = [(generate_random_input() + "\n") for _ in range(1000)]
    expected = []

    for input_data in inputs:
        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                text=True,
                capture_output=True,
                check=True,
            )
            expected.append(oracle_res.stdout.strip())
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle failed on input {input_data.strip()}: {exc.stderr}")

    oracle_info = os.stat(ORACLE_PATH)
    oracle_hash = file_hash(ORACLE_PATH)
    remove_oracle_copies(oracle_hash, oracle_info.st_size)
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH), "Oracle remained accessible during agent execution."

    for input_data, oracle_out in zip(inputs, expected):
        try:
            agent_res = subprocess.run(
                ["/usr/bin/python3", "-I", RUNNER_PATH, AGENT_SCRIPT],
                input=input_data,
                text=True,
                capture_output=True,
                check=True,
                cwd="/home/user",
                env={"PATH": "/usr/bin:/bin", "HOME": "/home/user", "PYTHONNOUSERSITE": "1"},
            )
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Agent script failed on input {input_data.strip()}: {exc.stderr}")

        assert oracle_out == agent_out, (
            f"Mismatch on input: {input_data.strip()}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
