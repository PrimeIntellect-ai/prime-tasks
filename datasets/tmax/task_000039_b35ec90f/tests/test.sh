#!/bin/bash
set -e
mkdir -p /logs/verifier

oracle_path=/app/ref_auth_gen
original_mode=$(stat -c '%a' "$oracle_path")
restore_oracle_mode() {
    chmod "$original_mode" "$oracle_path" 2>/dev/null || true
}
trap restore_oracle_mode EXIT
# The verifier remains able to execute the oracle as root, but submitted code,
# which is run as the unprivileged user, cannot delegate to it.
chmod 700 "$oracle_path"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import pwd
import random
import string
import subprocess

PIN = "A1B2C3D4E5F6G7H8"
SALT = "SaltySecret99"
AGENT_PATH = "/home/user/auth_gen.py"
ORACLE_PATH = "/app/ref_auth_gen"
USER = pwd.getpwnam("user")


def drop_privileges():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def expected_output(username, password):
    if "../" in username or "..\\" in username:
        return '{"error": "invalid username"}'
    token = hashlib.sha256((PIN + username + password + SALT).encode()).hexdigest()
    return f'{{"username": "{username}", "token": "{token}"}}'


def run_agent(username, password):
    return subprocess.run(
        ["python3", AGENT_PATH, username, password],
        capture_output=True,
        text=True,
        preexec_fn=drop_privileges,
    )


def test_auth_gen_exists():
    assert os.path.isfile(AGENT_PATH), "/home/user/auth_gen.py does not exist."
    assert not os.path.islink(AGENT_PATH), "auth_gen.py must be a regular Python file."
    with open(AGENT_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submission must not be the reference executable."
    with open(AGENT_PATH, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=AGENT_PATH)

    forbidden_modules = {"subprocess", "ctypes"}
    forbidden_calls = {
        "system", "popen", "fork", "forkpty", "posix_spawn", "posix_spawnp",
        "spawnl", "spawnle", "spawnlp", "spawnlpe", "spawnv", "spawnve",
        "spawnvp", "spawnvpe", "execv", "execve", "execvp", "execvpe",
        "execl", "execle", "execlp", "execlpe",
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert not any(alias.name.split(".")[0] in forbidden_modules for alias in node.names), \
                "The solution may not delegate token generation to another process."
        elif isinstance(node, ast.ImportFrom):
            assert (node.module or "").split(".")[0] not in forbidden_modules, \
                "The solution may not delegate token generation to another process."
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr not in forbidden_calls, \
                "The solution may not delegate token generation to another process."


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program {ORACLE_PATH} missing."
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} missing."

    random.seed(42)

    for _ in range(1000):
        length_u = random.randint(1, 50)
        chars_u = string.ascii_letters + string.digits

        if random.random() < 0.2:
            traversal = random.choice(["../", "..\\"])
            u = "".join(random.choices(chars_u, k=max(1, length_u - len(traversal))))
            insert_pos = random.randint(0, len(u))
            username = u[:insert_pos] + traversal + u[insert_pos:]
        else:
            username = "".join(random.choices(chars_u, k=length_u))

        length_p = random.randint(8, 32)
        chars_p = string.ascii_letters + string.digits + string.punctuation
        password = "".join(random.choices(chars_p, k=length_p))

        oracle_res = subprocess.run([ORACLE_PATH, username, password], capture_output=True, text=True)
        agent_res = run_agent(username, password)

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()
        derived_out = expected_output(username, password)

        assert oracle_out == derived_out, "Reference output disagrees with independently derived output."
        assert agent_res.returncode == 0, f"Agent exited with status {agent_res.returncode}: {agent_res.stderr}"
        assert oracle_out == agent_out, (
            f"Output mismatch for username={username!r}, password={password!r}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
