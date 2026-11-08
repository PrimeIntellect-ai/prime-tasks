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
import hashlib
import os
import signal
import socket
import ssl
import subprocess
import tarfile
import time
import uuid

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    address, hex_port = local.rsplit(":", 1)
                    if int(hex_port, 16) != port:
                        continue
                    # The task specifically requires the IPv4 loopback address.
                    if table.endswith("tcp") and address != "0100007F":
                        continue
                    inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_listener(port, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.2)
    return set()


def kill_listeners(*ports):
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline:
        if not any(listener_pids(port) for port in ports):
            return
        time.sleep(0.1)


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def test_backup_tarball():
    tar_path = "/home/user/config_backup.tar.gz"
    assert os.path.isfile(tar_path), f"Backup archive {tar_path} does not exist."

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            names = tar.getnames()
            assert any("bashttpd.conf" in name for name in names), "bashttpd.conf not found in the backup tarball."

            files = [m for m in tar.getmembers() if m.isfile()]
            assert len(files) == 1, "The backup must contain exactly the template's one regular file."
            assert os.path.basename(files[0].name) == "bashttpd.conf"
            archived = tar.extractfile(files[0]).read()
            assert archived == b"serve_dir /var/www\n", "The archived configuration is not the original template content."
            assert not any(m.issym() or m.islnk() for m in tar.getmembers()), "Backup must not substitute links for template files."
    except tarfile.ReadError:
        pytest.fail(f"File {tar_path} is not a valid gzip-compressed tar archive.")


def test_bashttpd_conf():
    conf_path = "/home/user/bashttpd.conf"
    assert os.path.isfile(conf_path), f"Configuration file {conf_path} does not exist."
    with open(conf_path) as f:
        content = f.read()
    assert "/home/user/www" in content, f"The configuration file {conf_path} does not seem to point to /home/user/www."


def test_bashttpd_was_fixed_and_executes():
    path = "/app/bashttpd/bashttpd"
    assert os.path.isfile(path), "The bashttpd program is missing."
    assert os.access(path, os.X_OK), "The bashttpd program is not executable."
    with open(path) as f:
        source = f.read()
    assert 'RSPONSE=' not in source, "The deliberately misspelled response variable was not fixed."
    assert 'RESPONSE=' in source, "The corrected RESPONSE assignment is missing."

    result = run([path], input=b"GET /index.html HTTP/1.1\r\nHost: localhost\r\n\r\n", timeout=5)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    output = result.stdout
    assert output.startswith(b"HTTP/1.1 200 OK\r\n"), "bashttpd does not emit the required HTTP status header."
    assert b"Content-Type: text/html\r\n\r\n" in output, "bashttpd does not emit valid response headers."
    assert b"Hello Secure World" in output


def test_cert_and_key_exist_and_are_valid():
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Private key file {key_path} does not exist."

    good = run(["openssl", "pkey", "-in", key_path, "-passin", "pass:HardenedPass123", "-check", "-noout"])
    assert good.returncode == 0, "The private key cannot be decrypted with HardenedPass123."
    wrong = run(["openssl", "pkey", "-in", key_path, "-passin", "pass:DefinitelyWrongPassword", "-noout"])
    assert wrong.returncode != 0, "The private key is not password-protected with the required password."
    rsa = run(["openssl", "rsa", "-in", key_path, "-passin", "pass:HardenedPass123", "-check", "-noout"])
    assert rsa.returncode == 0, "The private key is not a valid RSA key."

    cert_info = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"])
    assert cert_info.returncode == 0, "cert.pem is not a valid X.509 certificate."
    lines = cert_info.stdout.decode().splitlines()
    subject = next((x.split("=", 1)[1] for x in lines if x.startswith("subject=")), None)
    issuer = next((x.split("=", 1)[1] for x in lines if x.startswith("issuer=")), None)
    assert subject and subject == issuer, "The certificate is not self-signed."
    verified = run(["openssl", "verify", "-CAfile", cert_path, cert_path])
    assert verified.returncode == 0, "The self-signed certificate does not verify against itself."

    cert_pub = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", key_path, "-passin", "pass:HardenedPass123", "-pubout"])
    assert cert_pub.returncode == key_pub.returncode == 0
    assert cert_pub.stdout == key_pub.stdout, "The certificate and private key do not match."


def test_expect_script_exists():
    script_path = "/home/user/start_service.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} does not exist."
    with open(script_path, "rb") as f:
        first = f.readline().lower()
    assert b"expect" in first or script_path.endswith(".exp"), "start_service.exp is not an Expect script."


def test_https_service():
    url = "https://127.0.0.1:8443/index.html"
    index_path = "/home/user/www/index.html"
    assert os.path.isfile(index_path), f"Index file {index_path} does not exist."
    with open(index_path) as f:
        expected_content = f.read().strip()
    try:
        response = requests.get(url, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTPS service at {url}. Error: {e}")
    assert response.status_code == 200, f"Expected HTTP status 200, but got {response.status_code}."
    assert expected_content in response.text, "The content returned by the web server does not match the expected index.html content."


def test_expect_starts_real_bashttpd_tls_proxy():
    script = "/home/user/start_service.exp"
    kill_listeners(8080, 8443)

    # Execute the submitted Expect artifact from a clean port state. It may exit
    # after daemonizing or remain as a supervisor; either behavior is acceptable.
    subprocess.Popen(["expect", script], cwd="/home/user", stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)

    backend_pids = wait_for_listener(8080)
    tls_pids = wait_for_listener(8443)
    assert backend_pids, "The Expect script did not start a service on 127.0.0.1:8080."
    assert tls_pids, "The Expect script did not start a TLS service on 127.0.0.1:8443."

    backend_cmds = "\n".join(cmdline(pid) for pid in backend_pids)
    assert "/app/bashttpd/bashttpd" in backend_cmds, "Port 8080 is not being served by the required bashttpd program."
    tls_cmds = "\n".join(cmdline(pid).lower() for pid in tls_pids)
    assert any(tool in tls_cmds for tool in ("openssl", "socat", "stunnel")), "Port 8443 is not owned by the required kind of TLS proxy."

    # Confirm the live endpoint presents the submitted certificate.
    context = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="localhost") as wrapped:
            peer_der = wrapped.getpeercert(binary_form=True)
    cert_der = run(["openssl", "x509", "-in", "/home/user/cert.pem", "-outform", "DER"])
    assert cert_der.returncode == 0
    assert peer_der == cert_der.stdout, "The TLS service is not using /home/user/cert.pem."

    # Use unpredictable content so a fixed response cannot satisfy the test.
    name = "verify_" + uuid.uuid4().hex + ".html"
    path = os.path.join("/home/user/www", name)
    token = "dynamic-" + uuid.uuid4().hex
    with open(path, "w") as f:
        f.write(token)

    try:
        backend = requests.get(f"http://127.0.0.1:8080/{name}", timeout=5)
        assert backend.status_code == 200 and token in backend.text, "The bashttpd backend did not serve the requested file."
        secure = requests.get(f"https://127.0.0.1:8443/{name}", verify=False, timeout=5)
        assert secure.status_code == 200 and token in secure.text, "The TLS endpoint did not proxy the bashttpd response."

        # Removing only the backend must prevent the TLS endpoint from serving
        # the token, proving that 8443 is a proxy rather than an independent server.
        kill_listeners(8080)
        assert not listener_pids(8080)
        still_served = False
        try:
            response = requests.get(f"https://127.0.0.1:8443/{name}?{uuid.uuid4().hex}", verify=False, timeout=3)
            still_served = response.status_code == 200 and token in response.text
        except requests.exceptions.RequestException:
            pass
        assert not still_served, "The HTTPS service continues serving content without the bashttpd backend; it is not the required TLS proxy."

        # Restore the required backend so the service is left running after verification.
        subprocess.Popen([
            "socat", "TCP-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork",
            "EXEC:/app/bashttpd/bashttpd"
        ], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
           stderr=subprocess.DEVNULL, start_new_session=True)
        assert wait_for_listener(8080, timeout=5), "Could not restore the bashttpd backend after the dependency test."
        final = requests.get("https://127.0.0.1:8443/index.html", verify=False, timeout=5)
        assert final.status_code == 200 and "Hello Secure World" in final.text
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
