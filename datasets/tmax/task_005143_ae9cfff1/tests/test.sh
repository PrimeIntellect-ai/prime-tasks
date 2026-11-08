#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import random
import re
import shutil
import stat
import string
import subprocess
import tempfile
import pytest


def get_random_string(length, rng):
    letters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(rng.choice(letters) for _ in range(length))


def native_python_check(script_path):
    st = os.lstat(script_path)
    assert stat.S_ISREG(st.st_mode), f"The path {script_path} is not a regular file."

    with open(script_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=script_path)

    forbidden_modules = {
        "subprocess", "ctypes", "cffi", "pexpect", "_posixsubprocess",
        "importlib", "runpy"
    }
    forbidden_os_calls = {
        "system", "popen", "execl", "execle", "execlp", "execlpe",
        "execv", "execve", "execvp", "execvpe", "posix_spawn",
        "posix_spawnp", "spawnl", "spawnle", "spawnlp", "spawnlpe",
        "spawnv", "spawnve", "spawnvp", "spawnvpe"
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split('.')[0] not in forbidden_modules, \
                    f"External process/native delegation is not a native Python implementation: {alias.name}"
        elif isinstance(node, ast.ImportFrom):
            module = (node.module or "").split('.')[0]
            assert module not in forbidden_modules, \
                f"External process/native delegation is not a native Python implementation: {node.module}"
            if module == "os":
                for alias in node.names:
                    assert alias.name not in forbidden_os_calls, \
                        f"External process execution is not allowed: os.{alias.name}"
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id != "__import__", "Dynamic importing is not allowed."
                assert node.func.id not in forbidden_os_calls, \
                    f"External process execution is not allowed: {node.func.id}"
            elif isinstance(node.func, ast.Attribute):
                assert node.func.attr not in forbidden_os_calls, \
                    f"External process execution is not allowed: {node.func.attr}"


def djb2_expected(value):
    h = 5381
    for c in value.encode("ascii"):
        h = ((h * 33) + c) & 0xffffffff
    return f"{h:08x}"


def drop_to_user():
    user = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def test_hash_algo_accuracy():
    script_path = "/home/user/hash_algo.py"
    binary_path = "/app/auth_cli"

    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.path.isfile(binary_path), f"The binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The binary {binary_path} is not executable."
    native_python_check(script_path)

    rng = random.SystemRandom()
    total = 100
    cases = [get_random_string(rng.randint(5, 50), rng) for _ in range(total)]
    expected_outputs = []

    # Preserve the original oracle comparison while independently deriving each
    # answer, before making the oracle unavailable to the submitted program.
    for test_str in cases:
        try:
            bin_out = subprocess.check_output([binary_path, test_str], timeout=3).decode("utf-8").strip()
        except Exception as e:
            pytest.fail(f"Failed to run binary {binary_path} with input {test_str}: {e}")
        expected = djb2_expected(test_str)
        assert bin_out == expected, f"Reference binary disagreed with the independently derived answer for {test_str!r}."
        expected_outputs.append(expected)

    stash_dir = tempfile.mkdtemp(prefix="auth-oracle-", dir="/root")
    os.chmod(stash_dir, 0o700)
    stashed_binary = os.path.join(stash_dir, "auth_cli")
    shutil.move(binary_path, stashed_binary)

    matches = 0
    try:
        assert not os.path.exists(binary_path), "The reference binary remained available during submission execution."

        for test_str, expected in zip(cases, expected_outputs):
            try:
                raw_out = subprocess.check_output(
                    ["python3", script_path, test_str],
                    stderr=subprocess.DEVNULL,
                    timeout=3,
                    cwd="/home/user",
                    env={"PATH": "/usr/local/bin:/usr/bin:/bin", "LANG": "C.UTF-8"},
                    preexec_fn=drop_to_user,
                )
                py_out = raw_out.decode("utf-8")
            except Exception:
                py_out = ""

            assert re.fullmatch(r"[0-9a-f]{8}\n", py_out) is not None, \
                f"Output for {test_str!r} was not exactly one lowercase 8-character hex value."
            if expected == py_out.strip():
                matches += 1
    finally:
        if os.path.exists(stashed_binary):
            shutil.move(stashed_binary, binary_path)
        os.rmdir(stash_dir)

    accuracy = matches / total
    assert accuracy >= 1.0, f"Accuracy is {accuracy}, expected 1.0. The script output did not match the binary output perfectly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
