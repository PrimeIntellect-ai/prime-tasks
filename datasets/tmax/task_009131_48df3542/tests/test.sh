#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.server
import json
import os
import re
import secrets
import socketserver
import stat
import subprocess
import threading

ORIGINAL_AUDIT = b'''[INFO] 2023-10-01T12:00:00Z - Request to /login with username=admin&password=SuperSecretPassword123 from 192.168.1.10
[INFO] 2023-10-01T12:05:00Z - API call to /secure/data header: Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciJ9.signature123
[ERROR] 2023-10-01T12:10:00Z - Failed login attempt username=test&password=WrongPassword!
[INFO] 2023-10-01T12:15:00Z - API call to /secure/data header: Authorization: Bearer eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYWRtaW4ifQ.
'''


def require_regular_file(path):
    assert os.path.exists(path), f"The required file {path} does not exist."
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular file."


def decode_segment(segment):
    padding = "=" * ((4 - len(segment) % 4) % 4)
    return json.loads(base64.urlsafe_b64decode(segment + padding).decode("utf-8"))


def test_exploit_program_retrieves_exact_dynamic_response():
    exploit_path = "/home/user/exploit.go"
    key_path = "/home/user/stolen_key.pem"
    require_regular_file(exploit_path)

    random_body = secrets.token_urlsafe(48).encode("ascii")
    expected_key = (
        b"-----BEGIN OPENSSH PRIVATE KEY-----\n"
        + random_body
        + b"\n-----END OPENSSH PRIVATE KEY-----"
    )
    observed = {"valid": False}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/secure/key":
                self.send_error(404)
                return

            auth = self.headers.get("Authorization", "")
            valid = False
            if auth.startswith("Bearer "):
                token = auth[len("Bearer "):]
                parts = token.split(".")
                if len(parts) in (2, 3):
                    try:
                        header = decode_segment(parts[0])
                        payload = decode_segment(parts[1])
                        valid = header.get("alg") == "none" and payload.get("role") == "admin"
                    except Exception:
                        valid = False

            if not valid:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden\n")
                return

            observed["valid"] = True
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(expected_key)))
            self.end_headers()
            self.wfile.write(expected_key)

        def log_message(self, fmt, *args):
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    try:
        server = ReusableTCPServer(("127.0.0.1", 8080), Handler)
    except OSError as exc:
        raise AssertionError(f"Could not start verifier service on port 8080: {exc}")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.lexists(key_path):
            os.remove(key_path)
        result = subprocess.run(
            ["go", "run", exploit_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            text=True,
        )
        assert result.returncode == 0, (
            f"Running {exploit_path} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert observed["valid"], "The exploit did not send a forged alg=none admin JWT to /secure/key."
    assert os.path.exists(key_path), f"The file {key_path} does not exist. Did the exploit run successfully?"
    with open(key_path, "rb") as f:
        content = f.read()

    assert b"BEGIN OPENSSH PRIVATE KEY" in content, (
        f"The file {key_path} does not contain a valid OpenSSH private key. "
        "Ensure your exploit correctly bypassed the JWT validation and saved the exact response body."
    )
    assert content == expected_key, "stolen_key.pem is not the raw, exact response body returned to the exploit."


def test_redactor_program_on_dynamic_audit_log():
    redact_path = "/home/user/redact.go"
    original_log_path = "/home/user/audit.log"
    clean_log_path = "/home/user/audit_clean.log"
    require_regular_file(redact_path)
    assert os.path.exists(original_log_path), f"The original log file {original_log_path} is missing."

    with open(original_log_path, "rb") as f:
        saved_original = f.read()
    assert saved_original == ORIGINAL_AUDIT, "The original /home/user/audit.log was modified."

    password1 = "pw" + secrets.token_hex(12)
    password2 = "other" + secrets.token_hex(9)
    token1 = "ey." + secrets.token_urlsafe(25) + ".sig"
    token2 = secrets.token_urlsafe(31)
    dynamic_log = (
        f"[INFO] path=/login?password={password1}&next=/home user=alpha\n"
        f"[INFO] Authorization: Bearer {token1} request=one\n"
        f"[WARN] password={password2} Bearer {token2}\n"
        "[INFO] ordinary line without secrets\n"
    )

    try:
        with open(original_log_path, "w", encoding="utf-8", newline="") as f:
            f.write(dynamic_log)
        if os.path.lexists(clean_log_path):
            os.remove(clean_log_path)

        result = subprocess.run(
            ["go", "run", redact_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            text=True,
        )
        assert result.returncode == 0, (
            f"Running {redact_path} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.exists(clean_log_path), f"The redacted log file {clean_log_path} is missing."
        with open(original_log_path, "r", encoding="utf-8", newline="") as f:
            original_lines = f.readlines()
        with open(clean_log_path, "r", encoding="utf-8", newline="") as f:
            clean_lines = f.readlines()

        assert len(original_lines) == len(clean_lines), (
            f"The redacted log has {len(clean_lines)} lines, but the original has {len(original_lines)}. "
            "Lines should not be added or removed."
        )

        expected_lines = []
        for i, (orig, clean) in enumerate(zip(original_lines, clean_lines)):
            expected = re.sub(r'(Bearer\s+)[^\s]+', r'\g<1>[REDACTED]', orig)
            expected = re.sub(r'(password=)[^\s&]+', r'\g<1>[REDACTED]', expected)
            expected_lines.append(expected)
            assert clean.strip() == expected.strip(), (
                f"Line {i+1} in {clean_log_path} was not redacted correctly.\n"
                f"Expected: {expected.strip()}\nFound:    {clean.strip()}"
            )

        assert "".join(clean_lines) == "".join(expected_lines), (
            "audit_clean.log must preserve all content exactly except for the required redactions."
        )
    finally:
        with open(original_log_path, "wb") as f:
            f.write(saved_original)


def test_sshd_config_policy():
    policy_path = "/home/user/sshd_config.policy"
    assert os.path.exists(policy_path), f"The SSH policy file {policy_path} is missing."

    with open(policy_path, "r") as f:
        content = f.read().lower()

    raw_lines = content.splitlines()
    assert len(raw_lines) == 3, f"The SSH policy must contain exactly three lines, found {len(raw_lines)}."
    lines = [line.strip() for line in raw_lines if line.strip()]

    required_directives = {
        "permitrootlogin no",
        "passwordauthentication no",
        "x11forwarding no",
    }

    found_directives = set()
    for line in lines:
        normalized_line = re.sub(r'\s+', ' ', line)
        if normalized_line in required_directives:
            found_directives.add(normalized_line)

    missing = required_directives - found_directives
    assert not missing, (
        f"The SSH policy file {policy_path} is missing or has incorrect values for the following directives: "
        f"{', '.join(missing)}"
    )
    assert len(lines) == 3 and {re.sub(r'\s+', ' ', line) for line in lines} == required_directives, (
        "The SSH policy must contain only the three required directives, one per line."
    )
TEST_EOF

# Stop a development server the agent may have left running so the verifier can
# provide its own unpredictable service response.
pkill -f '/tmp/go-build.*/exe/server' 2>/dev/null || true
pkill -f 'go run /home/user/server.go' 2>/dev/null || true
sleep 1

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
