#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
import stat
import subprocess


def test_tls_certificate_exists_and_valid():
    cert_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"

    assert os.path.exists(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.exists(key_path), f"Key file {key_path} does not exist."

    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to parse certificate: {result.stderr}"
    assert "CN = secure-legacy.local" in result.stdout or "CN=secure-legacy.local" in result.stdout, \
        f"Certificate does not have the correct Common Name (CN). Got: {result.stdout}"


def test_auth_token_generation():
    secret_path = "/home/user/secret.txt"
    token_path = "/home/user/auth_token.txt"

    assert os.path.exists(token_path), f"Token file {token_path} does not exist."

    with open(secret_path, "r") as f:
        secret = f.read().strip()

    expected_hmac = hmac.new(
        secret.encode("utf-8"),
        b"user=admin",
        hashlib.sha256,
    ).hexdigest()

    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token == expected_hmac, \
        f"Auth token does not match expected HMAC. Expected {expected_hmac}, got {actual_token}"


def test_audit_report_contents():
    report_path = "/home/user/audit_report.txt"
    assert os.path.exists(report_path), f"Audit report {report_path} does not exist."

    expected_files = [
        "/home/user/app/safe_file.txt",
        "/home/user/app/server.py",
        "/home/user/app/subdir/another_suid",
        "/home/user/app/suid_bin",
        "/home/user/app/world_writable.log",
    ]

    with open(report_path, "r") as f:
        actual_files = [line.strip() for line in f if line.strip()]

    assert actual_files == expected_files, \
        f"Audit report contents are incorrect. Expected {expected_files}, got {actual_files}"


def test_run_secure_wrapper():
    wrapper_path = "/home/user/run_secure.sh"
    server_path = "/home/user/app/server.py"
    token_path = "/home/user/auth_token.txt"

    assert os.path.exists(wrapper_path), f"Wrapper script {wrapper_path} does not exist."

    st = os.stat(wrapper_path)
    assert stat.S_ISREG(st.st_mode), f"Wrapper script {wrapper_path} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"Wrapper script {wrapper_path} is not executable."

    with open(wrapper_path, "r") as f:
        content = f.read()

    assert "ulimit -n 50" in content, "Wrapper script does not contain 'ulimit -n 50'."
    assert "env -i" in content, "Wrapper script does not contain 'env -i'."
    assert "PATH=/usr/bin:/bin" in content or "PATH='/usr/bin:/bin'" in content or 'PATH="/usr/bin:/bin"' in content, \
        "Wrapper script does not set PATH correctly."
    assert "AUTH_TOKEN" in content, "Wrapper script does not expose AUTH_TOKEN."
    assert "/home/user/app/server.py" in content, "Wrapper script does not execute the target server script."

    server_lstat = os.lstat(server_path)
    assert stat.S_ISREG(server_lstat.st_mode), f"Target server {server_path} is not a regular file."

    with open(server_path, "rb") as f:
        original_server = f.read()
    with open(token_path, "rb") as f:
        original_token = f.read()

    server_mode = stat.S_IMODE(server_lstat.st_mode)
    token_mode = stat.S_IMODE(os.stat(token_path).st_mode)
    runtime_token = "runtime-check-" + os.urandom(24).hex()
    marker = "SECURE_WRAPPER_PROBE="
    probe = '''#!/usr/bin/python3
import json
import resource
raw = open("/proc/self/environ", "rb").read()
env = {}
for entry in raw.split(b"\\0"):
    if entry and b"=" in entry:
        key, value = entry.split(b"=", 1)
        env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
print("SECURE_WRAPPER_PROBE=" + json.dumps({"env": env, "nofile": resource.getrlimit(resource.RLIMIT_NOFILE)[0]}, sort_keys=True))
'''

    try:
        with open(token_path, "w") as f:
            f.write(runtime_token + "\n")
        os.chmod(token_path, token_mode)

        with open(server_path, "w") as f:
            f.write(probe)
        os.chmod(server_path, server_mode | stat.S_IXUSR)

        result = subprocess.run(
            [wrapper_path],
            capture_output=True,
            text=True,
            timeout=10,
            cwd="/tmp",
        )
        assert result.returncode == 0, \
            f"Wrapper execution failed with code {result.returncode}: {result.stderr}"

        probe_lines = [line for line in result.stdout.splitlines() if line.startswith(marker)]
        assert len(probe_lines) == 1, \
            f"Wrapper did not execute the target server probe exactly once. Output: {result.stdout!r}"
        observed = json.loads(probe_lines[0][len(marker):])

        assert observed["nofile"] == 50, \
            f"Wrapper did not enforce a file descriptor limit of 50. Got: {observed['nofile']}"
        assert observed["env"] == {
            "PATH": "/usr/bin:/bin",
            "AUTH_TOKEN": runtime_token,
        }, f"Wrapper target received an incorrect environment: {observed['env']}"
    finally:
        with open(server_path, "wb") as f:
            f.write(original_server)
        os.chmod(server_path, server_mode)
        with open(token_path, "wb") as f:
            f.write(original_token)
        os.chmod(token_path, token_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
