#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import io
import ipaddress
import os
import shlex
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

import jwt
import paramiko
import pytest


def test_nginx_proxy_configured():
    nginx_conf = "/etc/nginx/sites-available/default"
    assert os.path.isfile(nginx_conf), f"Nginx config not found at {nginx_conf}"
    with open(nginx_conf, "r") as f:
        content = f.read()
    assert "proxy_pass" in content and "5000" in content, "Nginx is not configured to proxy to port 5000"
    result = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    assert result.returncode == 0, f"Invalid Nginx configuration: {result.stdout} {result.stderr}"


def test_flask_app_modifications():
    app_py = "/app/flask/app.py"
    assert os.path.isfile(app_py), f"Flask app not found at {app_py}"
    with open(app_py, "r") as f:
        content = f.read()
    assert "redteam_hunter_99" in content, "JWT secret 'redteam_hunter_99' not found in app.py"
    assert "paramiko" in content or "pysftp" in content or "sftp" in content.lower(), "SFTP logic not found in app.py"
    compile(content, app_py, "exec")


def test_ssh_key_generated():
    priv_key = "/home/flask_svc/.ssh/id_rsa"
    pub_key = "/home/flask_svc/.ssh/id_rsa.pub"
    auth_keys = "/home/flask_svc/.ssh/authorized_keys"

    if os.path.exists("/home/flask_svc"):
        assert os.path.isfile(priv_key), f"SSH private key not found at {priv_key}"
        assert os.path.isfile(auth_keys), f"authorized_keys not found at {auth_keys}"

    assert os.path.isfile(pub_key), f"SSH public key not found at {pub_key}"
    key = paramiko.RSAKey.from_private_key_file(priv_key)
    expected_blob = key.get_base64()
    with open(pub_key) as f:
        assert expected_blob in f.read(), "id_rsa.pub does not match id_rsa"
    with open(auth_keys) as f:
        assert expected_blob in f.read(), "The generated key is not trusted by authorized_keys"


def _packet_verdict(rules, source, in_iface, dport):
    policy = "ACCEPT"
    parsed = []
    for raw in rules.splitlines():
        if raw.startswith(":INPUT "):
            policy = raw.split()[1]
        if not raw.startswith("-A INPUT "):
            continue
        tokens = shlex.split(raw)
        rule = {"src": None, "neg_src": False, "iface": None, "proto": None,
                "ports": None, "states": None, "jump": None}
        i = 2
        negate = False
        while i < len(tokens):
            t = tokens[i]
            if t == "!":
                negate = True
                i += 1
                continue
            if t in ("-s", "--source") and i + 1 < len(tokens):
                rule["src"] = tokens[i + 1]
                rule["neg_src"] = negate
                negate = False
                i += 2
            elif t in ("-i", "--in-interface") and i + 1 < len(tokens):
                rule["iface"] = tokens[i + 1]
                i += 2
            elif t in ("-p", "--protocol") and i + 1 < len(tokens):
                rule["proto"] = tokens[i + 1]
                i += 2
            elif t in ("--dport", "--destination-port") and i + 1 < len(tokens):
                rule["ports"] = {int(tokens[i + 1])}
                i += 2
            elif t == "--dports" and i + 1 < len(tokens):
                rule["ports"] = {int(x) for x in tokens[i + 1].split(",")}
                i += 2
            elif t in ("--ctstate", "--state") and i + 1 < len(tokens):
                rule["states"] = set(tokens[i + 1].split(","))
                i += 2
            elif t in ("-j", "--jump") and i + 1 < len(tokens):
                rule["jump"] = tokens[i + 1]
                i += 2
            else:
                negate = False
                i += 1
        parsed.append(rule)

    addr = ipaddress.ip_address(source)
    for rule in parsed:
        if rule["proto"] not in (None, "all", "tcp"):
            continue
        if rule["iface"] and rule["iface"] != in_iface:
            continue
        if rule["states"] and "NEW" not in rule["states"]:
            continue
        if rule["ports"] is not None and dport not in rule["ports"]:
            continue
        if rule["src"]:
            inside = addr in ipaddress.ip_network(rule["src"], strict=False)
            if rule["neg_src"]:
                inside = not inside
            if not inside:
                continue
        if rule["jump"] in ("ACCEPT", "DROP", "REJECT"):
            return rule["jump"]
    return policy


def test_firewall_rules_saved():
    rules_file = "/home/user/firewall_rules.v4"
    assert os.path.isfile(rules_file), f"Firewall rules not saved to {rules_file}"
    with open(rules_file, "r") as f:
        content = f.read()
    assert "8080" in content, "Port 8080 not found in firewall rules"
    assert "5000" in content, "Port 5000 not found in firewall rules"
    assert "2222" in content, "Port 2222 not found in firewall rules"
    assert "DROP" in content or "REJECT" in content, "No DROP/REJECT policy found in firewall rules"

    check = subprocess.run(["iptables-restore", "--test", rules_file], capture_output=True, text=True)
    permission_error = "permission denied" in (check.stdout + check.stderr).lower()
    if not permission_error:
        assert check.returncode == 0, f"Saved firewall rules are not loadable: {check.stdout} {check.stderr}"

    assert _packet_verdict(content, "203.0.113.10", "eth0", 8080) == "ACCEPT", "Port 8080 is not open externally"
    assert _packet_verdict(content, "127.0.0.1", "lo", 5000) == "ACCEPT", "Localhost cannot reach Flask on 5000"
    assert _packet_verdict(content, "203.0.113.10", "eth0", 5000) != "ACCEPT", "Port 5000 is externally accessible"
    assert _packet_verdict(content, "127.0.0.1", "lo", 2222) == "ACCEPT", "Localhost cannot reach SFTP on 2222"
    assert _packet_verdict(content, "203.0.113.10", "eth0", 2222) != "ACCEPT", "Port 2222 is externally accessible"
    assert _packet_verdict(content, "203.0.113.10", "eth0", 4444) != "ACCEPT", "Unspecified inbound ports are not dropped"


def _run_sanitizer(filename, path="/tmp/uploads"):
    result = subprocess.run(
        ["python3", "/home/user/sanitizer.py", "--filename", filename, "--path", path],
        capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, f"Sanitizer failed for {filename!r}: {result.stderr}"
    return result.stdout.strip()


def test_sanitizer_adversarial_corpus():
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"Sanitizer script not found at {sanitizer_script}"

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_bypassed = []
    evil_total = 0
    for filename in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "r") as f:
            payloads = f.read().splitlines()
        for payload in payloads:
            if not payload.strip():
                continue
            evil_total += 1
            result = subprocess.run(
                ["python3", sanitizer_script, "--filename", payload.strip(), "--path", "/tmp"],
                capture_output=True, text=True
            )
            if "EVIL" not in result.stdout:
                evil_bypassed.append(payload.strip())

    clean_modified = []
    clean_total = 0
    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "r") as f:
            payloads = f.read().splitlines()
        for payload in payloads:
            if not payload.strip():
                continue
            clean_total += 1
            result = subprocess.run(
                ["python3", sanitizer_script, "--filename", payload.strip(), "--path", "/tmp"],
                capture_output=True, text=True
            )
            if "SAFE" not in result.stdout:
                clean_modified.append(payload.strip())

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {evil_total} evil bypassed: {evil_bypassed[:5]}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {clean_total} clean rejected: {clean_modified[:5]}")
    assert not error_msgs, " | ".join(error_msgs)


@pytest.mark.parametrize("payload", [
    "../secret.txt", "..\\secret.txt", "....//secret.txt", "foo/./bar/../../secret",
    "%2e%2e%2fsecret", "%2E%2E%5Csecret", "%252e%252e%252fsecret",
    "..%c0%afsecret", "safe.txt%00.png", "/etc/passwd", "C:\\Windows\\win.ini"
])
def test_sanitizer_hidden_evil(payload):
    assert _run_sanitizer(payload) == "EVIL"


@pytest.mark.parametrize("payload", [
    "quarterly-report.pdf", "image_01.png", "archive.tar.gz", "notes..final.txt",
    "résumé-2026.pdf", "my report (final).docx"
])
def test_sanitizer_hidden_clean(payload):
    assert _run_sanitizer(payload) == "SAFE"


def test_sanitizer_checks_target_path():
    assert _run_sanitizer("report.pdf", "/tmp/uploads/../private") == "EVIL"
    assert _run_sanitizer("report.pdf", "/tmp/uploads") == "SAFE"


def _wait_port(port, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    raise AssertionError(f"Service did not listen on port {port}")


def _multipart_request(url, filename, data, token=None):
    boundary = "----verify" + uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def _contains_token(needle):
    roots = ["/home/flask_svc", "/uploads", "/srv/sftp", "/tmp/uploads"]
    for root in roots:
        if not os.path.exists(root):
            continue
        for directory, dirs, files in os.walk(root):
            if directory.startswith("/home/flask_svc/.ssh"):
                dirs[:] = []
                continue
            for name in files:
                path = os.path.join(directory, name)
                try:
                    if os.path.getsize(path) <= 2 * 1024 * 1024:
                        with open(path, "rb") as f:
                            if needle in f.read():
                                return path
                except OSError:
                    pass
    return None


def test_services_and_end_to_end_upload():
    os.makedirs("/run/sshd", exist_ok=True)
    subprocess.run(["nginx", "-s", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "sshd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "python3 /app/flask/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    sshd = subprocess.Popen(["/usr/sbin/sshd", "-D", "-e", "-p", "2222"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    flask = None
    try:
        _wait_port(2222)

        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect("127.0.0.1", port=2222, username="flask_svc",
                       key_filename="/home/flask_svc/.ssh/id_rsa",
                       allow_agent=False, look_for_keys=False, timeout=8)
        sftp = client.open_sftp()
        probe = ".verifier-sftp-" + uuid.uuid4().hex
        with sftp.open(probe, "wb") as f:
            f.write(b"sftp operational probe")
        assert sftp.stat(probe).st_size == len(b"sftp operational probe")
        sftp.remove(probe)
        sftp.close()
        client.close()

        flask = subprocess.Popen([sys.executable, "/app/flask/app.py"], cwd="/app/flask",
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        _wait_port(5000)
        result = subprocess.run(["nginx"], capture_output=True, text=True)
        assert result.returncode == 0, f"Nginx failed to start: {result.stdout} {result.stderr}"
        _wait_port(8080)

        url = "http://127.0.0.1:8080/api/upload"
        valid = jwt.encode({"sub": "verifier", "exp": int(time.time()) + 300},
                           "redteam_hunter_99", algorithm="HS256")
        expired = jwt.encode({"sub": "verifier", "exp": int(time.time()) - 30},
                             "redteam_hunter_99", algorithm="HS256")

        status, _ = _multipart_request(url, "unauthorized.txt", b"must not upload")
        assert status in (401, 403), f"Upload without JWT was not rejected (status {status})"
        status, _ = _multipart_request(url, "expired.txt", b"must not upload", expired)
        assert status in (401, 403), f"Expired JWT was not rejected (status {status})"
        status, _ = _multipart_request(url, "../../owned.txt", b"must not upload", valid)
        assert status == 403, f"Traversal upload did not return 403 (status {status})"

        marker = ("verified-upload-" + uuid.uuid4().hex).encode()
        filename = "verified_" + uuid.uuid4().hex + ".txt"
        status, body = _multipart_request(url, filename, marker, valid)
        assert 200 <= status < 300, f"Valid upload through Nginx failed with {status}: {body!r}"
        deadline = time.time() + 8
        found = None
        while time.time() < deadline and not found:
            found = _contains_token(marker)
            if not found:
                time.sleep(0.2)
        assert found, "Successful HTTP upload was not written into the local SFTP backend"
    finally:
        subprocess.run(["nginx", "-s", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if flask is not None:
            flask.terminate()
            try:
                flask.wait(timeout=3)
            except subprocess.TimeoutExpired:
                flask.kill()
        sshd.terminate()
        try:
            sshd.wait(timeout=3)
        except subprocess.TimeoutExpired:
            sshd.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
