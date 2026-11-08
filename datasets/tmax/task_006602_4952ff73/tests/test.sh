#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_CURL=/usr/bin/curl.verifier-real
rm -f "$REAL_CURL"
mv /usr/bin/curl "$REAL_CURL"
cat <<'CURL_EOF' > /usr/bin/curl
#!/bin/bash
exec /usr/bin/curl.verifier-real "$@" -H "X-Verifier-Curl: ${VERIFIER_CURL_NONCE:-}"
CURL_EOF
chmod 755 /usr/bin/curl

restore_curl() {
    rm -f /usr/bin/curl
    if [ -f "$REAL_CURL" ]; then
        mv "$REAL_CURL" /usr/bin/curl
    fi
}
trap restore_curl EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def test_cwes_identified():
    """Test that exactly three valid CWE IDs are identified, one per line."""
    cwes_file = "/home/user/cwes.txt"
    assert os.path.isfile(cwes_file), f"Missing file: {cwes_file}"

    with open(cwes_file, "r") as f:
        content = f.read().upper()

    # Preserve the original category assertions.
    assert "CWE-798" in content, "cwes.txt is missing CWE-798 (hardcoded credentials)"
    bypass_cwes = ["CWE-288", "CWE-287", "CWE-807"]
    assert any(cwe in content for cwe in bypass_cwes), f"cwes.txt is missing an auth bypass CWE (expected one of {bypass_cwes})"
    sensitive_cwes = ["CWE-532", "CWE-312"]
    assert any(cwe in content for cwe in sensitive_cwes), f"cwes.txt is missing a sensitive info CWE (expected one of {sensitive_cwes})"

    lines = content.splitlines()
    assert len(lines) == 3, f"cwes.txt must contain exactly three lines, found {len(lines)}"
    assert all(re.fullmatch(r"CWE-[1-9][0-9]*", line) for line in lines), "Each line must contain exactly one valid CWE ID"
    assert len(set(lines)) == 3, "The three CWE IDs must be distinct"
    assert "CWE-798" in lines
    assert sum(cwe in bypass_cwes for cwe in lines) == 1
    assert sum(cwe in sensitive_cwes for cwe in lines) == 1


def run_exploit(expected, env=None):
    result = subprocess.run(
        ["/home/user/exploit.sh"],
        capture_output=True,
        text=True,
        timeout=8,
        env=env,
    )
    assert result.returncode == 0, f"exploit.sh failed: {result.stderr}"
    output = result.stdout.strip()
    assert expected in output, f"Exploit script did not output the correct secret token. Output was: {output}"
    assert output == expected, f"exploit.sh must print ONLY the secret token; output was: {output!r}"


def test_exploit_script_execution():
    exploit_script = "/home/user/exploit.sh"
    server_script = "/home/user/server.py"
    assert os.path.isfile(exploit_script), f"Missing file: {exploit_script}"
    assert os.access(exploit_script, os.X_OK), f"{exploit_script} is not executable"

    # Preserve the original check against the supplied service.
    server_process = subprocess.Popen(
        ["python3", server_script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    try:
        assert server_process.poll() is None, "The supplied server failed to start on port 8080"
        run_exploit("FLG_77b31_s3cr3t", os.environ.copy())
    finally:
        server_process.terminate()
        try:
            server_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server_process.kill()
            server_process.wait()

    # Exercise the exploit against an unpredictable token. The instrumented curl
    # adds a nonce header, so the successful request must actually be made by curl.
    token = "FLG_" + secrets.token_hex(18)
    curl_nonce = secrets.token_hex(18)
    valid_requests = []

    class ChallengeHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(length)
            valid = (
                self.path == "/login"
                and self.headers.get("X-Admin-Bypass") == "true"
                and self.headers.get("X-Verifier-Curl") == curl_nonce
            )
            if valid:
                valid_requests.append(True)
                body = ('{"status":"success","secret_token":"%s"}' % token).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 8080), ChallengeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = os.environ.copy()
        env["VERIFIER_CURL_NONCE"] = curl_nonce
        run_exploit(token, env)
        assert valid_requests, "exploit.sh did not use curl to contact /login with the bypass header"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


SSN_RE = re.compile(r"(?<![0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9])")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def expected_redaction(text):
    return EMAIL_RE.sub("[REDACTED_EMAIL]", SSN_RE.sub("[REDACTED_SSN]", text))


def execute_redactor(path):
    result = subprocess.run(
        ["/home/user/redact.sh", path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"redact.sh failed for {path}: {result.stderr}"
    return result.stdout


def test_redact_script_and_clean_log():
    redact_script = "/home/user/redact.sh"
    app_log = "/home/user/app.log"
    clean_log = "/home/user/clean.log"
    assert os.path.isfile(redact_script), f"Missing file: {redact_script}"
    assert os.access(redact_script, os.X_OK), f"{redact_script} is not executable"
    assert os.path.isfile(clean_log), f"Missing file: {clean_log}"

    with open(app_log, "r") as f:
        original = f.read()
    produced = execute_redactor(app_log)
    with open(clean_log, "r") as f:
        content = f.read()

    assert produced == expected_redaction(original), "redact.sh did not correctly redact the supplied app.log"
    assert content == produced, "clean.log is not the output produced by running redact.sh on app.log"

    # Preserve the original clean.log assertions.
    assert "123-45-6789" not in content, "clean.log still contains an unredacted SSN"
    assert "987-65-4321" not in content, "clean.log still contains an unredacted SSN"
    assert "[REDACTED_SSN]" in content, "clean.log is missing the [REDACTED_SSN] string"
    assert "alice.smith@example.com" not in content, "clean.log still contains an unredacted email"
    assert "bob_jones@domain.co.uk" not in content, "clean.log still contains an unredacted email"
    assert "charlie+test@sub.domain.org" not in content, "clean.log still contains an unredacted email"
    assert "[REDACTED_EMAIL]" in content, "clean.log is missing the [REDACTED_EMAIL] string"
    assert "User registered: Alice Smith" in content, "clean.log is missing original non-sensitive log text"
    assert "Failed login attempt for" in content, "clean.log is missing original non-sensitive log text"
    assert "Payment processed for Charlie" in content, "clean.log is missing original non-sensitive log text"

    generated = (
        "first=001-02-0003 mail=a+b@example.io second=444-55-6666\n"
        "Keep this text; contact user_name@deep.sub-domain.example.org.\n"
        "Adjacent (999-88-7777), repeated x@y.co and x@y.co\n"
        "Not matches: 1234-56-7890 and plain@localhost\n"
    )
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(generated)
        generated_path = f.name
    try:
        actual = execute_redactor(generated_path)
        assert actual == expected_redaction(generated), "redact.sh failed on independently generated sensitive data"
    finally:
        os.unlink(generated_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
