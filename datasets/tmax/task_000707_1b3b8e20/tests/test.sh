#!/bin/bash
set +e
mkdir -p /logs/verifier

PRE_LISTEN=$(python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(1)
try:
    print("1" if s.connect_ex(("127.0.0.1", 8080)) == 0 else "0")
finally:
    s.close()
PY
)
export PRE_LISTEN

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import signal
import socket
import sqlite3
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

BINARY = "/home/user/server_fixed"
SOURCE = "/home/user/src/server.cpp"
DB = "/home/user/data/users.db"


def listener_inodes(port=8080):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        found.add(fields[9])
        except OSError:
            pass
    return found


def pids_owning(inodes):
    owners = set()
    if not inodes:
        return owners
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            pass
    return owners


def clear_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        owners = pids_owning(listener_inodes())
        if not owners:
            return
        for pid in owners:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)


def request(path, form=None):
    url = "http://127.0.0.1:8080" + path
    data = None if form is None else urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.getcode(), response.info(), response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode("utf-8")
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to server: {e}")


@pytest.fixture(scope="session", autouse=True)
def run_submitted_binary():
    assert os.path.isfile(BINARY), f"Compiled server not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable"

    clear_port()
    proc = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 6
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"{BINARY} exited before listening on port 8080")
        inodes = listener_inodes()
        if inodes:
            assert proc.pid in pids_owning(inodes), "Port 8080 is not owned by the submitted server_fixed process"
            break
        time.sleep(0.1)
    else:
        proc.terminate()
        pytest.fail("Submitted server_fixed did not listen on port 8080")

    yield
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def test_audit_trail_exists_and_valid():
    audit_file = "/home/user/audit_trail.json"
    assert os.path.isfile(audit_file), f"Audit trail file not found at {audit_file}"
    with open(audit_file) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit trail is not valid JSON")

    expected_vulns = ["SQL_Injection", "Reflected_XSS", "Insecure_Cookie", "Weak_Password_Hashing"]
    assert "vulnerabilities_fixed" in data, "Missing 'vulnerabilities_fixed' in audit trail"
    assert sorted(data["vulnerabilities_fixed"]) == sorted(expected_vulns), "Incorrect vulnerabilities_fixed list"
    assert data.get("hashing_algorithm_implemented") == "SHA-256", "Incorrect hashing algorithm in audit trail"
    assert "cookie_flags_added" in data, "Missing 'cookie_flags_added' in audit trail"
    assert sorted(data["cookie_flags_added"]) == sorted(["HttpOnly", "Secure"]), "Incorrect cookie flags in audit trail"


def test_server_running_on_8080():
    assert os.environ.get("PRE_LISTEN") == "1", "Server was not listening on port 8080 when verification began"
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        assert s.connect_ex(("127.0.0.1", 8080)) == 0, "Submitted server is not listening on port 8080"


def test_source_uses_required_security_apis_and_compiles():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"
    with open(SOURCE) as f:
        src = f.read()

    assert "sqlite3_prepare_v2" in src, "Login does not use sqlite3_prepare_v2"
    assert "sqlite3_bind_text" in src, "Login does not bind the username with sqlite3_bind_text"
    assert re.search(r"SELECT\s+password_hash\s+FROM\s+users\s+WHERE\s+username\s*=\s*\?", src, re.I), \
        "The password lookup is not a parameterized query"
    assert re.search(r"\bSHA256\s*\(|\bEVP_sha256\s*\(", src), "SHA-256 is not implemented through OpenSSL"

    output = "/tmp/verifier_server_from_source"
    result = subprocess.run([
        "g++", "-std=c++11", SOURCE, "-o", output,
        "-lsqlite3", "-lssl", "-lcrypto", "-lpthread"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    assert result.returncode == 0, f"server.cpp does not compile with the required flags:\n{result.stderr}"

    linked = subprocess.run(["ldd", BINARY], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert linked.returncode == 0 and "libcrypto" in linked.stdout, "server_fixed is not linked to OpenSSL libcrypto"


def test_sql_injection_fixed():
    status, _, _ = request("/login", {"username": "admin' OR '1'='1", "password": "wrong"})
    assert status == 401, f"Expected 401 Unauthorized for SQL injection attempt, got {status}. SQLi is likely not fixed."


def test_crypto_and_cookie_fixed():
    status, headers, _ = request("/login", {"username": "admin", "password": "admin"})
    assert status == 200, f"Expected 200 OK for valid credentials, got {status}"
    set_cookie = headers.get("Set-Cookie", "")
    assert "HttpOnly" in set_cookie, "Set-Cookie header is missing the HttpOnly flag"
    assert "Secure" in set_cookie, "Set-Cookie header is missing the Secure flag"


def test_randomized_sha256_login_prepared_statement_and_cookie():
    token = secrets.token_hex(12)
    username = "audit_" + token
    password = "Pw-" + secrets.token_urlsafe(18)
    digest = hashlib.sha256(password.encode()).hexdigest()

    with sqlite3.connect(DB) as db:
        db.execute("INSERT INTO users(username, password_hash) VALUES (?, ?)", (username, digest))

    status, headers, _ = request("/login", {"username": username, "password": password})
    assert status == 200, "A randomized user with the correct SHA-256 password hash could not log in"
    cookie = headers.get("Set-Cookie", "")
    attributes = {part.strip().lower() for part in cookie.split(";")}
    assert "httponly" in attributes, "Randomized successful login cookie lacks HttpOnly"
    assert "secure" in attributes, "Randomized successful login cookie lacks Secure"

    status, _, _ = request("/login", {"username": username, "password": password + "-wrong"})
    assert status == 401, "An incorrect randomized password was accepted"

    injection = "' OR username = '" + username + "' --"
    status, _, _ = request("/login", {"username": injection, "password": password})
    assert status == 401, "A dynamically generated SQL injection selected another user's password hash"


def test_xss_fixed():
    status, _, body = request("/greet?name=%3Cscript%3Ealert(1)%3C/script%3E")
    assert status == 200
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in body, "XSS payload was not correctly HTML entity encoded"
    assert "<script>" not in body, "Unencoded <script> tag found in response, XSS vulnerability is still present"


def test_all_required_html_characters_are_encoded_with_random_input():
    marker = "m" + secrets.token_hex(10)
    raw = marker + "<>&\"'"
    status, _, body = request("/greet?" + urllib.parse.urlencode({"name": raw}))
    assert status == 200
    match = re.search(r"<h1>Hello, (.*?)</h1>", body, re.S)
    assert match, "Greeting response did not contain the expected HTML structure"
    reflected = match.group(1)
    allowed = {
        marker + "&lt;&gt;&amp;&quot;&#39;",
        marker + "&lt;&gt;&amp;&quot;&#x27;",
        marker + "&lt;&gt;&amp;&quot;&apos;",
    }
    assert reflected in allowed, f"Not all five required HTML characters were entity encoded: {reflected!r}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
