#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
import sys
import importlib.util
from cryptography import x509
from cryptography.x509.oid import NameOID


def read_report():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."
    with open(report_path, "r") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def payload_target(payload_path):
    with open(payload_path, "r") as f:
        tree = ast.parse(f.read(), filename=payload_path)
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Constant) and isinstance(value.value, str) and os.path.isabs(value.value):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                if any(isinstance(target, ast.Name) and target.id == "target" for target in targets):
                    return os.path.abspath(value.value)
    raise AssertionError("Could not derive the payload target from payload.py")


def test_report_contents():
    lines = read_report()
    assert len(lines) >= 3, "/home/user/report.txt must contain at least 3 lines."

    # Preserve the original expected-result assertions.
    assert lines[0] == "CWE-601", f"Line 1 of report is '{lines[0]}', expected 'CWE-601'."
    assert lines[1] == "EvilCorpRoot", f"Line 2 of report is '{lines[1]}', expected 'EvilCorpRoot'."
    assert lines[2] == "/home/user/secret_master_key.pem", f"Line 3 of report is '{lines[2]}', expected '/home/user/secret_master_key.pem'."

    cert_dir = "/home/user/evidence/certs"
    ca_path = os.path.join(cert_dir, "ca.crt")
    server_cert_path = os.path.join(cert_dir, "server.crt")
    verification = subprocess.run(
        ["openssl", "verify", "-CAfile", ca_path, server_cert_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert verification.returncode != 0, "server.crt unexpectedly verifies against ca.crt."

    with open(server_cert_path, "rb") as f:
        cert = x509.load_pem_x509_certificate(f.read())
    issuer_names = cert.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert len(issuer_names) == 1, "server.crt must have exactly one issuer Common Name."
    assert lines[1] == issuer_names[0].value, "Report issuer CN was not derived correctly from server.crt."
    assert lines[2] == payload_target("/home/user/evidence/payload.py"), "Report target does not match payload.py."


def load_server():
    server_path = "/home/user/evidence/server.py"
    assert os.path.isfile(server_path), f"{server_path} is missing."
    spec = importlib.util.spec_from_file_location("server_under_test", server_path)
    server_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(server_module)
    app = getattr(server_module, "app", None)
    assert app is not None, "Flask app not found in server.py"
    return app


def test_server_patched():
    client = load_server().test_client()

    # Preserve the original redirect assertions.
    response = client.post('/login?next=/dashboard')
    assert response.status_code == 302, "Valid relative redirect did not return 302."
    assert response.headers['Location'] == '/dashboard', "Valid relative redirect failed."

    response = client.post('/login?next=http://evil.com')
    assert response.status_code == 302, "Invalid redirect did not return 302."
    assert response.headers['Location'] == '/home', "Invalid redirect (http) was not redirected to /home."

    response = client.post('/login?next=//evil.com')
    assert response.status_code == 302, "Invalid redirect did not return 302."
    assert response.headers['Location'] == '/home', "Invalid redirect (//) was not redirected to /home."

    token = secrets.token_hex(8)
    valid_paths = [
        f"/{token}",
        f"/{token}/nested",
        f"/http-{token}",
        f"/https://{token}",
    ]
    for destination in valid_paths:
        response = client.post('/login', query_string={"next": destination})
        assert response.status_code == 302
        assert response.headers["Location"] == destination, f"Valid relative path {destination!r} was rejected."

    invalid_paths = [
        f"//{token}.example/path",
        f"///{token}/path",
        f"http://{token}.example/path",
        f"https://{token}.example/path",
        f"HTTP://{token}.example/path",
        f"ftp://{token}.example/path",
        f"javascript:{token}",
        token,
        f"../{token}",
        f"\\\\{token}.example\\path",
    ]
    for destination in invalid_paths:
        response = client.post('/login', query_string={"next": destination})
        assert response.status_code == 302
        assert response.headers["Location"] == "/home", f"Invalid redirect {destination!r} was accepted."


def test_sandbox_exists_and_functionally_blocks_payload():
    sandbox_path = "/home/user/sandbox.py"
    payload_path = "/home/user/evidence/payload.py"
    report_path = "/home/user/report.txt"
    assert os.path.isfile(sandbox_path), f"{sandbox_path} is missing."

    with open(sandbox_path, "r") as f:
        content = f.read()
    # Preserve the original assertion in addition to the functional test below.
    assert "sys.addaudithook" in content, "sandbox.py does not appear to use sys.addaudithook."

    with open(payload_path, "rb") as f:
        original_payload = f.read()
    with open(report_path, "rb") as f:
        original_report = f.read()

    token = secrets.token_hex(12)
    target = f"/home/user/audit_target_{token}.dat"
    secret = ("UNREADABLE_" + secrets.token_hex(24)).encode()
    read_fd, write_fd = os.pipe()

    replacement_payload = f'''import os


def steal_data():
    fd = int(os.environ["SANDBOX_TEST_FD"])
    os.write(fd, ("PID:" + str(os.getpid()) + "\\n").encode())
    target = {target!r}
    try:
        with open(target, "rb") as f:
            data = f.read()
        os.write(fd, b"READ:" + data + b"\\n")
    except BaseException:
        os.write(fd, b"BLOCKED\\n")


if __name__ == "__main__":
    steal_data()
'''.encode()

    proc = None
    try:
        with open(target, "wb") as f:
            f.write(secret)
        with open(payload_path, "wb") as f:
            f.write(replacement_payload)

        original_lines = [line.strip() for line in original_report.decode().splitlines() if line.strip()]
        assert len(original_lines) >= 2
        with open(report_path, "w") as f:
            f.write(original_lines[0] + "\n" + original_lines[1] + "\n")

        env = os.environ.copy()
        env["SANDBOX_TEST_FD"] = str(write_fd)
        proc = subprocess.run(
            [sys.executable, sandbox_path],
            cwd="/home/user",
            env=env,
            pass_fds=(write_fd,),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        os.close(write_fd)
        write_fd = -1
        marker = os.read(read_fd, 65536)

        assert proc.returncode == 0, (
            f"sandbox.py failed with exit code {proc.returncode}: "
            + proc.stderr.decode(errors="replace")
        )
        assert f"PID:{proc.pid}\n".encode() in marker, "payload.py was not executed in the sandbox process."
        assert b"BLOCKED\n" in marker, "The payload's open attempt was not blocked."
        assert b"READ:" not in marker and secret not in marker, "The sandbox allowed the payload to read the protected file."

        lines = read_report()
        assert len(lines) >= 3, "sandbox.py did not append the captured path to the report."
        assert lines[0] == original_lines[0] and lines[1] == original_lines[1], "sandbox.py damaged existing report entries."
        assert lines[2] == os.path.abspath(target), "sandbox.py did not capture the attempted absolute path."
    finally:
        if write_fd >= 0:
            os.close(write_fd)
        os.close(read_fd)
        with open(payload_path, "wb") as f:
            f.write(original_payload)
        with open(report_path, "wb") as f:
            f.write(original_report)
        try:
            os.unlink(target)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
