#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import random
import re
import secrets
import shutil
import string
import subprocess
import tempfile
import time

AGENT_SCRIPT = "/home/user/secure_hasher.py"
BINARY = "/app/log_hasher"
RUN_USER = pwd.getpwnam("user")


def demote():
    os.setgroups([])
    os.setgid(RUN_USER.pw_gid)
    os.setuid(RUN_USER.pw_uid)


def generate_random_file(directory, size=1024):
    name = ''.join(random.choices(string.ascii_letters + string.digits, k=10)) + ".txt"
    path = os.path.join(directory, name)
    with open(path, "wb") as f:
        f.write(os.urandom(size))
    os.chmod(path, 0o644)
    return path


def run_cmd(cmd):
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
            preexec_fn=demote,
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception:
        return "ERROR"


def random_token():
    alphabet = string.ascii_letters + string.digits + "_-"
    return ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(18) + 6))


def generate_malicious_payloads(count):
    payloads = [
        "../../../etc/passwd",
        "file; id",
        "file && whoami",
        "../../var/log",
        "test|ls",
        "test`id`",
        "test$(id)",
        "/etc/shadow",
        "../app/log_hasher",
    ]
    builders = [
        lambda a, b: f"../{a}/{b}",
        lambda a, b: f"{a}/../{b}",
        lambda a, b: f"../../{a}/{b}",
        lambda a, b: f"{a}; {b}",
        lambda a, b: f"{a} && {b}",
        lambda a, b: f"{a}|{b}",
        lambda a, b: f"{a}`{b}`",
        lambda a, b: f"{a}$({b})",
    ]
    while len(payloads) < count:
        a, b = random_token(), random_token()
        payloads.append(secrets.choice(builders)(a, b))
    random.SystemRandom().shuffle(payloads)
    return payloads


def validate_python_script():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist or is not a regular file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

    with open(AGENT_SCRIPT, "rb") as f:
        source_bytes = f.read()
    first_line = source_bytes.splitlines()[0].decode("ascii", errors="replace") if source_bytes else ""
    assert re.match(r"^#!(?:/usr/bin/python3|/bin/python3|/usr/bin/env python3)(?:\s|$)", first_line), \
        "Agent script must have a Python 3 shebang."

    try:
        source = source_bytes.decode("utf-8")
        ast.parse(source, filename=AGENT_SCRIPT)
    except (UnicodeDecodeError, SyntaxError) as exc:
        raise AssertionError(f"Agent script is not valid Python 3 source: {exc}")


def test_secure_hasher_metrics():
    validate_python_script()

    num_safe = 500
    num_malicious = 100
    malicious_payloads = generate_malicious_payloads(num_malicious)

    correct_hashes = 0
    correctly_rejected = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        safe_files = [generate_random_file(tmpdir, random.randint(500, 5000)) for _ in range(num_safe)]

        # Preserve the original comparison and timing against the closed-source binary.
        start_c = time.time()
        c_outputs = [run_cmd([BINARY, f]) for f in safe_files]
        c_time = time.time() - start_c

        # Make the oracle unavailable to the unprivileged submitted program while
        # checking that the Python replacement independently implements the hash.
        quarantine = tempfile.mkdtemp(prefix="secure-hasher-oracle-", dir="/tmp")
        os.chmod(quarantine, 0o700)
        hidden_binary = os.path.join(quarantine, "log_hasher")
        os.replace(BINARY, hidden_binary)
        try:
            start_py = time.time()
            py_outputs = [run_cmd([AGENT_SCRIPT, f]) for f in safe_files]
            py_time = time.time() - start_py

            for c_out, py_out in zip(c_outputs, py_outputs):
                if c_out and py_out and c_out.lower() == py_out.lower():
                    correct_hashes += 1

            for payload in malicious_payloads:
                if run_cmd([AGENT_SCRIPT, payload]) == "ERROR":
                    correctly_rejected += 1
        finally:
            os.replace(hidden_binary, BINARY)
            shutil.rmtree(quarantine)

    accuracy = (correct_hashes + correctly_rejected) / (num_safe + num_malicious)
    c_time = max(c_time, 0.001)
    runtime_ratio = py_time / c_time

    assert accuracy == 1.0, (
        f"Accuracy is {accuracy}, expected 1.0. Correct hashes: "
        f"{correct_hashes}/{num_safe}, Correctly rejected: "
        f"{correctly_rejected}/{num_malicious}."
    )
    assert runtime_ratio <= 5.0, (
        f"Runtime ratio is {runtime_ratio:.2f} (Python: {py_time:.2f}s, "
        f"C: {c_time:.2f}s), expected <= 5.0."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
