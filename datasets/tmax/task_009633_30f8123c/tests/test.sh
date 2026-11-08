#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import socket
import ssl
import subprocess
import time
import urllib.error
import urllib.request

MAIN_GO = "/home/user/app/main.go"
MAIN_BIN = "/home/user/app/main"
NGINX_CONF = "/home/user/nginx/nginx.conf"
CRT = "/home/user/certs/server.crt"
KEY = "/home/user/certs/server.key"
MONITOR = "/home/user/monitor.sh"
USER_UID = pwd.getpwnam("user").pw_uid


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_uid(pid):
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return -1


def stop_port_processes():
    for sig in (15, 9):
        pids = listener_pids(9090) | listener_pids(8443) | listener_pids(8080)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(1)


def wait_for_services(timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids(9090) and listener_pids(8443):
            return
        time.sleep(0.25)
    raise AssertionError("monitor.sh did not start listeners on ports 9090 and 8443")


def run_monitor():
    result = run(["runuser", "-u", "user", "--", "env", "HOME=/home/user", MONITOR],
                 timeout=15)
    assert result.returncode == 0, (
        f"monitor.sh failed as the local user:\nstdout={result.stdout}\nstderr={result.stderr}"
    )


def fetch(url, tls=False):
    context = None
    if tls:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    nonce = random.SystemRandom().getrandbits(64)
    req = urllib.request.Request(f"{url}?verification={nonce}", headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, context=context, timeout=5) as response:
        return response.status, response.read().decode("utf-8")


def test_go_app_fixed_and_compiled():
    assert os.path.isfile(MAIN_GO), f"{MAIN_GO} is missing."
    with open(MAIN_GO) as f:
        content = f.read()
    assert "127.0.0.1:9090" in content, f"{MAIN_GO} does not seem to listen on 127.0.0.1:9090."
    assert "127.0.0.1:80" not in content, f"{MAIN_GO} is still trying to bind to port 80."

    assert os.path.isfile(MAIN_BIN), f"Compiled Go binary {MAIN_BIN} is missing."
    assert os.access(MAIN_BIN, os.X_OK), f"{MAIN_BIN} is not executable."
    with open(MAIN_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{MAIN_BIN} is not an ELF executable."
    metadata = run(["go", "version", "-m", MAIN_BIN])
    assert metadata.returncode == 0 and "go1" in metadata.stdout, (
        f"{MAIN_BIN} is not recognizable as a compiled Go binary."
    )


def test_tls_certs_exist():
    assert os.path.isfile(CRT), f"TLS certificate {CRT} is missing."
    assert os.path.isfile(KEY), f"TLS private key {KEY} is missing."

    cert_check = run(["openssl", "x509", "-in", CRT, "-noout", "-checkend", "0"])
    assert cert_check.returncode == 0, f"Invalid or expired TLS certificate: {cert_check.stderr}"
    key_check = run(["openssl", "rsa", "-in", KEY, "-check", "-noout"])
    assert key_check.returncode == 0, f"The private key is not a valid RSA key: {key_check.stderr}"

    cert_pub = run(["openssl", "x509", "-in", CRT, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", KEY, "-pubout"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), "TLS certificate and private key do not match."


def test_nginx_config_updated():
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} is missing."
    with open(NGINX_CONF) as f:
        content = f.read()

    assert "8080" not in content, "Nginx is still configured to listen on port 8080."
    assert "8443" in content, "Nginx is not configured to listen on port 8443."
    assert ("ssl_certificate " in content or "ssl_certificate\t" in content or
            "ssl_certificate\n" in content or "listen 8443 ssl" in content or
            "ssl " in content), "Nginx is not configured for SSL/TLS."

    checked = run(["runuser", "-u", "user", "--", "nginx", "-t", "-c", NGINX_CONF])
    assert checked.returncode == 0, f"Custom Nginx configuration is invalid: {checked.stderr}"
    dumped = run(["runuser", "-u", "user", "--", "nginx", "-T", "-c", NGINX_CONF])
    effective = dumped.stdout + dumped.stderr
    assert dumped.returncode == 0
    assert "listen 8443 ssl" in " ".join(effective.split()), "Effective config lacks an SSL listener on 8443."
    assert CRT in effective and KEY in effective, "Effective config does not use the required certificate paths."
    assert "proxy_pass http://127.0.0.1:9090" in " ".join(effective.split()), (
        "Effective config does not proxy to the Go backend."
    )


def test_monitor_script_exists_and_executable():
    assert os.path.isfile(MONITOR), f"{MONITOR} is missing."
    assert os.access(MONITOR, os.X_OK), f"{MONITOR} is not executable."


def test_monitor_starts_real_services_and_is_idempotent():
    stop_port_processes()
    assert not listener_pids(9090) and not listener_pids(8443), "Could not clear old test listeners."

    run_monitor()
    wait_for_services()

    go_pids_1 = listener_pids(9090)
    tls_pids_1 = listener_pids(8443)
    assert go_pids_1, "Nothing is listening on backend port 9090."
    assert tls_pids_1, "Nothing is listening on TLS port 8443."

    assert all(proc_exe(pid) == MAIN_BIN for pid in go_pids_1), (
        f"Port 9090 is not being served by {MAIN_BIN}: "
        f"{[(pid, proc_exe(pid)) for pid in go_pids_1]}"
    )
    assert all(proc_uid(pid) == USER_UID for pid in go_pids_1), "Go backend is not running as the local user."

    nginx_listener_pids = {pid for pid in tls_pids_1 if proc_exe(pid) == "/usr/sbin/nginx"}
    assert nginx_listener_pids, (
        f"Port 8443 is not being served by Nginx: {[(pid, proc_exe(pid)) for pid in tls_pids_1]}"
    )
    assert all(proc_uid(pid) == USER_UID for pid in tls_pids_1), "TLS service is not running as the local user."

    custom_masters_1 = {
        pid for pid in nginx_listener_pids
        if NGINX_CONF in proc_cmdline(pid) and "master process" in proc_cmdline(pid)
    }
    assert custom_masters_1, "Nginx was not started with the required custom config file."

    run_monitor()
    time.sleep(1)
    go_pids_2 = listener_pids(9090)
    custom_masters_2 = {
        pid for pid in listener_pids(8443)
        if proc_exe(pid) == "/usr/sbin/nginx"
        and NGINX_CONF in proc_cmdline(pid)
        and "master process" in proc_cmdline(pid)
    }
    assert go_pids_2 == go_pids_1, "A second monitor.sh run replaced or duplicated the Go service."
    assert custom_masters_2 == custom_masters_1, "A second monitor.sh run replaced or duplicated Nginx."
    assert not listener_pids(8080), "An HTTP service is still listening on port 8080."


def test_success_txt():
    success_file = "/home/user/success.txt"
    assert os.path.isfile(success_file), f"{success_file} is missing."
    with open(success_file) as f:
        content = f.read().strip()
    assert "Go Backend Online" in content, f"{success_file} does not contain the expected output."


def test_services_running_and_responding():
    try:
        status, body = fetch("https://127.0.0.1:8443/api", tls=True)
        assert status == 200
        assert body == "Go Backend Online", f"Expected exact API response, got {body!r}"
    except Exception as e:
        assert False, f"Failed to connect to Nginx over HTTPS or received an error: {e}"

    pem = ssl.get_server_certificate(("127.0.0.1", 8443))
    served_der = ssl.PEM_cert_to_DER_cert(pem)
    with open(CRT) as f:
        configured_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == configured_der, "Nginx is not serving the certificate from server.crt."


def test_go_backend_direct():
    try:
        status, body = fetch("http://127.0.0.1:9090/api")
        assert status == 200
        assert body == "Go Backend Online", f"Expected exact API response, got {body!r}"
    except Exception as e:
        assert False, f"Failed to connect to the Go backend or received an error: {e}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
