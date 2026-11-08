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
import json
import os
import random
import re
import signal
import socket
import string
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests

API_BIN = "/app/bin/api"


def wait_http(url, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=0.5)
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service at {url} did not become ready: {last_error}")


def kill_running_api():
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            executable = os.readlink(f"/proc/{entry}/exe")
        except OSError:
            continue
        if executable == API_BIN or executable == API_BIN + " (deleted)":
            try:
                os.kill(int(entry), signal.SIGTERM)
            except ProcessLookupError:
                pass

    deadline = time.time() + 3
    while time.time() < deadline:
        found = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                executable = os.readlink(f"/proc/{entry}/exe")
            except OSError:
                continue
            if executable == API_BIN or executable == API_BIN + " (deleted)":
                found = True
                break
        if not found:
            return
        time.sleep(0.1)


def start_api():
    proc = subprocess.Popen([API_BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        response = wait_http("http://127.0.0.1:8080/health", timeout=5)
        assert response.status_code == 200
    except Exception:
        proc.terminate()
        raise
    return proc


def test_integrity_txt():
    api_bin_path = "/app/bin/api"
    integrity_txt_path = "/app/integrity.txt"

    assert os.path.isfile(api_bin_path), f"Compiled binary {api_bin_path} is missing."
    assert os.path.isfile(integrity_txt_path), f"Integrity file {integrity_txt_path} is missing."

    with open(api_bin_path, "rb") as f:
        binary_data = f.read()
        actual_hash = hashlib.sha256(binary_data).hexdigest()

    with open(integrity_txt_path, "r") as f:
        raw_recorded_hash = f.read()
        recorded_hash = raw_recorded_hash.strip()

    assert recorded_hash == actual_hash, f"Hash in {integrity_txt_path} ({recorded_hash}) does not match actual hash of {api_bin_path} ({actual_hash})."
    assert re.fullmatch(r"[0-9a-f]{64}\n?", raw_recorded_hash), "integrity.txt must contain only a lowercase SHA-256 digest and an optional newline."
    assert binary_data.startswith(b"\x7fELF"), "/app/bin/api must be a compiled ELF executable."

    with open("/app/src/api.c", "r") as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert not re.search(r"\b(?:strcpy|sprintf)\s*\(", source_without_comments), "Unsafe unbounded copy/format call remains in api.c."

    rebuild = subprocess.run(["make", "-B"], cwd="/app/src", capture_output=True, text=True, timeout=30)
    assert rebuild.returncode == 0, f"Rebuilding the submitted source failed:\n{rebuild.stdout}\n{rebuild.stderr}"
    with open(api_bin_path, "rb") as f:
        rebuilt_data = f.read()
    assert rebuilt_data.startswith(b"\x7fELF"), "make did not produce an ELF executable at /app/bin/api."
    rebuilt_hash = hashlib.sha256(rebuilt_data).hexdigest()
    assert rebuilt_hash == recorded_hash, "The recorded digest does not describe the executable rebuilt from the submitted source."


def ssh_command(*extra):
    return subprocess.run(list(extra), capture_output=True, text=True, timeout=10)


def test_ssh_hardening():
    # Preserve the original root-login assertion.
    cmd_root = [
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes",
        "-i", "/app/keys/devsecops_ed25519", "-p", "2222", "root@127.0.0.1", "echo fail"
    ]
    res_root = ssh_command(*cmd_root)
    assert res_root.returncode != 0, "Root login should be disabled, but SSH command succeeded."

    # Preserve the original password-authentication assertion.
    cmd_pass_no_sshpass = [
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", "PreferredAuthentications=password",
        "-o", "BatchMode=yes", "-p", "2222", "devsecops@127.0.0.1", "echo fail"
    ]
    res_pass = ssh_command(*cmd_pass_no_sshpass)
    assert res_pass.returncode != 0, "Password authentication should be disabled."

    # Test devsecops login succeeds.
    cmd_devsecops = [
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes",
        "-i", "/app/keys/devsecops_ed25519", "-p", "2222", "devsecops@127.0.0.1", "echo success"
    ]
    res_devsecops = ssh_command(*cmd_devsecops)
    assert res_devsecops.returncode == 0, f"SSH login for devsecops failed: {res_devsecops.stderr}"
    assert "success" in res_devsecops.stdout, "SSH login for devsecops did not return expected output."

    # Verify the effective sshd policy, rather than merely looking for text in the file.
    effective = subprocess.run(
        ["/usr/sbin/sshd", "-T", "-f", "/app/sshd_config", "-C", "user=root,host=localhost,addr=127.0.0.1"],
        capture_output=True, text=True, timeout=10
    )
    assert effective.returncode == 0, f"Invalid sshd configuration: {effective.stderr}"
    values = {}
    for line in effective.stdout.splitlines():
        key, _, value = line.partition(" ")
        values.setdefault(key.lower(), []).append(value.strip())
    assert values.get("passwordauthentication") == ["no"], "Effective PasswordAuthentication must be no."
    assert values.get("permitrootlogin") == ["no"], "Effective PermitRootLogin must be no."
    assert values.get("allowusers") == ["devsecops"], "Effective AllowUsers must contain only devsecops."
    assert values.get("hostkey") == ["/app/keys/ssh_host_ed25519_key"], "Only the required Ed25519 HostKey may be active."

    # Attempt a real password exchange without BatchMode; the known setup password must not work.
    password_attempt = ssh_command(
        "sshpass", "-p", "password", "ssh",
        "-o", "StrictHostKeyChecking=no", "-o", "PubkeyAuthentication=no",
        "-o", "PreferredAuthentications=password", "-o", "NumberOfPasswordPrompts=1",
        "-p", "2222", "devsecops@127.0.0.1", "echo fail"
    )
    assert password_attempt.returncode != 0, "Password authentication is still accepted by the running daemon."

    scan = subprocess.run(
        ["ssh-keyscan", "-T", "3", "-p", "2222", "127.0.0.1"],
        capture_output=True, text=True, timeout=10
    )
    key_types = {line.split()[1] for line in scan.stdout.splitlines() if line and not line.startswith("#") and len(line.split()) >= 2}
    assert key_types == {"ssh-ed25519"}, f"Running SSH daemon exposes non-Ed25519 host keys: {key_types}"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def test_http_routing():
    try:
        response = requests.get("http://127.0.0.1:8000/api/health", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"HTTP request to Nginx failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
        assert data.get("status") == "ok", "Expected JSON response {'status':'ok'}"
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    # Replace the backend with a nonce-producing server. A canned Nginx response
    # cannot predict the nonce or report the path received by the upstream.
    kill_running_api()
    nonce = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=40))
    segment = "route-" + "".join(random.SystemRandom().choices(string.ascii_lowercase, k=16))
    query = "q=" + "".join(random.SystemRandom().choices(string.ascii_lowercase, k=12))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"nonce": nonce, "upstream_path": self.path}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = None
    thread = None
    try:
        server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        routed = requests.get(f"http://127.0.0.1:8000/api/{segment}?{query}", timeout=5)
        assert routed.status_code == 200
        routed_data = routed.json()
        assert routed_data == {"nonce": nonce, "upstream_path": f"/{segment}?{query}"}, "Nginx did not proxy /api/ to the backend root."
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=2)
        start_api()


def test_vulnerability_remediation():
    assert os.path.isfile(API_BIN)

    # Exercise the rebuilt artifact directly so Nginx cannot hide a crashing API.
    for length in (2000, 3500):
        long_user_agent = "A" * length
        headers = {"User-Agent": long_user_agent}
        try:
            direct = requests.get("http://127.0.0.1:8080/health", headers=headers, timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Rebuilt API crashed or failed directly with a {length}-byte User-Agent: {e}")
        assert direct.status_code == 200
        assert direct.json().get("status") == "ok"

        # A second request establishes that the same server survived the overflow attempt.
        survivor = requests.get("http://127.0.0.1:8080/health", timeout=5)
        assert survivor.status_code == 200
        assert survivor.json().get("status") == "ok"

    # Preserve the original routed long-header assertion.
    long_user_agent = "A" * 2000
    headers = {"User-Agent": long_user_agent}
    try:
        response = requests.get("http://127.0.0.1:8000/api/health", headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Service crashed or request failed with long User-Agent: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Service might have crashed."
    try:
        data = response.json()
        assert data.get("status") == "ok", "Expected JSON response {'status':'ok'}"
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
