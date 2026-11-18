#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any helper process the agent may have left running to proxy the oracle.
if command -v pkill >/dev/null 2>&1 && id user >/dev/null 2>&1; then
    pkill -KILL -u "$(id -u user)" 2>/dev/null || true
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import re
import shutil
import stat
import string
import subprocess

FIXED = "/home/user/fixed_encode.sh"
ORACLE = "/app/oracle_processor"
SANDBOX = "/tmp/fixed-encode-sandbox"


def generate_test_case(rng):
    length = rng.randint(10, 100)
    # Ensure spaces are included to test the regression.
    chars = string.ascii_letters + string.digits + " \t\n!@#$%"
    body = "".join(rng.choice(chars) for _ in range(length))
    if " " not in body:
        body = " " + body[1:]
    return "ENCv1|" + body


def run_proc(cmd, stdin_data, timeout=2):
    try:
        res = subprocess.run(
            cmd,
            input=stdin_data.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        return res.stdout.decode().strip()
    except Exception:
        return None


def copy_binary_and_libs(source, destinations):
    source = os.path.realpath(source)
    for destination in destinations:
        target = os.path.join(SANDBOX, destination.lstrip("/"))
        os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
        shutil.copy2(source, target)
        os.chmod(target, 0o555)

    output = subprocess.check_output(["ldd", source], text=True)
    libraries = set(re.findall(r"(?:=>\s*)?(/[^\s()]+)", output))
    for library in libraries:
        if not os.path.isfile(library):
            continue
        target = os.path.join(SANDBOX, library.lstrip("/"))
        os.makedirs(os.path.dirname(target), mode=0o755, exist_ok=True)
        shutil.copy2(library, target)
        os.chmod(target, 0o555)


def build_sandbox():
    shutil.rmtree(SANDBOX, ignore_errors=True)
    os.makedirs(SANDBOX, mode=0o755)
    for directory in ("bin", "usr/bin", "lib", "lib64", "tmp"):
        os.makedirs(os.path.join(SANDBOX, directory), mode=0o755, exist_ok=True)

    copy_binary_and_libs(shutil.which("bash"), ["/bin/bash", "/usr/bin/bash"])
    for name in ("cat", "tr", "base64", "env"):
        executable = shutil.which(name)
        assert executable is not None, f"Required sandbox utility {name} is unavailable."
        copy_binary_and_libs(executable, [f"/bin/{name}", f"/usr/bin/{name}"])

    shutil.copy2(FIXED, os.path.join(SANDBOX, "fixed_encode.sh"))
    os.chmod(os.path.join(SANDBOX, "fixed_encode.sh"), 0o555)


def run_agent(stdin_data):
    return run_proc(
        ["chroot", "--userspec=65534:65534", SANDBOX, "/fixed_encode.sh"],
        stdin_data,
    )


def test_fixed_encode_exists_and_executable():
    assert os.path.exists(FIXED), f"Fixed script {FIXED} does not exist."
    assert os.path.isfile(FIXED), f"{FIXED} is not a file."

    st = os.stat(FIXED)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Fixed script {FIXED} is not executable."

    with open(FIXED, "rb") as f:
        first_line = f.readline(256)
        remainder = f.read()
    assert first_line.startswith(b"#!") and b"bash" in first_line.lower(), \
        f"{FIXED} is not a Bash script."
    assert b"\x00" not in first_line + remainder, f"{FIXED} contains binary data."
    assert not filecmp.cmp(FIXED, ORACLE, shallow=False), \
        "The submitted artifact is byte-identical to the reference implementation."

    build_sandbox()


def test_fixed_encode_accuracy():
    assert os.path.exists(ORACLE), f"Oracle binary {ORACLE} does not exist."
    assert os.path.isdir(SANDBOX), "Execution sandbox was not created."

    rng = random.SystemRandom()
    test_inputs = [generate_test_case(rng) for _ in range(50)]
    oracle_outputs = [run_proc([ORACLE], value) for value in test_inputs]

    correct = 0
    for test_input, oracle_out in zip(test_inputs, oracle_outputs):
        assert oracle_out is not None, "Oracle processor failed to execute or timed out."
        agent_out = run_agent(test_input)
        if agent_out == oracle_out:
            correct += 1

    accuracy = correct / len(test_inputs)
    assert accuracy >= 1.0, \
        f"Accuracy metric failed: {accuracy} < 1.0. The fixed script output does not perfectly match the oracle for all valid inputs."


def test_missing_magic_string():
    test_input = "INVALID_MAGIC|some random data"
    oracle_out = run_proc([ORACLE], test_input)
    agent_out = run_agent(test_input)

    assert oracle_out is not None, "Oracle processor failed to execute."
    assert agent_out == oracle_out, \
        f"Expected output '{oracle_out}' for missing magic string, but got '{agent_out}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
