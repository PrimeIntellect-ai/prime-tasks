#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import json
import os
import subprocess
import urllib.error
import urllib.request

import pytest

NODES_DIR = "/home/user/math_nodes"
API_URL = "http://127.0.0.1:8080/build_order"
PROXY_URL = "http://127.0.0.1:9000/api/v1/build_order"


def fetch_json(url):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            content_type = response.headers.get("Content-Type", "")
            assert "application/json" in content_type, (
                f"Expected Content-Type application/json, got {content_type}"
            )
            data = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")

    try:
        return json.loads(data)
    except json.JSONDecodeError:
        pytest.fail(f"Response from {url} is not valid JSON: {data}")


def expected_order(graph):
    remaining = {name: set(deps) for name, deps in graph.items()}
    ready = sorted(name for name, deps in remaining.items() if not deps)
    result = []

    while ready:
        node = ready.pop(0)
        result.append(node)
        for name in sorted(remaining):
            if node in remaining[name]:
                remaining[name].remove(node)
                if not remaining[name] and name not in result and name not in ready:
                    ready.append(name)
        ready.sort()

    assert len(result) == len(graph), "Verifier fixture unexpectedly contains a cycle"
    return result


@contextlib.contextmanager
def temporary_graph(graph):
    original = {
        name: open(os.path.join(NODES_DIR, name), "rb").read()
        for name in os.listdir(NODES_DIR)
        if name.endswith(".txt")
    }
    try:
        for name in os.listdir(NODES_DIR):
            if name.endswith(".txt"):
                os.unlink(os.path.join(NODES_DIR, name))
        for module, dependencies in graph.items():
            path = os.path.join(NODES_DIR, module + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(",".join(dependencies))
        yield
    finally:
        for name in os.listdir(NODES_DIR):
            if name.endswith(".txt"):
                os.unlink(os.path.join(NODES_DIR, name))
        for name, contents in original.items():
            with open(os.path.join(NODES_DIR, name), "wb") as handle:
                handle.write(contents)


def test_nginx_proxy_returns_correct_build_order():
    expected = ["D", "B", "E", "C", "A"]
    assert fetch_json(PROXY_URL) == expected


def test_api_server_returns_correct_build_order():
    expected = ["D", "B", "E", "C", "A"]
    assert fetch_json(API_URL) == expected


def test_nginx_config_exists():
    config_path = "/home/user/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx configuration file missing at {config_path}"


def test_services_recompute_multiple_changed_graphs():
    fixtures = [
        {
            "Quartz": [],
            "Beta": [],
            "Alpha": ["Beta"],
            "Gamma": ["Beta"],
            "Delta": ["Alpha", "Gamma"],
        },
        {
            "Z": ["M", "A"],
            "M": ["A"],
            "A": [],
            "B": [],
            "C": ["B"],
        },
    ]

    for graph in fixtures:
        expected = expected_order(graph)
        with temporary_graph(graph):
            assert fetch_json(API_URL) == expected
            assert fetch_json(PROXY_URL) == expected


def nginx_owns_proxy_listener():
    listening_inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address_hex, port_hex = local_address.split(":")
            if address_hex == "0100007F" and int(port_hex, 16) == 9000 and state == "0A":
                listening_inodes.add(inode)

    if not listening_inodes:
        return False

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in listening_inodes for link in links):
            continue
        try:
            executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if executable == "nginx":
            return True
    return False


def test_real_nginx_configuration_and_listener():
    result = subprocess.run(
        ["nginx", "-t", "-c", "/home/user/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Invalid Nginx configuration:\n{result.stdout}"
    assert nginx_owns_proxy_listener(), "Port 9000 is not owned by a running Nginx process"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
