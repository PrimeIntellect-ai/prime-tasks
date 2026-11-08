#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import re
import secrets
import socket
import subprocess
import urllib.request

import pytest


def test_diff_txt_empty():
    path = "/home/user/diff.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The task requires running the diff command and saving to this file."
    assert os.path.getsize(path) == 0, f"File {path} is not empty. This means the outputs from the Python 2 script and the Rust service did not match."


def test_rust_min_json_content():
    path = "/home/user/rust_min.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected = [
        {"id": "B1", "timestamp": 1620000100, "value": "qux"},
        {"id": "A2", "timestamp": 1620000050, "value": "bar"},
        {"id": "A1", "timestamp": 1620000000, "value": "foo"},
        {"id": "A3", "timestamp": 1619999900, "value": "baz"},
        {"id": "B2", "timestamp": 1619999800, "value": "quux"}
    ]

    assert data == expected, f"The content of {path} does not match the expected sorted data."


def test_nginx_running():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=2):
            pass
    except OSError:
        pytest.fail("Nginx does not appear to be running or bound to 127.0.0.1:8080. Ensure it was started and left running.")


def test_rust_server_running():
    try:
        with socket.create_connection(("127.0.0.1", 3000), timeout=2):
            pass
    except OSError:
        pytest.fail("Rust service does not appear to be running or bound to 127.0.0.1:3000. Ensure it was started in the background and left running.")


def _listener_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = []
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.append(pid)
                    break
        except OSError:
            continue
    return owners


def _exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def _parent(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def test_listener_processes_are_rust_binary_and_nginx():
    rust_owners = _listener_owners(3000)
    assert rust_owners, "No process owns the listening socket on port 3000."
    rust_exes = [_exe(pid) for pid in rust_owners]
    assert any(
        exe.startswith("/home/user/rust_sorter/target/")
        and os.path.basename(exe) == "rust_sorter"
        and os.path.isfile(exe)
        for exe in rust_exes
    ), f"Port 3000 is not owned by the compiled rust_sorter project binary: {rust_exes}"

    cargo = "/home/user/rust_sorter/Cargo.toml"
    assert os.path.isfile(cargo), "The Rust project is missing Cargo.toml."
    assert glob.glob("/home/user/rust_sorter/src/**/*.rs", recursive=True), "The Rust project has no Rust source files."
    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd="/home/user/rust_sorter", text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert metadata.returncode == 0, f"The Rust project is not a valid Cargo project: {metadata.stderr}"
    packages = json.loads(metadata.stdout).get("packages", [])
    assert any(p.get("name") == "rust_sorter" for p in packages), "Cargo metadata does not define the rust_sorter package."

    nginx_owners = _listener_owners(8080)
    assert nginx_owners, "No process owns the listening socket on port 8080."
    assert any(os.path.basename(_exe(pid)) == "nginx" for pid in nginx_owners), \
        f"Port 8080 is not owned by Nginx: {[_exe(pid) for pid in nginx_owners]}"

    configured = False
    for owner in nginx_owners:
        pid = owner
        for _ in range(8):
            if pid <= 1:
                break
            cmd = _cmdline(pid)
            if "nginx" in cmd and "/home/user/nginx.conf" in cmd and "-p /home/user" in cmd:
                configured = True
                break
            pid = _parent(pid)
        if configured:
            break
    assert configured, "The Nginx listener was not started with -p /home/user -c /home/user/nginx.conf."


def test_nginx_configuration():
    path = "/home/user/nginx.conf"
    assert os.path.isfile(path), "The required Nginx configuration file is missing."
    with open(path) as f:
        config = f.read()

    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", config), "Nginx must listen on 127.0.0.1:8080."
    assert re.search(r"\blocation\s+/\s*\{", config), "Nginx must define a location / block."
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:3000\s*;", config), "Nginx must proxy to the Rust service."
    assert re.search(r"\bpid\s+/home/user/[^;]+;", config), "The PID file must be under /home/user/."
    assert re.search(r"\baccess_log\s+/home/user/[^;]+", config), "The access log must be under /home/user/."
    assert re.search(r"\berror_log\s+/home/user/[^;]+", config), "The error log must be under /home/user/."
    assert re.search(r"\bdaemon\s+off\s*;", config), "Nginx daemon mode must be disabled."

    checked = subprocess.run(
        ["nginx", "-t", "-p", "/home/user", "-c", "/home/user/nginx.conf"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert checked.returncode == 0, f"The Nginx configuration is invalid: {checked.stderr}"


def _expected_from_csvs():
    rows = []
    for filepath in glob.glob("/home/user/data/*.csv"):
        with open(filepath, newline="") as f:
            for row in csv.DictReader(f):
                row["timestamp"] = int(row["timestamp"])
                rows.append(row)
    rows.sort(key=lambda row: row["timestamp"], reverse=True)
    return rows


def _get_json(url):
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=8) as response:
        assert response.status == 200, f"GET {url} returned HTTP {response.status}."
        body = response.read().decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        pytest.fail(f"GET {url} did not return valid JSON: {exc}; body={body!r}")


def test_live_process_endpoint_with_unseen_data_through_proxy():
    token = secrets.token_hex(12)
    challenge = f"/home/user/data/verifier_{token}.csv"
    rows = [
        [f"V-{token}-middle", "3920000001", f"value-{token}-a"],
        [f"V-{token}-high", "4920000002", f"value-{token}-b"],
        [f"V-{token}-low", "2920000003", f"value-{token}-c"]
    ]
    try:
        with open(challenge, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "timestamp", "value"])
            writer.writerows(rows)

        expected = _expected_from_csvs()
        direct = _get_json("http://127.0.0.1:3000/process")
        proxied = _get_json("http://127.0.0.1:8080/process")
        assert direct == expected, "The live Rust /process endpoint did not merge and sort the current CSV files correctly."
        assert proxied == expected, "The Nginx-proxied /process response did not match the derived expected output."
        assert proxied == direct, "The reverse proxy response differs from the direct Rust service response."
    finally:
        try:
            os.remove(challenge)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
