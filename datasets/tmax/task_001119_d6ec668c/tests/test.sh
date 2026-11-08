#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import runpy
import shlex
import signal
import socket
import ssl
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest


def cleanup_service_processes():
    subprocess.run(["pkill", "-TERM", "-f", "^/usr/bin/python3 /home/user/webhook_service.py$"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    subprocess.run(["pkill", "-KILL", "-f", "^/usr/bin/python3 /home/user/webhook_service.py$"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_certs_exist():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.exists(cert_path), f"Missing certificate file: {cert_path}"
    assert os.path.exists(key_path), f"Missing key file: {key_path}"


def test_logs_dir_exists():
    logs_dir = "/home/user/logs"
    assert os.path.exists(logs_dir), f"Missing logs directory: {logs_dir}"
    assert os.path.isdir(logs_dir), f"{logs_dir} is not a directory"


def test_webhook_service_fixed():
    path = "/home/user/webhook_service.py"
    assert os.path.exists(path), f"Missing required file: {path}"

    with open(path, 'r') as f:
        content = f.read()

    assert "RotatingFileHandler" in content, "webhook_service.py does not use RotatingFileHandler"
    assert "maxBytes=1024" in content.replace(" ", ""), "webhook_service.py does not configure maxBytes=1024"
    assert "backupCount=3" in content.replace(" ", ""), "webhook_service.py does not configure backupCount=3"
    assert "ssl." in content, "webhook_service.py does not contain TLS configuration"
    assert "cert.pem" in content, "webhook_service.py does not reference cert.pem"
    assert "key.pem" in content, "webhook_service.py does not reference key.pem"


def test_ci_pipeline_script():
    script_path = "/home/user/ci_pipeline.sh"
    assert os.path.exists(script_path), f"Missing CI pipeline script: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"

    with open(script_path, 'r') as f:
        content = f.read()

    assert "CI SUCCESS" in content, f"{script_path} does not contain 'CI SUCCESS'"
    assert "curl" in content, f"{script_path} does not use curl"
    assert "8443" in content, f"{script_path} does not reference port 8443"


def test_ci_pipeline_execution():
    script_path = "/home/user/ci_pipeline.sh"
    assert os.path.exists(script_path), "Script missing, cannot run execution test"

    try:
        result = subprocess.run([script_path], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"CI pipeline script failed with exit code {result.returncode}. Stderr: {result.stderr}"
        assert "CI SUCCESS" in result.stdout, "CI pipeline script did not output 'CI SUCCESS'"
    except subprocess.TimeoutExpired:
        pytest.fail("CI pipeline script timed out. Ensure the background process is terminated correctly.")
    finally:
        cleanup_service_processes()


def test_certificate_is_valid_self_signed_and_matches_key():
    cert = "/home/user/certs/cert.pem"
    key = "/home/user/certs/key.pem"

    subprocess.run(["openssl", "x509", "-in", cert, "-noout", "-checkend", "0"], check=True, capture_output=True, text=True)
    subprocess.run(["openssl", "pkey", "-in", key, "-noout", "-check"], check=True, capture_output=True, text=True)

    subject = subprocess.check_output(
        ["openssl", "x509", "-in", cert, "-noout", "-subject", "-nameopt", "RFC2253"], text=True
    ).strip().split("=", 1)[1]
    issuer = subprocess.check_output(
        ["openssl", "x509", "-in", cert, "-noout", "-issuer", "-nameopt", "RFC2253"], text=True
    ).strip().split("=", 1)[1]
    assert subject == issuer, "Certificate is not self-signed"

    cert_public_pem = subprocess.check_output(["openssl", "x509", "-in", cert, "-pubkey", "-noout"])
    cert_public_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_public_pem, capture_output=True, check=True
    ).stdout
    key_public_der = subprocess.check_output(
        ["openssl", "pkey", "-in", key, "-pubout", "-outform", "DER"]
    )
    assert cert_public_der == key_public_der, "Certificate and private key do not match"


def test_service_really_serves_https_and_rotates_logs():
    cleanup_service_processes()
    for path in glob.glob("/home/user/logs/webhook.log*"):
        if os.path.isfile(path):
            os.remove(path)

    proc = subprocess.Popen(
        ["/usr/bin/python3", "/home/user/mock_systemd.py", "start", "webhook.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    context = ssl._create_unverified_context()
    body = None
    peer_cert = None
    last_error = None

    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate(timeout=1)
                pytest.fail(f"Supervisor exited before HTTPS service became ready. stdout={stdout!r}, stderr={stderr!r}")
            try:
                with urllib.request.urlopen("https://localhost:8443/", context=context, timeout=0.5) as response:
                    body = response.read().decode("utf-8")
                with socket.create_connection(("localhost", 8443), timeout=1) as raw:
                    with context.wrap_socket(raw, server_hostname="localhost") as tls_socket:
                        peer_cert = tls_socket.getpeercert(binary_form=True)
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)

        assert body is not None, f"Service did not become available over HTTPS: {last_error}"
        assert "Webhook Service Online" in body, f"Unexpected HTTPS response body: {body!r}"
        assert peer_cert, "TLS server did not present a certificate"

        for _ in range(100):
            with urllib.request.urlopen("https://localhost:8443/", context=context, timeout=1) as response:
                assert "Webhook Service Online" in response.read().decode("utf-8")

        deadline = time.time() + 3
        backups = []
        while time.time() < deadline:
            backups = glob.glob("/home/user/logs/webhook.log.*")
            if backups:
                break
            time.sleep(0.1)

        assert os.path.isfile("/home/user/logs/webhook.log"), "Rotating log file was not created"
        assert backups, "Log did not rotate after exceeding 1024 bytes"
        assert len(backups) <= 3, "More than three rotated log backups were retained"
        assert os.path.getsize("/home/user/logs/webhook.log") <= 1024, "Active log exceeds configured maxBytes=1024"
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGINT)
                proc.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        cleanup_service_processes()


def _wait_for_supervisor_exit():
    deadline = time.time() + 3
    while time.time() < deadline:
        found = subprocess.run(
            ["pgrep", "-f", "^/usr/bin/python3 /home/user/mock_systemd.py start webhook[.]service$"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
        if not found:
            return True
        time.sleep(0.1)
    return False


def test_pipeline_invokes_supervisor_and_curl_and_handles_failure():
    cleanup_service_processes()
    script = "/home/user/ci_pipeline.sh"
    supervisor = "/home/user/mock_systemd.py"
    curl = "/usr/bin/curl"
    token = uuid.uuid4().hex
    supervisor_original = f"/tmp/mock_systemd.{token}.py"
    curl_original = f"/tmp/curl.{token}"
    supervisor_marker = f"/tmp/supervisor.{token}.log"
    curl_marker = f"/tmp/curl.{token}.log"

    os.replace(supervisor, supervisor_original)
    os.replace(curl, curl_original)
    try:
        with open(supervisor, "w") as f:
            f.write(
                "import runpy, sys\n"
                f"with open({supervisor_marker!r}, 'a') as marker:\n"
                "    marker.write(repr(sys.argv) + '\\n')\n"
                f"runpy.run_path({supervisor_original!r}, run_name='__main__')\n"
            )
        os.chmod(supervisor, 0o777)

        with open(curl, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s\\n' \"$*\" >> {shlex.quote(curl_marker)}\n")
            f.write('if [ "${VERIFIER_FORCE_CURL_FAIL:-0}" = "1" ]; then exit 7; fi\n')
            f.write(f"exec {shlex.quote(curl_original)} \"$@\"\n")
        os.chmod(curl, 0o755)

        success = subprocess.run([script], capture_output=True, text=True, timeout=15)
        assert success.returncode == 0, f"Pipeline success path exited {success.returncode}: {success.stderr}"
        assert "CI SUCCESS" in success.stdout, "Pipeline success path did not print CI SUCCESS"
        assert os.path.exists(supervisor_marker), "Pipeline did not invoke /home/user/mock_systemd.py"
        assert os.path.exists(curl_marker), "Pipeline did not invoke curl"

        with open(supervisor_marker) as f:
            supervisor_calls = f.read()
        assert "'start'" in supervisor_calls and "'webhook.service'" in supervisor_calls, \
            "Pipeline did not call the supervisor with 'start webhook.service'"

        with open(curl_marker) as f:
            curl_calls = [line.strip() for line in f if line.strip()]
        assert curl_calls, "No curl invocation was recorded"
        assert any("https://localhost:8443/" in call for call in curl_calls), \
            "Pipeline did not curl https://localhost:8443/"
        assert any("-k" in shlex.split(call) or "--insecure" in shlex.split(call) for call in curl_calls), \
            "Pipeline did not ignore self-signed certificate validation errors"
        assert _wait_for_supervisor_exit(), "Pipeline did not terminate its background supervisor"
        cleanup_service_processes()

        open(supervisor_marker, "w").close()
        open(curl_marker, "w").close()
        env = os.environ.copy()
        env["VERIFIER_FORCE_CURL_FAIL"] = "1"
        failed = subprocess.run([script], capture_output=True, text=True, timeout=15, env=env)
        assert failed.returncode == 1, f"Pipeline must exit 1 when curl fails, got {failed.returncode}"
        assert "CI FAILED" in failed.stdout, "Pipeline did not print CI FAILED when curl failed"
        assert "CI SUCCESS" not in failed.stdout, "Pipeline falsely printed CI SUCCESS when curl failed"
        assert os.path.getsize(supervisor_marker) > 0, "Failure path did not start the supervisor"
        assert os.path.getsize(curl_marker) > 0, "Failure path did not attempt curl"
        assert _wait_for_supervisor_exit(), "Failure path did not terminate its background supervisor"
    finally:
        cleanup_service_processes()
        if os.path.exists(supervisor):
            os.remove(supervisor)
        if os.path.exists(supervisor_original):
            os.replace(supervisor_original, supervisor)
        if os.path.exists(curl):
            os.remove(curl)
        if os.path.exists(curl_original):
            os.replace(curl_original, curl)
        for path in (supervisor_marker, curl_marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
