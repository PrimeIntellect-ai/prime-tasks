#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import re
import secrets
import shlex
import subprocess
import tempfile

INCIDENT_DIR = "/home/user/incident"
AUTH_SERVER_SOURCE = os.path.join(INCIDENT_DIR, "auth_server.c")
AUTH_SERVER_BIN = os.path.join(INCIDENT_DIR, "auth_server")
CERT_FILE = os.path.join(INCIDENT_DIR, "cert.pem")
KEY_FILE = os.path.join(INCIDENT_DIR, "key.pem")
SSHD_CONFIG = os.path.join(INCIDENT_DIR, "sshd_config")
TEST_SH = os.path.join(INCIDENT_DIR, "test.sh")
TEST_OUTPUT = os.path.join(INCIDENT_DIR, "test_output.log")
CSP = b"Content-Security-Policy: default-src 'self';"


def run_server(binary, argument):
    result = subprocess.run(
        [binary, argument], capture_output=True, timeout=5
    )
    assert result.returncode == 0, f"auth_server failed for {argument!r}: {result.stderr!r}"
    return result.stdout


def assert_response(binary, target, expected_location):
    raw = run_server(binary, "redirect_to=" + target)
    assert b"\r\n\r\n" in raw, "HTTP headers are not terminated by a CRLF blank line"
    header, _ = raw.split(b"\r\n\r\n", 1)
    lines = header.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 302 Found", "Missing HTTP 302 status line"
    assert lines.count(b"Location: " + expected_location.encode()) == 1, "Incorrect Location header"
    assert lines.count(CSP) == 1, "The exact CSP header must occur once on its own line"
    return raw


def exercise_auth_server(binary):
    # Retain the original fixed behavioral assertions.
    out1 = run_server(binary, "redirect_to=http://evil.com")
    assert b"Location: /error\r\n" in out1, "auth_server did not redirect http://evil.com to /error"
    assert b"Content-Security-Policy: default-src 'self';\r\n" in out1, "auth_server did not include the correct CSP header"

    out2 = run_server(binary, "redirect_to=//evil.com")
    assert b"Location: /error\r\n" in out2, "auth_server did not redirect //evil.com to /error"

    out3 = run_server(binary, "redirect_to=/dashboard")
    assert b"Location: /dashboard\r\n" in out3, "auth_server did not redirect /dashboard to /dashboard"
    assert b"Content-Security-Policy: default-src 'self';\r\n" in out3, "auth_server did not include the correct CSP header"

    assert_response(binary, "http://evil.com", "/error")
    assert_response(binary, "//evil.com", "/error")
    assert_response(binary, "/dashboard", "/dashboard")

    # Unpredictable targets prevent a fixed-response executable from passing.
    token = secrets.token_hex(12)
    cases = [
        (f"http://{token}.example/path", "/error"),
        (f"https://{token}.example/login", "/error"),
        (f"//{token}.example/continue", "/error"),
        (f"/{token}/dashboard", f"/{token}/dashboard"),
        (f"relative-{token}", f"relative-{token}"),
        (f"ftp://{token}.example/file", f"ftp://{token}.example/file"),
    ]
    for target, expected in cases:
        assert_response(binary, target, expected)


def test_auth_server_compiled_and_patched():
    assert os.path.isfile(AUTH_SERVER_SOURCE), f"{AUTH_SERVER_SOURCE} is missing."
    assert os.path.isfile(AUTH_SERVER_BIN), f"{AUTH_SERVER_BIN} is missing. Did you compile the C code?"
    assert os.access(AUTH_SERVER_BIN, os.X_OK), f"{AUTH_SERVER_BIN} is not executable."
    with open(AUTH_SERVER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "auth_server is not a compiled ELF executable"

    exercise_auth_server(AUTH_SERVER_BIN)

    # Compile the submitted C source independently and exercise that artifact too.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "auth_server")
        build = subprocess.run(
            ["gcc", "-std=c11", AUTH_SERVER_SOURCE, "-o", rebuilt],
            capture_output=True, text=True, timeout=20
        )
        assert build.returncode == 0, f"auth_server.c does not compile with gcc: {build.stderr}"
        exercise_auth_server(rebuilt)


def openssl(*args, input_data=None):
    return subprocess.run(
        ["openssl", *args], input=input_data, capture_output=True, timeout=10
    )


def test_tls_certificate():
    assert os.path.isfile(CERT_FILE), f"{CERT_FILE} is missing."
    assert os.path.isfile(KEY_FILE), f"{KEY_FILE} is missing."

    key_check = openssl("rsa", "-in", KEY_FILE, "-check", "-noout")
    assert key_check.returncode == 0, "Private key is invalid or requires a passphrase."

    cert_text = openssl("x509", "-in", CERT_FILE, "-text", "-noout")
    assert cert_text.returncode == 0, "Certificate is invalid."
    out = cert_text.stdout.decode(errors="replace")
    assert "CN = localhost" in out or "CN=localhost" in out, "Certificate Common Name is not localhost."
    assert "Public-Key: (2048 bit)" in out, "Certificate is not RSA 2048-bit."

    subject_result = openssl("x509", "-in", CERT_FILE, "-noout", "-subject", "-nameopt", "RFC2253")
    issuer_result = openssl("x509", "-in", CERT_FILE, "-noout", "-issuer", "-nameopt", "RFC2253")
    assert subject_result.returncode == 0 and issuer_result.returncode == 0
    subject = subject_result.stdout.decode().strip().split("=", 1)[1]
    issuer = issuer_result.stdout.decode().strip().split("=", 1)[1]
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject), "Certificate subject CN is not localhost."
    assert subject == issuer, "Certificate is not self-issued."

    verify = openssl("verify", "-CAfile", CERT_FILE, CERT_FILE)
    assert verify.returncode == 0, "Certificate is not a valid self-signed certificate."

    cert_pub = openssl("x509", "-in", CERT_FILE, "-pubkey", "-noout")
    assert cert_pub.returncode == 0
    cert_pub_der = openssl("pkey", "-pubin", "-outform", "DER", input_data=cert_pub.stdout)
    key_pub_der = openssl("pkey", "-in", KEY_FILE, "-pubout", "-outform", "DER")
    assert cert_pub_der.returncode == 0 and key_pub_der.returncode == 0
    assert hashlib.sha256(cert_pub_der.stdout).digest() == hashlib.sha256(key_pub_der.stdout).digest(), "Certificate and private key do not match."

    dates = openssl("x509", "-in", CERT_FILE, "-noout", "-dates")
    assert dates.returncode == 0
    values = {}
    for line in dates.stdout.decode().splitlines():
        name, value = line.split("=", 1)
        values[name] = datetime.datetime.strptime(value, "%b %d %H:%M:%S %Y GMT").replace(tzinfo=datetime.timezone.utc)
    assert values["notAfter"] - values["notBefore"] == datetime.timedelta(days=365), "Certificate validity is not exactly 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert values["notBefore"] <= now + datetime.timedelta(minutes=5), "Certificate is not yet valid."
    assert values["notAfter"] > now, "Certificate has expired."


def test_sshd_config():
    assert os.path.isfile(SSHD_CONFIG), f"{SSHD_CONFIG} is missing."
    with open(SSHD_CONFIG, "r") as f:
        content = f.read()

    assert re.search(r"^\s*PermitRootLogin\s+no\s*$", content, re.MULTILINE), "PermitRootLogin is not set to 'no' in sshd_config."
    assert re.search(r"^\s*PasswordAuthentication\s+no\s*$", content, re.MULTILINE), "PasswordAuthentication is not set to 'no' in sshd_config."

    active = {}
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        active.setdefault(parts[0].lower(), []).append(" ".join(parts[1:]).lower())

    assert active.get("permitrootlogin") == ["no"], "PermitRootLogin has a missing, duplicate, or conflicting active setting."
    assert active.get("passwordauthentication") == ["no"], "PasswordAuthentication has a missing, duplicate, or conflicting active setting."
    assert active.get("port") == ["2222"], "The existing Port 2222 setting was not left intact."
    assert active.get("x11forwarding") == ["no"], "The existing X11Forwarding no setting was not left intact."


def test_test_script_and_output():
    assert os.path.isfile(TEST_SH), f"{TEST_SH} is missing."

    real_binary = AUTH_SERVER_BIN + ".verifier-real"
    fd, call_log = tempfile.mkstemp(prefix="auth_calls_")
    os.close(fd)
    sentinel = ("VERIFIER-SENTINEL-" + secrets.token_hex(8) + "\n").encode()

    if os.path.exists(real_binary):
        os.unlink(real_binary)
    os.replace(AUTH_SERVER_BIN, real_binary)
    wrapper = (
        "#!/bin/sh\n"
        "{ printf '%s' \"$#\"; for arg in \"$@\"; do printf '\\t%s' \"$arg\"; done; printf '\\n'; } >> " + shlex.quote(call_log) + "\n"
        "exec " + shlex.quote(real_binary) + " \"$@\"\n"
    )
    try:
        with open(AUTH_SERVER_BIN, "w") as f:
            f.write(wrapper)
        os.chmod(AUTH_SERVER_BIN, 0o755)
        with open(TEST_OUTPUT, "wb") as f:
            f.write(sentinel)

        script_run = subprocess.run(
            ["/bin/bash", TEST_SH], cwd=INCIDENT_DIR,
            capture_output=True, timeout=20
        )
        assert script_run.returncode == 0, f"test.sh failed: {script_run.stderr!r}"

        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert calls == [
            "1\tredirect_to=http://evil.com",
            "1\tredirect_to=/dashboard",
        ], "test.sh must run auth_server exactly twice with the required arguments and order."

        expected = sentinel
        expected += run_server(real_binary, "redirect_to=http://evil.com")
        expected += run_server(real_binary, "redirect_to=/dashboard")
        assert os.path.isfile(TEST_OUTPUT), f"{TEST_OUTPUT} is missing. Did you run test.sh?"
        with open(TEST_OUTPUT, "rb") as f:
            logged = f.read()
        assert logged == expected, "test.sh did not append exactly the stdout of both required runs."
    finally:
        if os.path.lexists(AUTH_SERVER_BIN):
            os.unlink(AUTH_SERVER_BIN)
        if os.path.exists(real_binary):
            os.replace(real_binary, AUTH_SERVER_BIN)
        if os.path.exists(call_log):
            os.unlink(call_log)

    # Retain the original assertions against the freshly generated log.
    content = logged.decode(errors="replace")
    blocks = content.strip().split("HTTP/1.1 302 Found")
    assert len(blocks) >= 3, "test_output.log does not contain two HTTP 302 responses."
    block1 = blocks[1]
    block2 = blocks[2]
    assert "Location: /error" in block1, "First run in test_output.log did not redirect to /error."
    assert "Content-Security-Policy: default-src 'self';" in block1, "First run in test_output.log missing CSP header."
    assert "Location: /dashboard" in block2, "Second run in test_output.log did not redirect to /dashboard."
    assert "Content-Security-Policy: default-src 'self';" in block2, "Second run in test_output.log missing CSP header."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
