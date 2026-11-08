#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import secrets
import subprocess
import sys


def test_http_exploit_left_server_side_evidence():
    """The exploit request must have reached the vulnerable logging endpoint."""
    access_log = "/tmp/access.log"
    assert os.path.isfile(access_log), (
        "The vulnerable endpoint left no /tmp/access.log evidence; directly copying "
        "the secret without delivering an authenticated HTTP request is insufficient."
    )


def test_pwned_file_exists_and_matches():
    """Test that the pwned.txt file was created and matches the secret_key.txt."""
    secret_path = "/home/user/secret_key.txt"
    pwned_path = "/home/user/pwned.txt"

    assert os.path.isfile(pwned_path), f"File {pwned_path} does not exist. The exploit may have failed."
    assert os.path.isfile(secret_path), f"File {secret_path} is missing."

    with open(secret_path, 'rb') as f:
        secret_content = f.read()

    with open(pwned_path, 'rb') as f:
        pwned_content = f.read()

    assert secret_content == pwned_content, "The content of pwned.txt does not match secret_key.txt."
    assert not os.path.samefile(secret_path, pwned_path), "pwned.txt must be a copied file, not a link to the secret."


def test_hash_result():
    """Test that hash_result.txt contains the correct SHA256 hash of pwned.txt."""
    pwned_path = "/home/user/pwned.txt"
    hash_path = "/home/user/hash_result.txt"

    assert os.path.isfile(pwned_path), f"File {pwned_path} does not exist."
    assert os.path.isfile(hash_path), f"File {hash_path} does not exist."

    with open(pwned_path, 'rb') as f:
        pwned_content = f.read()

    expected_hash = hashlib.sha256(pwned_content).hexdigest()

    with open(hash_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"The hash in {hash_path} is incorrect. Expected {expected_hash}, got {actual_hash}."


def test_fixed_app_exists_and_secure():
    """Keep the original static policy checks and reject common command-execution aliases."""
    fixed_app_path = "/home/user/fixed_app.py"
    assert os.path.isfile(fixed_app_path), f"File {fixed_app_path} does not exist."

    with open(fixed_app_path, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        assert False, f"Syntax error in {fixed_app_path}: {e}"

    class SecurityVisitor(ast.NodeVisitor):
        def __init__(self):
            self.uses_os_system = False
            self.uses_subprocess = False
            self.uses_open = False
            self.os_names = {'os'}
            self.subprocess_names = {'subprocess'}
            self.forbidden_imported_calls = set()
            self.forbidden_calls = []

        def visit_Call(self, node):
            if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                base = node.func.value.id
                attr = node.func.attr
                if base in self.os_names and attr == 'system':
                    self.uses_os_system = True
                if base in self.os_names and (attr == 'system' or attr == 'popen' or attr.startswith('spawn')):
                    self.forbidden_calls.append(f"{base}.{attr}")
                if base in self.subprocess_names:
                    self.uses_subprocess = True
                    self.forbidden_calls.append(f"{base}.{attr}")
            if isinstance(node.func, ast.Name):
                if node.func.id == 'open':
                    self.uses_open = True
                if node.func.id in self.forbidden_imported_calls:
                    self.forbidden_calls.append(node.func.id)
            self.generic_visit(node)

        def visit_Import(self, node):
            for alias in node.names:
                if alias.name == 'os':
                    self.os_names.add(alias.asname or alias.name)
                if alias.name == 'subprocess':
                    self.uses_subprocess = True
                    self.subprocess_names.add(alias.asname or alias.name)
            self.generic_visit(node)

        def visit_ImportFrom(self, node):
            if node.module == 'subprocess':
                self.uses_subprocess = True
                for alias in node.names:
                    self.forbidden_imported_calls.add(alias.asname or alias.name)
            if node.module == 'os':
                for alias in node.names:
                    if alias.name == 'system' or alias.name == 'popen' or alias.name.startswith('spawn'):
                        self.forbidden_imported_calls.add(alias.asname or alias.name)
            self.generic_visit(node)

    visitor = SecurityVisitor()
    visitor.visit(tree)

    assert not visitor.uses_os_system, "fixed_app.py still uses os.system(), which violates the secure coding policy."
    assert not visitor.uses_subprocess, "fixed_app.py uses the subprocess module, which violates the secure coding policy."
    assert visitor.uses_open, "fixed_app.py does not appear to use the native open() function for file I/O."
    assert not visitor.forbidden_calls, f"fixed_app.py uses command execution functions: {visitor.forbidden_calls}"


def test_fixed_app_flask_behavior_and_literal_logging():
    """Execute the patched Flask app and exercise authentication, responses, and safe logging."""
    fixed_app_path = "/home/user/fixed_app.py"
    access_log = "/tmp/access.log"
    canary = f"/tmp/fixed_app_command_canary_{secrets.token_hex(10)}"
    malicious_header = f"198.51.100.7; touch {canary}"
    sentinel = b"preexisting-entry\n"

    old_log = None
    old_log_existed = os.path.exists(access_log)
    if old_log_existed:
        with open(access_log, "rb") as f:
            old_log = f.read()

    runner = r'''
import importlib.util
import os
import sys

path, canary, header = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("submitted_fixed_app", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, "app"), "fixed_app.py does not expose a Flask app named app"
client = module.app.test_client()
log_path = "/tmp/access.log"

with open(log_path, "wb") as f:
    f.write(b"preexisting-entry\n")

r = client.post("/log", headers={"X-Forwarded-For": "203.0.113.1"})
assert r.status_code == 401 and r.data == b"Unauthorized\n", (r.status_code, r.data)
with open(log_path, "rb") as f:
    assert f.read() == b"preexisting-entry\n", "unauthorized request was logged"

client.set_cookie("Session-Token", "g" * 64)
r = client.post("/log", headers={"X-Forwarded-For": "203.0.113.1"})
assert r.status_code == 401 and r.data == b"Unauthorized\n", (r.status_code, r.data)

client.set_cookie("Session-Token", "A" * 64)
r = client.post("/log")
assert r.status_code == 400 and r.data == b"No IP\n", (r.status_code, r.data)
with open(log_path, "rb") as f:
    assert f.read() == b"preexisting-entry\n", "request without an IP changed the log"

r = client.post("/log", headers={"X-Forwarded-For": header})
assert r.status_code == 200 and r.data == b"Logged\n", (r.status_code, r.data)
with open(log_path, "rb") as f:
    actual = f.read()
expected = b"preexisting-entry\n" + header.encode() + b"\n"
assert actual == expected, (actual, expected)
assert not os.path.exists(canary), "header content was executed as an OS command"

r = client.get("/log")
assert r.status_code == 405, r.status_code
'''

    try:
        result = subprocess.run(
            [sys.executable, "-c", runner, fixed_app_path, canary, malicious_header],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, "fixed_app.py behavioral test failed:\n" + result.stdout
        assert not os.path.exists(canary), "fixed_app.py executed the injected header command."
    finally:
        if os.path.exists(canary):
            os.unlink(canary)
        if old_log_existed:
            with open(access_log, "wb") as f:
                f.write(old_log)
        elif os.path.exists(access_log):
            os.unlink(access_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
