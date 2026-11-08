#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

SCAN = "/home/user/scan.sh"
NGINX_CONF = "/home/user/app/nginx/nginx.conf"
SSH_CONFIG = "/home/user/app/ssh/sshd_config"
KEY_PATH = "/home/user/app/ssh/ssh_host_ed25519_key"


def canonical(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def assert_scanner_topics(text, source):
    value = canonical(text)
    assert "xframeoptions" in value, f"{source} does not report on X-Frame-Options."
    assert "xcontenttypeoptions" in value, f"{source} does not report on X-Content-Type-Options."
    assert "secure" in value, f"{source} does not report on the Secure cookie flag."
    assert "httponly" in value, f"{source} does not report on the HttpOnly cookie flag."
    key_named = "sshhosted25519key" in value or "hostkey" in value
    permission_named = any(word in value for word in ("permission", "mode", "readable", "permissive"))
    assert key_named and permission_named, f"{source} does not report the SSH host-key permission finding."


def run_scanner():
    result = subprocess.run([SCAN], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Scanner exited with {result.returncode}: {result.stderr}"
    assert result.stdout.strip(), "Scanner produced no findings."
    return result.stdout


def test_http_headers_and_cookies():
    for _ in range(10):
        try:
            resp = requests.get("http://127.0.0.1:8080/", timeout=2)
            break
        except requests.RequestException:
            time.sleep(1)
    else:
        assert False, "Nginx service on port 8080 is not reachable."

    headers = {k.lower(): v for k, v in resp.headers.items()}
    assert "x-frame-options" in headers, "X-Frame-Options header is missing."
    assert headers["x-frame-options"].upper() == "DENY", \
        f"X-Frame-Options is {headers['x-frame-options']}, expected DENY."
    assert "x-content-type-options" in headers, "X-Content-Type-Options header is missing."
    assert headers["x-content-type-options"].lower() == "nosniff", \
        f"X-Content-Type-Options is {headers['x-content-type-options']}, expected nosniff."
    assert "set-cookie" in headers, "Set-Cookie header is missing."
    cookie_val = headers["set-cookie"].lower()
    assert "secure" in cookie_val, "Set-Cookie does not contain the Secure flag."
    assert "httponly" in cookie_val, "Set-Cookie does not contain the HttpOnly flag."


def test_ssh_password_auth_rejected():
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "BatchMode=yes",
        "-o", "PreferredAuthentications=password",
        "-o", "ConnectTimeout=3",
        "-p", "2222", "user@127.0.0.1"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, "SSH connection with password authentication succeeded."
    assert ("Permission denied" in result.stderr or "Connection closed" in result.stderr
            or "publickey" in result.stderr), \
        f"Expected password authentication to be rejected, got: {result.stderr}"


def effective_sshd_config():
    result = subprocess.run(
        ["/usr/sbin/sshd", "-T", "-f", SSH_CONFIG,
         "-C", "user=user,host=localhost,addr=127.0.0.1"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"sshd_config is invalid: {result.stderr}"
    values = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            values[parts[0].lower()] = parts[1].strip()
    return values


def test_ssh_effective_authentication_settings():
    values = effective_sshd_config()
    assert values.get("passwordauthentication") == "no", \
        "Effective PasswordAuthentication setting is not 'no'."
    assert values.get("permitemptypasswords") == "no", \
        "Effective PermitEmptyPasswords setting is not 'no'."


def test_ssh_ciphers_restricted():
    allowed_ciphers = {
        "chacha20-poly1305@openssh.com",
        "aes256-gcm@openssh.com",
    }

    values = effective_sshd_config()
    configured = {c.strip() for c in values.get("ciphers", "").split(",") if c.strip()}
    assert configured == allowed_ciphers, \
        f"Effective SSH ciphers are {sorted(configured)}, expected exactly {sorted(allowed_ciphers)}."

    cmd = ["nmap", "--script", "ssh2-enum-algos", "-p", "2222", "127.0.0.1"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except FileNotFoundError:
        with open(SSH_CONFIG) as f:
            config = f.read()
        ciphers_line = re.search(r"^\s*Ciphers\s+(.+)$", config, re.MULTILINE | re.IGNORECASE)
        assert ciphers_line, "Ciphers directive not found in sshd_config."
        ciphers = {c.strip() for c in ciphers_line.group(1).split(",") if c.strip()}
        assert ciphers == allowed_ciphers, \
            f"Configured ciphers are {sorted(ciphers)}, expected exactly {sorted(allowed_ciphers)}."
        return

    output = result.stdout
    if "ssh2-enum-algos" in output:
        section = re.search(r"encryption_algorithms:(.*?)mac_algorithms:", output, re.DOTALL)
        if section:
            ciphers = set(re.findall(r"\s+([a-zA-Z0-9\-@.]+)", section.group(1)))
            assert ciphers == allowed_ciphers, \
                f"Live SSH server ciphers are {sorted(ciphers)}, expected exactly {sorted(allowed_ciphers)}."


def test_system_state_and_reports():
    assert os.path.exists(KEY_PATH), f"{KEY_PATH} does not exist."
    mode = stat.S_IMODE(os.stat(KEY_PATH).st_mode)
    assert mode == 0o600, f"Permissions of {KEY_PATH} are {oct(mode)}, expected 0600."

    assert os.path.isfile(SCAN), f"{SCAN} does not exist."
    assert os.access(SCAN, os.X_OK), f"{SCAN} is not executable."
    with open(SCAN, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, \
        f"{SCAN} is not a Bash script."
    syntax = subprocess.run(["bash", "-n", SCAN], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Scanner has invalid Bash syntax: {syntax.stderr}"

    pre_path = "/home/user/pre_report.txt"
    post_path = "/home/user/post_report.txt"
    assert os.path.isfile(pre_path), f"{pre_path} does not exist."
    assert os.path.isfile(post_path), f"{post_path} does not exist."
    pre = open(pre_path).read()
    post = open(post_path).read()
    assert pre.strip(), "pre_report.txt is empty."
    assert post.strip(), "post_report.txt is empty."
    assert pre.strip() != post.strip(), "Pre- and post-remediation reports are identical."
    assert_scanner_topics(pre, "pre_report.txt")
    assert_scanner_topics(post, "post_report.txt")

    current = run_scanner()
    assert_scanner_topics(current, "scanner output")
    assert current.strip() == post.strip(), \
        "post_report.txt is not the output currently produced by scan.sh."


class ControlledHandler(BaseHTTPRequestHandler):
    state = {}

    def do_GET(self):
        self.send_response_only(200)
        if self.state.get("frame"):
            self.send_header("X-Frame-Options", "DENY")
        if self.state.get("ctype"):
            self.send_header("X-Content-Type-Options", "nosniff")
        cookie = "session=controlled"
        if self.state.get("secure"):
            cookie += "; Secure"
        if self.state.get("httponly"):
            cookie += "; HttpOnly"
        self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, fmt, *args):
        pass


def test_scanner_actually_checks_each_condition():
    stop = subprocess.run(["nginx", "-c", NGINX_CONF, "-s", "stop"],
                          capture_output=True, text=True)
    server = None
    try:
        for _ in range(30):
            try:
                server = HTTPServer(("127.0.0.1", 8080), ControlledHandler)
                break
            except OSError:
                time.sleep(0.1)
        assert server is not None, f"Could not replace Nginx with controlled test server: {stop.stderr}"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def scan(state, mode=0o600):
            ControlledHandler.state = state
            os.chmod(KEY_PATH, mode)
            output = run_scanner()
            assert_scanner_topics(output, "scanner output")
            return output

        full = {"frame": True, "ctype": True, "secure": True, "httponly": True}
        good = scan(full)
        no_frame = scan({**full, "frame": False})
        no_ctype = scan({**full, "ctype": False})
        no_secure = scan({**full, "secure": False})
        no_httponly = scan({**full, "httponly": False})
        bad_mode = scan(full, 0o644)

        assert good != no_frame, "Scanner output does not react to a missing X-Frame-Options header."
        assert good != no_ctype, "Scanner output does not react to a missing X-Content-Type-Options header."
        assert good != no_secure, "Scanner output does not react to a missing Secure cookie flag."
        assert good != no_httponly, "Scanner output does not react to a missing HttpOnly cookie flag."
        assert good != bad_mode, "Scanner output does not react to overly permissive host-key permissions."
    finally:
        os.chmod(KEY_PATH, 0o600)
        if server is not None:
            server.shutdown()
            server.server_close()
        start = subprocess.run(["nginx", "-c", NGINX_CONF], capture_output=True, text=True)
        assert start.returncode == 0, f"Failed to restore Nginx after scanner tests: {start.stderr}"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
