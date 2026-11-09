#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import stat
import subprocess


def run_cgi(query):
    path = "/home/user/app/login.cgi"
    env = os.environ.copy()
    env["QUERY_STRING"] = query
    return subprocess.run([path], env=env, capture_output=True, text=True, timeout=10)


def test_cracked_password():
    path = "/home/user/cracked_password.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "hunter2", f"Expected cracked password to be 'hunter2', but got '{content}'"


def test_vuln_headers():
    path = "/home/user/vuln_headers.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read()

    assert "Location: http://evil.com" in content, "Expected 'Location: http://evil.com' in vuln_headers.txt"
    assert "Status: 302 Found" in content, "Expected 'Status: 302 Found' in vuln_headers.txt"

    expected = (
        "Content-Type: text/html\n"
        "Status: 302 Found\n"
        "Location: http://evil.com\n"
        "\n"
        "Success\n"
    )
    assert content == expected, "vuln_headers.txt is not the exact raw output of the requested successful exploit invocation"


def test_login_cgi_patched():
    path = "/home/user/app/login.cgi"
    assert os.path.isfile(path), f"Missing file: {path}"
    assert os.access(path, os.X_OK), f"File {path} is not executable"

    result = run_cgi("user=admin&pass=hunter2&redirect=http://evil.com")
    assert result.returncode == 0, f"CGI exited with status {result.returncode}: {result.stderr}"
    assert "Location: /dashboard" in result.stdout, "Script did not override malicious redirect to /dashboard"
    assert "Location: http://evil.com" not in result.stdout, "Script still vulnerable to open redirect"

    db_path = "/home/user/app/passwd.db"
    original_db = open(db_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(db_path).st_mode)
    token = secrets.token_hex(12)
    username = "audituser" + token
    password = "AuditPass" + token
    password_hash = hashlib.md5(password.encode()).hexdigest()

    try:
        separator = b"" if original_db.endswith(b"\n") or not original_db else b"\n"
        with open(db_path, "wb") as f:
            f.write(original_db + separator + f"{username}:{password_hash}\n".encode())

        success_prefix = "Content-Type: text/html\nStatus: 302 Found\n"
        for redirect in (
            "http://evil.example/" + token,
            "https://evil.example/" + token,
            "//evil.example/" + token,
        ):
            result = run_cgi(f"user={username}&pass={password}&redirect={redirect}")
            assert result.returncode == 0, f"CGI failed for redirect {redirect}: {result.stderr}"
            expected = success_prefix + "Location: /dashboard\n\nSuccess\n"
            assert result.stdout == expected, f"Unsafe redirect {redirect!r} was not replaced exactly with /dashboard"

        safe_redirect = "/account/" + token
        result = run_cgi(f"user={username}&pass={password}&redirect={safe_redirect}")
        expected = success_prefix + f"Location: {safe_redirect}\n\nSuccess\n"
        assert result.returncode == 0
        assert result.stdout == expected, "CGI did not preserve a safe relative redirect"

        result = run_cgi(f"user={username}&pass={password}&redirect=")
        expected = success_prefix + "Location: /dashboard\n\nSuccess\n"
        assert result.returncode == 0
        assert result.stdout == expected, "CGI did not retain the default redirect behavior"

        result = run_cgi(f"user={username}&pass=wrong{token}&redirect=http://evil.example/{token}")
        expected = "Content-Type: text/html\nStatus: 401 Unauthorized\n\nFail\n"
        assert result.returncode == 0
        assert result.stdout == expected, "CGI no longer rejects an invalid password with the original response"
    finally:
        with open(db_path, "wb") as f:
            f.write(original_db)
        os.chmod(db_path, original_mode)


def test_passwd_db_permissions():
    path = "/home/user/app/passwd.db"
    assert os.path.isfile(path), f"Missing file: {path}"
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o600, f"Expected permissions to be 600, but got {oct(mode)}"


def test_ssh_config_hardened():
    path = "/home/user/ssh_config"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read()

    permit_root_login = re.search(r"^\s*PermitRootLogin\s+no\s*$", content, re.MULTILINE)
    password_auth = re.search(r"^\s*PasswordAuthentication\s+no\s*$", content, re.MULTILINE)
    assert permit_root_login, "Expected 'PermitRootLogin no' directive in ssh_config"
    assert password_auth, "Expected 'PasswordAuthentication no' directive in ssh_config"

    permit_root_login_yes = re.search(r"^\s*PermitRootLogin\s+yes\s*$", content, re.MULTILINE)
    password_auth_yes = re.search(r"^\s*PasswordAuthentication\s+yes\s*$", content, re.MULTILINE)
    assert not permit_root_login_yes, "Insecure 'PermitRootLogin yes' directive still present"
    assert not password_auth_yes, "Insecure 'PasswordAuthentication yes' directive still present"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
