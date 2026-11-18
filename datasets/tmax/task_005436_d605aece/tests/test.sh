#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import shutil
import socket
import ssl
import stat
import subprocess
import time
import urllib.request
import pytest

HOME = "/home/user"
CONF = "/home/user/nginx/conf/nginx.conf"


def test_bashrc_env_vars():
    """Check that BACKEND_A and BACKEND_B are defined in .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "BACKEND_A=9001" in content.replace("export ", "").replace('"', '').replace("'", ""), "BACKEND_A=9001 not found in .bashrc"
    assert "BACKEND_B=9002" in content.replace("export ", "").replace('"', '').replace("'", ""), "BACKEND_B=9002 not found in .bashrc"


def test_ssl_cert_and_key():
    """Check that the certificate and matching key are valid RSA-2048 material for localhost."""
    cert_path = "/home/user/ssl/server.crt"
    key_path = "/home/user/ssl/server.key"

    assert os.path.isfile(cert_path), f"Certificate not found at {cert_path}"
    assert os.path.isfile(key_path), f"Key not found at {key_path}"

    subprocess.run(["openssl", "x509", "-in", cert_path, "-noout"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["openssl", "pkey", "-in", key_path, "-check", "-noout"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    subject = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"],
        text=True,
    )
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject.replace("subject=", "").strip()), subject

    details = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True)
    assert "Public Key Algorithm: rsaEncryption" in details, "Certificate key is not RSA"
    assert "Public-Key: (2048 bit)" in details, "Certificate does not use a 2048-bit key"

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", key_path, "-pubout"])
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_backends_script():
    """Check that backends.sh exists and is executable."""
    script_path = "/home/user/backends.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable by the user."


def test_nginx_conf():
    """Check that nginx.conf exists and contains required directives."""
    assert os.path.isfile(CONF), f"{CONF} does not exist."

    with open(CONF, "r") as f:
        content = f.read()

    assert "8443" in content, "Nginx does not appear to be configured to listen on port 8443."
    assert "ssl" in content.lower(), "Nginx does not appear to have SSL enabled."
    assert "client_body_temp_path" in content, "client_body_temp_path directive is missing."
    assert "proxy_temp_path" in content, "proxy_temp_path directive is missing."
    assert "fastcgi_temp_path" in content, "fastcgi_temp_path directive is missing."
    assert "uwsgi_temp_path" in content, "uwsgi_temp_path directive is missing."
    assert "scgi_temp_path" in content, "scgi_temp_path directive is missing."
    assert "user " not in content, "The 'user' directive should be omitted for unprivileged execution."

    check = subprocess.run(
        ["runuser", "-u", "user", "--", "nginx", "-p", "/home/user/nginx", "-c", "conf/nginx.conf", "-t"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    assert check.returncode == 0, f"Nginx rejected the configuration as user:\n{check.stdout}"

    dump = subprocess.check_output(
        ["runuser", "-u", "user", "--", "nginx", "-p", "/home/user/nginx", "-c", "conf/nginx.conf", "-T"],
        stderr=subprocess.STDOUT, text=True,
    )
    active = "\n".join(line.split("#", 1)[0] for line in dump.splitlines())

    assert re.search(r"\bpid\s+/home/user/nginx/nginx\.pid\s*;", active)
    assert re.search(r"\berror_log\s+/home/user/nginx/logs/error\.log(?:\s+\w+)?\s*;", active)
    assert re.search(r"\baccess_log\s+/home/user/nginx/logs/access\.log(?:\s+\w+)?\s*;", active)
    assert re.search(r"\blisten\s+[^;]*\b8443\b[^;]*\bssl\b[^;]*;", active)
    assert re.search(r"\bssl_certificate\s+/home/user/ssl/server\.crt\s*;", active)
    assert re.search(r"\bssl_certificate_key\s+/home/user/ssl/server\.key\s*;", active)

    for directive in ("client_body_temp_path", "proxy_temp_path", "fastcgi_temp_path", "uwsgi_temp_path", "scgi_temp_path"):
        pattern = rf"\b{directive}\s+/home/user/nginx/tmp/[^;\s]+(?:\s+[^;]+)?\s*;"
        assert re.search(pattern, active), f"{directive} is not under /home/user/nginx/tmp/"

    upstream_name = None
    for name, body in re.findall(r"\bupstream\s+([A-Za-z0-9_]+)\s*\{([^}}]*)\}", active, re.S):
        if re.search(r"\bserver\s+127\.0\.0\.1:9001\s*;", body) and re.search(r"\bserver\s+127\.0\.0\.1:9002\s*;", body):
            upstream_name = name
            break
    assert upstream_name, "No single round-robin upstream contains both required backends"
    assert re.search(rf"\bproxy_pass\s+http://{re.escape(upstream_name)}(?:/[^;]*)?\s*;", active), "proxy_pass does not use the required upstream"


def test_start_all_script():
    """Check that start_all.sh exists and is executable."""
    script_path = "/home/user/start_all.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable by the user."


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(int(proc.rsplit("/", 1)[1]))
    return pids


def stop_existing_listeners():
    victims = set()
    for port in (8443, 9001, 9002):
        victims.update(listener_pids(port))
    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def get_url(url):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
        return response.read().decode("utf-8").strip()


def test_integration():
    """Run the submitted artifacts unprivileged and verify real Nginx round-robin proxying."""
    stop_existing_listeners()

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "bash", "-c",
         "source /home/user/.bashrc && /home/user/start_all.sh"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
    )
    assert result.returncode == 0, f"start_all.sh failed to execute successfully:\n{result.stdout}"
    time.sleep(2)

    assert get_url("http://127.0.0.1:9001/") == "Backend A"
    assert get_url("http://127.0.0.1:9002/") == "Backend B"

    nginx_real = os.path.realpath(shutil.which("nginx"))
    tls_pids = listener_pids(8443)
    assert tls_pids, "Nothing is listening on port 8443"
    for pid in tls_pids:
        try:
            executable = os.path.realpath(f"/proc/{pid}/exe")
            uid = os.stat(f"/proc/{pid}").st_uid
        except FileNotFoundError:
            pytest.fail("The port 8443 listener exited unexpectedly")
        assert executable == nginx_real, f"Port 8443 is served by {executable}, not Nginx"
        assert uid == os.stat("/home/user").st_uid, "Nginx is not running as the unprivileged user"

    for port in (9001, 9002):
        pids = listener_pids(port)
        assert pids, f"No backend listens on port {port}"
        assert all(os.path.realpath(f"/proc/{pid}/exe") != nginx_real for pid in pids), f"Backend port {port} is incorrectly served by Nginx"

    cert_pem = subprocess.check_output(["openssl", "x509", "-in", "/home/user/ssl/server.crt", "-outform", "DER"])
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ssl._create_unverified_context().wrap_socket(raw, server_hostname="localhost") as wrapped:
            served_cert = wrapped.getpeercert(binary_form=True)
    assert hashlib.sha256(served_cert).digest() == hashlib.sha256(cert_pem).digest(), "Port 8443 is not serving server.crt"

    responses = [get_url("https://localhost:8443/") for _ in range(6)]
    assert set(responses) == {"Backend A", "Backend B"}, f"Unexpected or incomplete backend responses: {responses}"

    assert os.path.isfile("/home/user/nginx/nginx.pid"), "Configured Nginx PID file was not created"
    assert os.path.isfile("/home/user/nginx/logs/error.log"), "Configured Nginx error log was not created"
    assert os.path.isfile("/home/user/nginx/logs/access.log"), "Configured Nginx access log was not created"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
