#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import socket
import socketserver
import ssl
import stat
import string
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler


def run_classifier(classifier_path, request_path):
    return subprocess.run(
        ["python3", classifier_path, request_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_waf_classifier_corpus():
    """Test the WAF classifier against the clean and evil corpora."""
    classifier_path = "/home/user/waf_classifier.py"
    assert os.path.isfile(classifier_path), f"WAF classifier script not found at {classifier_path}"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_failures = []
    for clean_file in clean_files:
        result = run_classifier(classifier_path, clean_file)
        output = result.stdout.strip()
        if output != "ACCEPT":
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    for evil_file in evil_files:
        result = run_classifier(classifier_path, evil_file)
        output = result.stdout.strip()
        if output != "REJECT":
            evil_failures.append(os.path.basename(evil_file))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_messages, "WAF classifier failed corpus tests:\n" + "\n".join(error_messages)


def test_waf_classifier_generated_requests():
    """Exercise mixed, unpredictably named requests so pathname-only classifiers cannot pass."""
    classifier_path = "/home/user/waf_classifier.py"
    assert os.path.isfile(classifier_path), f"WAF classifier script not found at {classifier_path}"

    nonce = ''.join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=20))
    cases = [
        ("ACCEPT", f"GET /api/status?request={nonce} HTTP/1.1\r\nHost: localhost\r\nX-Request-ID: {nonce}\r\n\r\n"),
        ("ACCEPT", f"POST /api/data HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n\r\n{{\"value\":\"{nonce}\"}}"),
        ("REJECT", f"GET /api/{nonce}/../private HTTP/1.1\r\nHost: localhost\r\n\r\n"),
        ("REJECT", f"GET /api/{nonce}/..%2fprivate HTTP/1.1\r\nHost: localhost\r\n\r\n"),
        ("REJECT", f"GET /search?tag={nonce}&q=UNION+SELECT+id HTTP/1.1\r\nHost: localhost\r\n\r\n"),
        ("REJECT", f"GET /item?name={nonce}&id=1=1 HTTP/1.1\r\nHost: localhost\r\n\r\n"),
        ("REJECT", f"GET /api/status HTTP/1.1\r\nHost: localhost\r\nX-Link: javascript:alert('{nonce}')\r\n\r\n"),
        ("REJECT", f"POST /submit HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\n\r\n<script>alert('{nonce}')</script>"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="request_inputs_") as request_dir:
        failures = []
        for expected, request in cases:
            filename = ''.join(random.SystemRandom().choices(string.ascii_lowercase + string.digits, k=18)) + ".dat"
            path = os.path.join(request_dir, filename)
            with open(path, "w", newline="") as f:
                f.write(request)
            result = run_classifier(classifier_path, path)
            actual = result.stdout.strip()
            if result.returncode != 0 or actual != expected:
                failures.append(f"{filename}: expected {expected}, got {actual!r}, rc={result.returncode}")
        assert not failures, "Generated WAF tests failed:\n" + "\n".join(failures)


def test_nginx_config_contents():
    """Test that nginx.conf is correctly generated with required directives."""
    config_path = "/home/user/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config not found at {config_path}"

    with open(config_path, "r") as f:
        config_content = f.read()

    assert re.search(r"listen\s+8443\s+ssl", config_content) or re.search(r"listen\s+8443", config_content), \
        "Nginx config does not listen on port 8443 (HTTPS)."
    assert "/app/certs/server.crt" in config_content, "Nginx config missing server.crt path."
    assert "/app/certs/server.key" in config_content, "Nginx config missing server.key path."
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):9090", config_content), \
        "Nginx config does not proxy to upstream port 9090."


def custom_nginx_master_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        proc_dir = os.path.join("/proc", entry)
        try:
            with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
                command = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            executable = os.path.realpath(os.path.join(proc_dir, "exe"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if ("nginx" in os.path.basename(executable)
                and "master process" in command
                and "-c /home/user/nginx.conf" in command):
            found.append(int(entry))
    return found


def run_deploy():
    return subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/deploy.sh"],
        capture_output=True,
        text=True,
        timeout=20,
    )


def tls_request(path):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    last_error = None
    for _ in range(30):
        try:
            with socket.create_connection(("127.0.0.1", 8443), timeout=2) as raw:
                with context.wrap_socket(raw, server_hostname="localhost") as conn:
                    peer_cert = conn.getpeercert(binary_form=True)
                    conn.sendall(f"GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode())
                    chunks = []
                    while True:
                        chunk = conn.recv(65536)
                        if not chunk:
                            break
                        chunks.append(chunk)
                    return peer_cert, b"".join(chunks)
        except (OSError, ssl.SSLError) as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Could not make an HTTPS request to Nginx on port 8443: {last_error}")


def test_deploy_script_idempotence_and_https_proxy():
    deploy_path = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_path), f"Deployment script not found at {deploy_path}"
    assert stat.S_IMODE(os.stat(deploy_path).st_mode) & 0o111, "deploy.sh is not executable"

    token = ''.join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=28))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = f"UPSTREAM_OK:{token}:{self.path}".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    try:
        backend = ReusableTCPServer(("127.0.0.1", 9090), Handler)
    except OSError as exc:
        raise AssertionError(f"Unable to start verification upstream on port 9090: {exc}")

    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    try:
        # Require the script itself to regenerate the requested configuration.
        try:
            os.unlink("/home/user/nginx.conf")
        except FileNotFoundError:
            pass

        first = run_deploy()
        assert first.returncode == 0, f"First deploy.sh run failed:\nstdout={first.stdout}\nstderr={first.stderr}"
        assert os.path.isfile("/home/user/nginx.conf"), "deploy.sh did not generate /home/user/nginx.conf"

        first_pids = custom_nginx_master_pids()
        assert first_pids, "No real Nginx master process is running with the custom config after deploy.sh"

        second = run_deploy()
        assert second.returncode == 0, f"Second deploy.sh run failed:\nstdout={second.stdout}\nstderr={second.stderr}"
        second_pids = custom_nginx_master_pids()
        assert second_pids, "Nginx is not running after the second deploy.sh invocation"
        assert set(second_pids) == set(first_pids), "Second deploy.sh run replaced Nginx instead of reloading it idempotently"

        user_uid = pwd.getpwnam("user").pw_uid
        for pid in second_pids:
            assert os.stat(f"/proc/{pid}").st_uid == user_uid, f"Nginx master PID {pid} is not running as user"

        request_path = f"/verify/{token}"
        peer_cert, response = tls_request(request_path)
        assert b" 200 " in response.split(b"\r\n", 1)[0], f"HTTPS request did not return 200: {response[:200]!r}"
        expected_body = f"UPSTREAM_OK:{token}:{request_path}".encode()
        assert expected_body in response, "HTTPS request was not proxied to the verification server on port 9090"

        with open("/app/certs/server.crt", "r") as f:
            expected_cert = ssl.PEM_cert_to_DER_cert(f.read())
        assert peer_cert == expected_cert, "Nginx is not serving /app/certs/server.crt"
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)


def test_nginx_running():
    """Test that Nginx is running as an unprivileged user with the custom config."""
    try:
        result = subprocess.run(["pgrep", "-f", "nginx.*-c /home/user/nginx.conf"], capture_output=True, text=True)
        assert result.returncode == 0 and result.stdout.strip() != "", "Nginx is not running with the custom config."
    except FileNotFoundError:
        result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
        assert "nginx -c /home/user/nginx.conf" in result.stdout or "nginx: master process" in result.stdout, \
            "Nginx is not running with the custom config."

    pids = custom_nginx_master_pids()
    assert pids, "No genuine Nginx master process is using /home/user/nginx.conf"
    user_uid = pwd.getpwnam("user").pw_uid
    assert all(os.stat(f"/proc/{pid}").st_uid == user_uid for pid in pids), "Nginx master is running with elevated privileges"


def test_nginx_data_directories():
    """Test that the required Nginx data directories exist."""
    data_dir = "/home/user/nginx_data"
    assert os.path.isdir(data_dir), f"Nginx data directory not found at {data_dir}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
