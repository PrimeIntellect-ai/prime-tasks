#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pathlib
import secrets
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def jwt(header, payload=None, signature=None):
    if payload is None:
        payload = {"nonce": secrets.token_hex(13)}
    if signature is None:
        signature = secrets.token_bytes(23)
    return ".".join([
        b64url(json.dumps(header, separators=(",", ":")).encode()),
        b64url(json.dumps(payload, separators=(",", ":")).encode()),
        b64url(signature),
    ])


def run_filter(script_path, token):
    random_dir = tempfile.mkdtemp(prefix="jwt-audit-", dir="/tmp")
    path = os.path.join(random_dir, secrets.token_hex(10) + ".dat")
    with open(path, "wb") as f:
        f.write(token.encode("ascii"))
    try:
        return subprocess.run(
            [script_path, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).returncode
    finally:
        try:
            os.unlink(path)
            os.rmdir(random_dir)
        except OSError:
            pass


def nginx_socket_owners(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    owners = []
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            exe = os.path.realpath(proc / "exe")
            for fd in (proc / "fd").iterdir():
                if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                    owners.append((int(proc.name), exe))
                    break
        except (OSError, PermissionError):
            continue
    return owners


def test_nginx_configuration_and_live_process():
    config = "/app/nginx.conf"
    assert os.path.isfile(config), f"Nginx configuration is missing: {config}"

    checked = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", config],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"/app/nginx.conf is not a valid Nginx configuration:\n{checked.stdout}"

    owners = nginx_socket_owners(8080)
    assert owners, "Nothing is listening on port 8080."
    assert any(os.path.basename(exe) == "nginx" for _, exe in owners), \
        f"Port 8080 is not owned by Nginx: {owners}"

    active_config_found = False
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if os.path.basename(os.path.realpath(proc / "exe")) != "nginx":
                continue
            cmdline = (proc / "cmdline").read_bytes().replace(b"\x00", b" ").decode(errors="replace")
            if "/app/nginx.conf" in cmdline:
                active_config_found = True
                break
        except (OSError, PermissionError):
            continue
    assert active_config_found, "A running Nginx process was not started with /app/nginx.conf."


def test_nginx_authorization_header():
    """Original forwarding assertion, retained."""
    url = "http://localhost:8080/api"
    test_token = "Bearer test_token_12345_secret"
    headers = {"Authorization": test_token}
    req = urllib.request.Request(url, headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200 from backend, got {response.status}"
            body = response.read().decode("utf-8")
            assert test_token in body or "test_token_12345_secret" in body, \
                "Authorization header was not found in the backend response. Nginx is likely still stripping it."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect or retrieve valid response through Nginx: {e}")


def test_nginx_forwards_random_authorization_values():
    for method in ("GET", "POST"):
        authorization = "Bearer " + secrets.token_urlsafe(35)
        marker = secrets.token_hex(17)
        data = b"probe" if method == "POST" else None
        req = urllib.request.Request(
            "http://127.0.0.1:8080/api?probe=" + secrets.token_hex(8),
            data=data,
            method=method,
            headers={"Authorization": authorization, "X-Audit-Probe": marker},
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200
            body = json.loads(response.read().decode("utf-8"))
            normalized = {str(k).lower(): v for k, v in body.items()}
            assert normalized.get("authorization") == authorization
            assert normalized.get("x-audit-probe") == marker


def test_filter_script_adversarial_corpus():
    """Original corpus assertions, retained."""
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, "No files found in evil corpus."
    assert clean_files, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []
    for filepath in evil_files:
        result = subprocess.run([script_path, filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(filepath))
    for filepath in clean_files:
        result = subprocess.run([script_path, filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(filepath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_script_randomized_and_malformed_tokens():
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path)
    assert os.access(script_path, os.X_OK)

    accepted = []
    for alg in ("HS" + str(secrets.randbelow(700) + 100), "RS" + str(secrets.randbelow(700) + 100), "EdDSA", "none-" + secrets.token_hex(4)):
        accepted.append(jwt({"typ": "JWT", "kid": secrets.token_hex(9), "alg": alg}))

    rejected = []
    for spelling in ("none", "NONE", "NoNe", "nOnE"):
        randomized = "".join(c.upper() if secrets.randbits(1) else c.lower() for c in spelling)
        rejected.append(jwt({"typ": "JWT", "alg": randomized, "nonce": secrets.token_hex(7)}))

    good = jwt({"alg": "HS512", "kid": secrets.token_hex(8)})
    parts = good.split(".")
    rejected.extend([
        parts[0] + "." + parts[1] + ".",
        parts[0] + "." + parts[1],
        "." + parts[1] + "." + parts[2],
        parts[0] + ".." + parts[2],
        good + "." + b64url(secrets.token_bytes(5)),
        parts[0] + "." + parts[1] + ".bad#signature",
        parts[0] + ".bad#payload." + parts[2],
        "bad#header." + parts[1] + "." + parts[2],
        b64url(b"not-json") + "." + parts[1] + "." + parts[2],
        b64url(json.dumps({"typ": "JWT"}).encode()) + "." + parts[1] + "." + parts[2],
        "A." + parts[1] + "." + parts[2],
    ])

    for token in accepted:
        assert run_filter(script_path, token) == 0, "A randomized valid JWT was rejected."
    for token in rejected:
        assert run_filter(script_path, token) == 1, "A randomized invalid or alg:none JWT was accepted."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
