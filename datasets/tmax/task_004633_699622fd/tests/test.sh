#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import signal
import socket
import ssl
import stat
import subprocess
import time
import urllib.request
import uuid

import pytest


def test_mailing_lists_permissions():
    directory = "/home/user/mailing_lists"
    assert os.path.isdir(directory), f"Directory {directory} does not exist."

    files = [f for f in os.listdir(directory) if f.endswith(".list_config")]
    assert len(files) == 4, f"Expected 4 .list_config files, found {len(files)}."

    for filename in files:
        filepath = os.path.join(directory, filename)
        st = os.stat(filepath)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o600, f"File {filepath} has incorrect permissions: {oct(perms)}. Expected 0o600."


def test_status_json_contents():
    filepath = "/home/user/status.json"
    assert os.path.isfile(filepath), f"{filepath} does not exist."

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{filepath} does not contain valid JSON.")

    expected_keys = {"alice", "bob", "charlie", "diana"}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, found {set(data.keys())}."
    assert data["alice"] == "alice@example.com", "Incorrect email for alice."
    assert data["bob"] == "bob@example.com", "Incorrect email for bob."
    assert data["charlie"] == "charlie@example.com", "Incorrect email for charlie."
    assert data["diana"] == "diana@example.com", "Incorrect email for diana."


def https_json():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://localhost:8443/status.json")
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}."
        return json.loads(response.read().decode("utf-8"))


def test_https_server_response():
    try:
        data = https_json()
        expected_keys = {"alice", "bob", "charlie", "diana"}
        assert set(data.keys()) == expected_keys, f"Server returned incorrect JSON keys: {set(data.keys())}."
    except Exception as e:
        pytest.fail(f"Failed to fetch from HTTPS server: {e}")


def python_script_pids(target):
    target = os.path.realpath(target)
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            with open(f"/proc/{pid}/stat", "r") as f:
                if f.read().split()[2] == "Z":
                    continue
            exe = os.path.basename(os.path.realpath(f"/proc/{pid}/exe"))
            if not exe.startswith("python"):
                continue
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            args = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            for arg in args:
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.realpath(candidate) == target:
                    found.add(pid)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return found


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(":", 1)[1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_processes_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode('utf-8')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run ps command: {e}")

    assert "monitor.py" in output, "monitor.py is not running in the background."
    assert "server.py" in output, "server.py is not running in the background."

    monitor_pids = python_script_pids("/home/user/monitor.py")
    server_pids = python_script_pids("/home/user/server.py")
    assert monitor_pids, "/home/user/monitor.py is not running as a Python process."
    assert server_pids, "/home/user/server.py is not running as a Python process."
    assert server_pids & listener_pids(8443), "The server.py process is not the process listening on port 8443."


def test_server_implementation_and_certificates():
    server_path = "/home/user/server.py"
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.isfile(server_path), f"{server_path} does not exist."
    assert os.path.isdir("/home/user/certs"), "/home/user/certs does not exist."
    assert os.path.isfile(cert_path), f"{cert_path} does not exist."
    assert os.path.isfile(key_path), f"{key_path} does not exist."

    try:
        tree = ast.parse(open(server_path, "r").read(), filename=server_path)
    except (OSError, SyntaxError) as e:
        pytest.fail(f"server.py is not valid readable Python: {e}")

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
    assert "http.server" in imported, "server.py must import Python's http.server module."
    assert "ssl" in imported, "server.py must import Python's ssl module."

    subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    subprocess.run(["openssl", "pkey", "-in", key_path, "-noout"],
                   check=True, input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    subprocess.run(["openssl", "verify", "-CAfile", cert_path, cert_path],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)

    cert_pub = subprocess.run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
                              check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5).stdout
    cert_pub_der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub,
                                  check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5).stdout
    key_pub_der = subprocess.run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"],
                                 check=True, input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5).stdout
    assert cert_pub_der == key_pub_der, "cert.pem and key.pem do not form a matching key pair."

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("localhost", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls:
            served_der = tls.getpeercert(binary_form=True)
    disk_der = ssl.PEM_cert_to_DER_cert(open(cert_path, "r").read())
    assert served_der == disk_der, "The HTTPS server is not using /home/user/certs/cert.pem."


def test_live_monitor_drives_served_status():
    config = "/home/user/mailing_lists/bob.list_config"
    status = "/home/user/status.json"
    monitor_pids = python_script_pids("/home/user/monitor.py")
    server_pids = python_script_pids("/home/user/server.py")
    assert monitor_pids and server_pids

    original = open(config, "r").read()
    token = f"bob-{uuid.uuid4().hex}@example.test"
    stopped = set()
    try:
        for pid in monitor_pids:
            os.kill(pid, signal.SIGSTOP)
            stopped.add(pid)

        with open(config, "w") as f:
            f.write(token + "\n")
        os.chmod(config, 0o600)

        time.sleep(3)
        with open(status, "r") as f:
            assert json.load(f).get("bob") != token, "status.json changed while all monitor.py processes were stopped."

        for pid in list(stopped):
            os.kill(pid, signal.SIGCONT)
            stopped.remove(pid)

        deadline = time.time() + 10
        observed = None
        while time.time() < deadline:
            try:
                file_data = json.load(open(status, "r"))
                served_data = https_json()
                if file_data.get("bob") == token and served_data == file_data:
                    observed = file_data
                    break
            except (OSError, ValueError, urllib.error.URLError):
                pass
            time.sleep(0.25)
        assert observed is not None, "The running monitor did not update status.json and the HTTPS response from a changed config file."
        assert monitor_pids <= python_script_pids("/home/user/monitor.py"), "monitor.py did not stay running."
        assert server_pids <= python_script_pids("/home/user/server.py"), "server.py did not stay running."
        assert server_pids & listener_pids(8443), "server.py stopped listening on port 8443."
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        with open(config, "w") as f:
            f.write(original)
        os.chmod(config, 0o600)
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                if json.load(open(status, "r")).get("bob") == original.strip():
                    break
            except (OSError, ValueError):
                pass
            time.sleep(0.25)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
