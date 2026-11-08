#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import random
import re
import shutil
import subprocess
import sysconfig
import tempfile

import pytest

ORACLE_PATH = "/app/policy_engine.bin"
AGENT_SCRIPT = "/home/user/policy_engine.py"
PYTHON_BIN = "/usr/bin/python3"


def generate_random_ip():
    rand_val = random.random()
    if rand_val < 0.2:
        return f"10.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"
    elif rand_val < 0.4:
        return f"192.168.{random.randint(0, 255)}.{random.randint(0, 255)}"
    return f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"


def generate_random_port():
    if random.random() < 0.3:
        return 22
    return random.randint(1, 65535)


def generate_random_input():
    ip = generate_random_ip()
    port = generate_random_port()
    key_type = random.choice(["rsa", "dsa", "ecdsa", "ed25519"])
    key_length = random.choice([1024, 2048, 3072, 4096, 256, 521])
    return f"{ip} {port} {key_type} {key_length}"


def _copy_absolute(source, jail):
    destination = os.path.join(jail, source.lstrip("/"))
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.copy2(source, destination, follow_symlinks=True)


def _ldd_dependencies(path):
    output = subprocess.run(
        ["ldd", path], text=True, capture_output=True, check=True
    ).stdout
    dependencies = set()
    for line in output.splitlines():
        match = re.search(r"(?:=>\s*)?(/[^\s]+)", line)
        if match and os.path.isfile(match.group(1)):
            dependencies.add(match.group(1))
    return dependencies


def build_python_jail():
    jail = tempfile.mkdtemp(prefix="policy-engine-jail-")
    os.chmod(jail, 0o755)

    os.makedirs(os.path.join(jail, "usr/bin"), exist_ok=True)
    shutil.copy2(os.path.realpath(PYTHON_BIN), os.path.join(jail, "usr/bin/python3"))

    path_data = subprocess.run(
        [PYTHON_BIN, "-c", "import json,sysconfig; print(json.dumps(sysconfig.get_paths()))"],
        text=True,
        capture_output=True,
        check=True,
    )
    python_paths = json.loads(path_data.stdout)
    library_roots = {
        python_paths.get("stdlib"),
        python_paths.get("platstdlib"),
    }
    library_roots.discard(None)

    for source in library_roots:
        if os.path.isdir(source):
            destination = os.path.join(jail, source.lstrip("/"))
            shutil.copytree(source, destination, dirs_exist_ok=True)

    native_files = [os.path.realpath(PYTHON_BIN)]
    for root in library_roots:
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for name in files:
                if ".so" in name:
                    native_files.append(os.path.join(directory, name))

    dependencies = set()
    for native_file in native_files:
        try:
            dependencies.update(_ldd_dependencies(native_file))
        except subprocess.CalledProcessError:
            pass
    for dependency in dependencies:
        _copy_absolute(dependency, jail)

    jailed_script = os.path.join(jail, "home/user/policy_engine.py")
    os.makedirs(os.path.dirname(jailed_script), mode=0o755, exist_ok=True)
    shutil.copyfile(AGENT_SCRIPT, jailed_script)
    os.chmod(jailed_script, 0o444)
    os.makedirs(os.path.join(jail, "tmp"), mode=0o777, exist_ok=True)
    os.chmod(os.path.join(jail, "tmp"), 0o1777)

    account = pwd.getpwnam("user")
    chroot_bin = shutil.which("chroot")
    assert chroot_bin, "chroot utility is unavailable"
    command = [
        chroot_bin,
        f"--userspec={account.pw_uid}:{account.pw_gid}",
        jail,
        "/usr/bin/python3",
        "-B",
        "/home/user/policy_engine.py",
    ]
    return jail, command


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable"

    jail, agent_cmd = build_python_jail()
    try:
        random.seed(42)
        num_tests = 1000

        for _ in range(num_tests):
            test_input = generate_random_input()

            try:
                oracle_proc = subprocess.run(
                    [ORACLE_PATH],
                    input=test_input,
                    text=True,
                    capture_output=True,
                    timeout=2,
                    check=True,
                )
                oracle_output = oracle_proc.stdout.strip()
            except subprocess.CalledProcessError as exc:
                pytest.fail(f"Oracle failed on input '{test_input}': {exc.stderr}")
            except subprocess.TimeoutExpired:
                pytest.fail(f"Oracle timed out on input '{test_input}'")

            try:
                agent_proc = subprocess.run(
                    agent_cmd,
                    input=test_input,
                    text=True,
                    capture_output=True,
                    timeout=2,
                    env={
                        "PATH": "/usr/bin:/bin",
                        "PYTHONDONTWRITEBYTECODE": "1",
                        "LANG": "C.UTF-8",
                    },
                )
                agent_output = agent_proc.stdout.strip()
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent script timed out on input '{test_input}'")

            if agent_proc.returncode != 0:
                pytest.fail(
                    f"Agent script crashed on input '{test_input}'. Stderr: {agent_proc.stderr}"
                )

            assert agent_output == oracle_output, (
                f"Output mismatch on input '{test_input}'\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent):       {agent_output}"
            )
    finally:
        shutil.rmtree(jail, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
