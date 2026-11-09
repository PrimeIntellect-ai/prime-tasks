#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the original service so the verifier can replace it with an instrumented
# equivalent that records whether scanner.py actually uses path traversal.
pkill -f "python3 /home/user/server.py" 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import secrets
import stat
import subprocess
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer


def test_recovered_token():
    """Check that the token was successfully recovered via the vulnerability scan."""
    path = "/home/user/recovered_token.txt"
    assert os.path.isfile(path), f"File {path} is missing. The scanner script may not have saved the output correctly."

    with open(path, "r") as f:
        content = f.read()

    expected = "FLAG{traversal_identified_992}"
    assert content == expected, f"Content of {path} is incorrect. Expected '{expected}', got '{content}'."


def test_target_rsa_permissions():
    """Check that the exposed RSA key permissions were properly hardened."""
    path = "/home/user/target_rsa"
    assert os.path.isfile(path), f"File {path} is missing."

    st = os.stat(path)
    perms = oct(st.st_mode)[-3:]
    assert perms == "600", f"Permissions of {path} are insecure. Expected 600, got {perms}."


def test_ssh_config_harden():
    """Check that the SSH config snippet is correctly configured."""
    path = "/home/user/ssh_config_harden"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = f.readlines()

    in_target_server = False
    has_identity_file = False
    has_password_auth = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if "=" in line:
            key, val = [x.strip() for x in line.split("=", 1)]
        else:
            parts = line.split(None, 1)
            if len(parts) < 2:
                continue
            key, val = parts

        key_lower = key.lower()

        if key_lower == "host":
            if val == "target-server":
                in_target_server = True
            else:
                in_target_server = False
        elif in_target_server:
            if key_lower == "identityfile" and val == "/home/user/target_rsa":
                has_identity_file = True
            elif key_lower == "passwordauthentication" and val.lower() == "no":
                has_password_auth = True

    assert has_identity_file, "IdentityFile is not correctly set to /home/user/target_rsa for host target-server."
    assert has_password_auth, "PasswordAuthentication is not explicitly disabled (set to 'no') for host target-server."


def test_scanner_script_validity():
    """Check that the scanner script exists and contains valid Python syntax."""
    path = "/home/user/scanner.py"
    assert os.path.isfile(path), f"File {path} is missing. Did you write the scanner script?"

    with open(path, "r") as f:
        content = f.read()

    try:
        ast.parse(content)
    except SyntaxError as e:
        assert False, f"The script {path} contains invalid Python syntax: {e}"


def test_scanner_executes_path_traversal_request():
    """Execute scanner.py and verify it retrieves an unpredictable token via traversal."""
    scanner_path = "/home/user/scanner.py"
    recovered_path = "/home/user/recovered_token.txt"
    secret_path = "/home/user/secret_token.txt"
    expected = f"FLAG{{dynamic_{secrets.token_hex(16)}}}".encode()
    observed_traversals = []

    # Prevent scanner.py, which is run as the unprivileged user, from obtaining
    # the new value by directly opening the local secret file.
    with open(secret_path, "wb") as f:
        f.write(expected)
    os.chown(secret_path, 0, 0)
    os.chmod(secret_path, 0o600)
    if os.path.exists(recovered_path):
        os.remove(recovered_path)

    class InstrumentedHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path != "/download":
                self.send_response(404)
                self.end_headers()
                return

            query = urllib.parse.parse_qs(parsed.query)
            if "file" not in query:
                self.send_response(400)
                self.end_headers()
                return

            supplied = urllib.parse.unquote(query["file"][0])
            normalized = os.path.normpath("/" + supplied.lstrip("/"))
            has_traversal = ".." in supplied.replace("\\", "/").split("/")
            if has_traversal and normalized == secret_path:
                observed_traversals.append(supplied)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(expected)
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"Not found")

        def log_message(self, format, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(("127.0.0.1", 8080), InstrumentedHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    account = pwd.getpwnam("user")

    def become_user():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        result = subprocess.run(
            ["python3", scanner_path],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            preexec_fn=become_user,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert result.returncode == 0, (
        f"scanner.py exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert observed_traversals, "scanner.py did not request secret_token.txt using a path traversal payload."
    assert expected in result.stdout, "scanner.py did not output the retrieved file content."
    assert os.path.isfile(recovered_path), "scanner.py did not create recovered_token.txt when executed."
    with open(recovered_path, "rb") as f:
        recovered = f.read()
    assert recovered == expected, "scanner.py did not save the HTTP response exactly as received."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
