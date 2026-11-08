#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import subprocess
import time

import pytest
import requests

NODES = {
    8081: "/home/user/data/node1",
    8082: "/home/user/data/node2",
    8083: "/home/user/data/node3",
}


def clear_nodes():
    for directory in NODES.values():
        os.makedirs(directory, exist_ok=True)
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def find_payload(directory, payload):
    for root, _, files in os.walk(directory):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.getsize(path) == len(payload):
                    with open(path, "rb") as f:
                        if f.read() == payload:
                            return True
            except OSError:
                pass
    return False


def listening_socket_owners():
    port_inodes = {port: set() for port in (8080, 8081, 8082, 8083)}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    port = int(fields[1].split(":")[1], 16)
                    if port in port_inodes:
                        port_inodes[port].add(fields[9])
        except FileNotFoundError:
            pass

    owners = {port: set() for port in port_inodes}
    wanted = {inode: port for port, inodes in port_inodes.items() for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:["):
                    inode = target[8:-1]
                    if inode in wanted:
                        owners[wanted[inode]].add(int(entry))
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def operator_is_running():
    expected = os.path.realpath("/home/user/operator.py")
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [a.decode(errors="replace") for a in raw.split(b"\0") if a]
            cwd = os.readlink(f"/proc/{entry}/cwd")
        except (OSError, PermissionError):
            continue
        for arg in args:
            if arg.endswith("operator.py"):
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.realpath(candidate) == expected:
                    return True
    return False


def post(url, payload, timeout=3):
    return requests.post(
        url,
        data=payload,
        headers={"Connection": "close", "Content-Type": "application/octet-stream"},
        timeout=timeout,
    )


def test_required_components_and_behavior():
    assert os.path.isfile("/home/user/operator.py"), "Missing /home/user/operator.py"
    assert os.path.getsize("/home/user/operator.py") > 0, "operator.py is empty"
    assert os.path.isfile("/home/user/fstab_sim"), "Missing /home/user/fstab_sim"

    with open("/home/user/fstab_sim", errors="replace") as f:
        fstab = f.read()
    for port, directory in NODES.items():
        assert directory in fstab, f"fstab_sim does not list {directory}"
        assert str(port) in fstab, f"fstab_sim does not list port {port}"
    assert "50" in fstab or "52428800" in fstab, "fstab_sim does not describe the 50MB quotas"

    assert operator_is_running(), "operator.py is not running as a continuous controller"

    owners = listening_socket_owners()
    for port in owners:
        assert owners[port], f"No process is listening on required port {port}"
    backend_ports = (8081, 8082, 8083)
    for i, left in enumerate(backend_ports):
        for right in backend_ports[i + 1:]:
            assert owners[left].isdisjoint(owners[right]), \
                "Backend ports are not served by three separate backend instances"
    for port in backend_ports:
        assert owners[8080].isdisjoint(owners[port]), \
            "Port 8080 is not a separate reverse-proxy service"

    clear_nodes()

    # Exercise each backend directly and derive the expected stored body ourselves.
    for port, directory in NODES.items():
        payload = (f"direct-backend-{port}-" + os.urandom(16).hex()).encode()
        response = post(f"http://127.0.0.1:{port}/upload", payload)
        assert response.status_code == 200, f"Backend {port} did not return 200"
        deadline = time.time() + 2
        while time.time() < deadline and not find_payload(directory, payload):
            time.sleep(0.05)
        assert find_payload(directory, payload), \
            f"Backend {port} did not store the upload in {directory}"

    # Verify that the port-8080 service sends real uploads across all backends.
    clear_nodes()
    proxy_payloads = []
    for i in range(18):
        payload = (f"proxy-distribution-{i}-" + os.urandom(20).hex()).encode()
        response = post("http://127.0.0.1:8080/upload", payload)
        assert response.status_code == 200, "Reverse proxy upload did not return 200"
        proxy_payloads.append(payload)

    hit_nodes = set()
    for payload in proxy_payloads:
        locations = [directory for directory in NODES.values() if find_payload(directory, payload)]
        assert locations, "Port 8080 returned 200 without storing the uploaded body on a backend"
        hit_nodes.update(locations)
    assert hit_nodes == set(NODES.values()), \
        f"Reverse proxy did not load balance across all three backends; observed {hit_nodes}"

    # Put node1 above the 40MB eviction threshold without exceeding its 50MB quota.
    clear_nodes()
    filler = "/home/user/data/node1/verifier_threshold_filler"
    with open(filler, "wb") as f:
        f.truncate(41 * 1024 * 1024)

    # A controller fast enough for the supplied adversarial generator must notice promptly.
    time.sleep(4)
    eviction_payloads = []
    for i in range(18):
        payload = (f"after-eviction-{i}-" + os.urandom(32768 - 40)).encode()
        response = post("http://127.0.0.1:8080/upload", payload)
        assert response.status_code == 200, "Proxy dropped/failed a request after node eviction"
        eviction_payloads.append(payload)

    for payload in eviction_payloads:
        assert not find_payload(NODES[8081], payload), \
            "The proxy continued routing new uploads to node1 above the 40MB threshold"
        assert find_payload(NODES[8082], payload) or find_payload(NODES[8083], payload), \
            "A successful post-eviction upload was not stored by an eligible backend"


def test_traffic_gen_success_rate():
    """Retain the original adversarial traffic-generator assertion."""
    binary_path = "/app/traffic_gen"
    assert os.path.isfile(binary_path), f"Traffic generator binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Traffic generator binary at {binary_path} is not executable"

    target_url = "http://127.0.0.1:8080"
    res = subprocess.run(
        [binary_path, "--target", target_url],
        capture_output=True,
        text=True,
        timeout=30,
    )

    try:
        lines = [line.strip() for line in res.stdout.splitlines() if line.strip()]
        assert len(lines) > 0, "Traffic generator produced no stdout."
        output = json.loads(lines[-1])
        rate = float(output["success_rate"])
        assert rate >= 0.95, f"Success rate {rate} is below the required threshold of 0.95"
    except Exception as e:
        raise AssertionError(
            f"Verification failed: {e}\nStdout: {res.stdout}\nStderr: {res.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
