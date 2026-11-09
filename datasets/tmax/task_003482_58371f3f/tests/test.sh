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
import base64
import json
import os
import re
import secrets
import stat
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

import requests


class MockBackendHandler(BaseHTTPRequestHandler):
    hits = 0

    def do_GET(self):
        type(self).hits += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Backend OK")

    def log_message(self, fmt, *args):
        pass


def setup_module(module):
    module.backend_server = HTTPServer(("127.0.0.1", 8080), MockBackendHandler)
    thread = threading.Thread(target=module.backend_server.serve_forever, daemon=True)
    thread.start()

    startup_script = "/home/user/start_gateway.sh"
    assert os.path.exists(startup_script), f"{startup_script} does not exist"
    subprocess.run(["chmod", "+x", startup_script], check=True)
    module.gateway_process = subprocess.Popen(["bash", startup_script])
    time.sleep(3)

    # Stale or prepopulated audit entries must not satisfy the behavioral tests.
    with open("/home/user/audit.log", "w"):
        pass


def teardown_module(module):
    if hasattr(module, "backend_server"):
        module.backend_server.shutdown()
    subprocess.run(["pkill", "-f", "nginx"], check=False)
    subprocess.run(["pkill", "-f", "fcgiwrap"], check=False)


def find_certs():
    certs_dir = "/home/user/certs"
    assert os.path.isdir(certs_dir), f"{certs_dir} directory is missing"
    crts = [os.path.join(certs_dir, f) for f in os.listdir(certs_dir)
            if f.endswith(".crt") or f.endswith(".pem")]
    keys = [os.path.join(certs_dir, f) for f in os.listdir(certs_dir) if f.endswith(".key")]

    ca_cert = None
    client_cert = None
    client_key = None
    for crt in crts:
        out = subprocess.check_output(["openssl", "x509", "-in", crt, "-text", "-noout"]).decode()
        if "CA:TRUE" in out:
            ca_cert = crt
        elif "TLS Web Client Authentication" in out or "client" in crt.lower():
            client_cert = crt
    if not ca_cert:
        for crt in crts:
            if "ca" in crt.lower():
                ca_cert = crt
    if not client_cert:
        for crt in crts:
            if "client" in crt.lower():
                client_cert = crt
    for key in keys:
        if "client" in key.lower():
            client_key = key
    return ca_cert, client_cert, client_key


def nginx_pids():
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
            if os.path.basename(exe) == "nginx":
                result.append(int(name))
        except OSError:
            pass
    return result


def listening_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                    found.add(fields[9])
    return found


def process_owns_any_socket(pids, inodes):
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for pid in pids:
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    if os.readlink(f"/proc/{pid}/fd/{fd}") in wanted:
                        return True
                except OSError:
                    pass
        except OSError:
            pass
    return False


def b64url(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def run_cgi(token):
    env = os.environ.copy()
    env.update({
        "REQUEST_METHOD": "GET",
        "REQUEST_URI": "/data",
        "SCRIPT_NAME": "/auth",
        "GATEWAY_INTERFACE": "CGI/1.1",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "HTTP_AUTHORIZATION": "Bearer " + token,
    })
    return subprocess.run(["/home/user/auth_filter.cgi"], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=5, check=False)


def assert_audit_entry(header, status):
    pattern = re.compile(
        r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] AUDIT: Token with header "
        + re.escape(header) + r" evaluated\. Status: " + str(status) + r"$"
    )
    with open("/home/user/audit.log") as f:
        assert any(pattern.match(line.rstrip("\n")) for line in f), (
            f"Missing fresh audit entry for header {header} and status {status}"
        )


def test_required_artifacts_and_real_nginx_stack():
    cgi = "/home/user/auth_filter.cgi"
    conf = "/home/user/nginx.conf"
    assert os.path.isfile(cgi), f"{cgi} does not exist or is not a regular file"
    assert os.access(cgi, os.X_OK), f"{cgi} is not executable"
    with open(cgi, "rb") as f:
        assert b"bash" in f.readline().lower(), "auth_filter.cgi is not a Bash script"
    assert os.path.isfile(conf), f"{conf} does not exist or is not a regular file"

    checked = subprocess.run(["nginx", "-T", "-c", conf], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, timeout=10)
    assert checked.returncode == 0, "nginx rejected /home/user/nginx.conf:\n" + checked.stdout
    cfg = checked.stdout
    assert re.search(r"\blisten\s+0\.0\.0\.0:8443(?:\s+[^;]*)?\bssl\b", cfg), "Missing HTTPS listen on 0.0.0.0:8443"
    assert re.search(r"\bssl_verify_client\s+on\s*;", cfg), "Client certificate verification is not enabled"
    assert re.search(r"\bauth_request\s+[^;]+;", cfg), "auth_request is not configured"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:8080\s*;", cfg), "Backend proxy_pass is missing"
    assert re.search(r"\bfastcgi_pass\s+unix:[^;]+;", cfg), "fcgiwrap UNIX socket is not configured"
    assert "/home/user/auth_filter.cgi" in cfg, "Nginx does not route FastCGI to auth_filter.cgi"

    pids = nginx_pids()
    assert pids, "No real nginx process is running"
    cmdlines = []
    for pid in pids:
        try:
            cmdlines.append(open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    assert any("/home/user/nginx.conf" in cmd for cmd in cmdlines), "Running nginx was not started with /home/user/nginx.conf"
    inodes = listening_inodes(8443)
    assert inodes and process_owns_any_socket(pids, inodes), "Port 8443 is not owned by nginx"

    fcgi_pids = subprocess.run(["pgrep", "-x", "fcgiwrap"], stdout=subprocess.PIPE, text=True)
    assert fcgi_pids.returncode == 0 and fcgi_pids.stdout.strip(), "fcgiwrap is not running"
    socket_paths = re.findall(r"\bfastcgi_pass\s+unix:([^;]+);", cfg)
    assert any(os.path.exists(path.strip()) and stat.S_ISSOCK(os.stat(path.strip()).st_mode)
               for path in socket_paths), "Configured fcgiwrap UNIX socket does not exist"


def test_server_key_permissions():
    certs_dir = "/home/user/certs"
    keys = [os.path.join(certs_dir, f) for f in os.listdir(certs_dir) if f.endswith(".key")]
    server_key = None
    for key in keys:
        if "server" in key.lower() or "localhost" in key.lower():
            server_key = key
    if not server_key:
        _, _, client_key = find_certs()
        for key in keys:
            if key != client_key:
                server_key = key
                break
    assert server_key is not None, "Could not find server private key"
    perms = stat.S_IMODE(os.stat(server_key).st_mode)
    assert perms == 0o400, f"Server key {server_key} has permissions {oct(perms)}, expected 0o400"


def test_mtls_missing_client_cert():
    try:
        resp = requests.get("https://127.0.0.1:8443/data", verify=False, timeout=2)
        assert resp.status_code == 400, "Expected 400 Bad Request for missing client cert"
    except requests.exceptions.SSLError:
        pass


def test_valid_mtls_and_jwt():
    ca_cert, client_cert, client_key = find_certs()
    assert ca_cert and client_cert and client_key, "Could not identify CA, client cert, or client key"
    header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    token = f"{header}.e30.signature"
    before = MockBackendHandler.hits
    resp = requests.get("https://127.0.0.1:8443/data",
                        headers={"Authorization": f"Bearer {token}"},
                        verify=ca_cert, cert=(client_cert, client_key), timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for valid JWT, got {resp.status_code}"
    assert resp.content == b"Backend OK" and MockBackendHandler.hits == before + 1, "Valid request was not proxied to the backend"


def test_valid_mtls_vulnerable_jwt():
    ca_cert, client_cert, client_key = find_certs()
    assert ca_cert and client_cert and client_key, "Could not identify CA, client cert, or client key"
    header = "eyJhbGciOiJub25lIn0"
    token = f"{header}.e30."
    before = MockBackendHandler.hits
    resp = requests.get("https://127.0.0.1:8443/data",
                        headers={"Authorization": f"Bearer {token}"},
                        verify=ca_cert, cert=(client_cert, client_key), timeout=5)
    assert resp.status_code == 403, f"Expected 403 Forbidden for vulnerable JWT, got {resp.status_code}"
    assert MockBackendHandler.hits == before, "Rejected none-algorithm request reached the backend"


def test_randomized_cgi_and_gateway_validation():
    ca_cert, client_cert, client_key = find_certs()
    assert ca_cert and client_cert and client_key, "Could not identify CA, client cert, or client key"
    nonce = secrets.token_hex(12)
    mixed_none = "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in "none")
    none_header = b64url({"typ": "JWT", "nonce": nonce, "alg": mixed_none})
    good_header = b64url({"nonce": nonce + "-good", "alg": "HS384", "typ": "JWT"})
    none_token = f"{none_header}.{b64url({'v': nonce})}."
    good_token = f"{good_header}.{b64url({'v': nonce})}.{secrets.token_urlsafe(9)}"

    direct_bad = run_cgi(none_token)
    assert re.search(r"(?im)^Status:\s*403\b", direct_bad.stdout), "CGI did not directly reject a randomized case-variant none algorithm"
    direct_good = run_cgi(good_token)
    assert re.search(r"(?im)^Status:\s*200\b", direct_good.stdout), "CGI did not directly allow a randomized non-none algorithm"
    assert_audit_entry(none_header, 403)
    assert_audit_entry(good_header, 200)

    # Clear direct-execution evidence, then require the live Nginx/FastCGI path to recreate it.
    with open("/home/user/audit.log", "w"):
        pass
    before = MockBackendHandler.hits
    good = requests.get("https://127.0.0.1:8443/data",
                        headers={"Authorization": "Bearer " + good_token},
                        verify=ca_cert, cert=(client_cert, client_key), timeout=5)
    assert good.status_code == 200 and good.content == b"Backend OK"
    assert MockBackendHandler.hits == before + 1, "Randomized valid token was not proxied"
    bad = requests.get("https://127.0.0.1:8443/data",
                       headers={"Authorization": "Bearer " + none_token},
                       verify=ca_cert, cert=(client_cert, client_key), timeout=5)
    assert bad.status_code == 403, "Randomized case-variant none token was not rejected"
    assert MockBackendHandler.hits == before + 1, "Randomized rejected token reached the backend"
    assert_audit_entry(good_header, 200)
    assert_audit_entry(none_header, 403)


def test_audit_log_format():
    # Exercise the original fixed cases again because the randomized test clears stale evidence.
    ca_cert, client_cert, client_key = find_certs()
    hs256_header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    none_header = "eyJhbGciOiJub25lIn0"
    requests.get("https://127.0.0.1:8443/data",
                 headers={"Authorization": f"Bearer {hs256_header}.e30.signature"},
                 verify=ca_cert, cert=(client_cert, client_key), timeout=5)
    requests.get("https://127.0.0.1:8443/data",
                 headers={"Authorization": f"Bearer {none_header}.e30."},
                 verify=ca_cert, cert=(client_cert, client_key), timeout=5)

    log_file = "/home/user/audit.log"
    assert os.path.exists(log_file), "Audit log file does not exist"
    with open(log_file) as f:
        logs = f.read().strip().split("\n")
    assert len(logs) >= 2, "Expected at least 2 audit log entries"
    found_200 = False
    found_403 = False
    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] AUDIT: Token with header ([a-zA-Z0-9\-_]+) evaluated\. Status: (\d{3})$")
    for line in logs:
        match = pattern.match(line)
        if match:
            hdr, status = match.groups()
            if hdr == hs256_header and status == "200":
                found_200 = True
            if hdr == none_header and status == "403":
                found_403 = True
    assert found_200, "Did not find expected audit log entry for valid JWT (200)"
    assert found_403, "Did not find expected audit log entry for vulnerable JWT (403)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
