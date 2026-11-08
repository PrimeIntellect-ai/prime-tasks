#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import hmac
import stat
import hashlib
import secrets
import random
import signal
import subprocess
import tempfile


def get_expected_token():
    key = b"supersecret"
    msg = b"admin_access"
    return hmac.new(key, msg, hashlib.sha256).hexdigest()


def test_admin_token_file():
    token_path = "/home/user/admin_token.txt"
    assert os.path.exists(token_path), f"File {token_path} is missing."
    assert os.path.isfile(token_path), f"{token_path} should be a file."

    with open(token_path, "r") as f:
        content = f.read().strip()

    expected_token = get_expected_token()
    assert content == expected_token, f"Expected token {expected_token}, but got {content} in {token_path}."


def test_policy_conf_updated():
    policy_path = "/home/user/policy.conf"
    assert os.path.exists(policy_path), f"File {policy_path} is missing."

    with open(policy_path, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 2, f"{policy_path} should have at least 2 lines."

    first_line = lines[0].strip()
    expected_token = get_expected_token()
    expected_first_line = f"ALLOW ADMIN {expected_token}"

    assert first_line == expected_first_line, f"Expected first line of {policy_path} to be '{expected_first_line}', but got '{first_line}'."
    assert lines[1].strip() == "ALLOW USER 1234", f"Expected second line of {policy_path} to remain 'ALLOW USER 1234'."


def _script_candidates():
    candidates = []
    for root in ("/home/user", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "__pycache__"}]
            for name in files:
                path = os.path.join(directory, name)
                if path == "/tmp/test_final_state.py" or os.path.islink(path):
                    continue
                try:
                    if not stat.S_ISREG(os.stat(path).st_mode) or os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        raw = f.read()
                    text = raw.decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                first = text.splitlines()[0] if text.splitlines() else ""
                if name.endswith(".sh") or re.match(r"^#!.*\b(bash|sh)\b", first):
                    candidates.append((path, text))
    return candidates


def _snapshot(path):
    if not os.path.lexists(path):
        return None
    st = os.stat(path)
    with open(path, "rb") as f:
        return (f.read(), stat.S_IMODE(st.st_mode))


def _restore(path, snapshot):
    try:
        if os.path.lexists(path):
            os.unlink(path)
    except IsADirectoryError:
        return
    if snapshot is not None:
        data, mode = snapshot
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, mode)


def _run_script(path):
    proc = subprocess.Popen(
        ["/bin/bash", path],
        cwd=os.path.dirname(path) or "/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
    )
    try:
        out, err = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, err = proc.communicate()
        return -1, out + b"\n" + err
    return proc.returncode, out + b"\n" + err


def test_bash_cracking_script_extracts_and_cracks_dynamic_inputs():
    candidates = _script_candidates()
    assert candidates, "No Bash cracking script was written."

    plausible = []
    for path, source in candidates:
        lower = source.lower()
        if ("auth_binary" in source and "wordlist.txt" in source and
                "hash" in lower and "salt" in lower and
                re.search(r"sha-?256|sha256sum|hashlib", lower)):
            plausible.append((path, source))
    assert plausible, "No Bash script references the binary, wordlist, HASH/SALT data, and SHA-256 cracking operation."

    tracked = [
        "/home/user/auth_binary",
        "/home/user/wordlist.txt",
        "/home/user/policy.conf",
        "/home/user/admin_token.txt",
    ]
    original = {path: _snapshot(path) for path in tracked}

    secret = "pw" + secrets.token_hex(10)
    salt = "salt" + secrets.token_hex(8)
    digest = hashlib.sha256((secret + salt).encode()).hexdigest()
    expected_token = hmac.new(secret.encode(), b"admin_access", hashlib.sha256).hexdigest()
    words = ["wrong" + secrets.token_hex(5) for _ in range(6)]
    words.insert(random.randrange(len(words) + 1), secret)

    with tempfile.TemporaryDirectory() as td:
        source_path = os.path.join(td, "auth.c")
        binary_path = os.path.join(td, "auth_binary")
        with open(source_path, "w") as f:
            f.write(
                '#include <stdio.h>\n'
                'int main(void) {\n'
                f'  const char *hash = "HASH:{digest}";\n'
                f'  const char *salt = "SALT:{salt}";\n'
                '  puts("Auth service loaded.");\n'
                '  return hash[0] == salt[0];\n'
                '}\n'
            )
        subprocess.run(["gcc", "-o", binary_path, source_path], check=True)
        with open(binary_path, "rb") as f:
            dynamic_binary = f.read()

        passed = False
        diagnostics = []
        try:
            for script_path, _ in plausible:
                for path in tracked:
                    _restore(path, original[path])
                with open("/home/user/auth_binary", "wb") as f:
                    f.write(dynamic_binary)
                os.chmod("/home/user/auth_binary", 0o755)
                with open("/home/user/wordlist.txt", "w") as f:
                    f.write("\n".join(words) + "\n")

                code, output_bytes = _run_script(script_path)
                output = output_bytes.decode("utf-8", errors="replace")
                observable = False

                stripped_lines = [line.strip() for line in output.splitlines()]
                if output.strip() == secret:
                    observable = True
                if any(secret in line and re.search(r"found|cracked|success|correct", line, re.I)
                       for line in stripped_lines):
                    observable = True
                if expected_token in output:
                    observable = True

                try:
                    with open("/home/user/admin_token.txt", "r") as f:
                        if f.read().strip() == expected_token:
                            observable = True
                except OSError:
                    pass
                try:
                    with open("/home/user/policy.conf", "r") as f:
                        if f.readline().strip() == f"ALLOW ADMIN {expected_token}":
                            observable = True
                except OSError:
                    pass

                if code == 0 and observable:
                    passed = True
                    break
                diagnostics.append(f"{script_path}: exit={code}, output={output[:300]!r}")
        finally:
            for path in tracked:
                _restore(path, original[path])

    assert passed, "No submitted Bash script extracted and cracked a verifier-generated binary/wordlist case. " + "; ".join(diagnostics)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
