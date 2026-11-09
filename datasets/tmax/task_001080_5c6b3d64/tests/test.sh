#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import errno
import json
import os
import secrets
import socket
import subprocess
import sys
import time
from collections import defaultdict

from scapy.all import rdpcap, UDP

HOME = "/home/user"
CONF = os.path.join(HOME, "server_conf.json")
SERVER = os.path.join(HOME, "server.py")
REPLAY = os.path.join(HOME, "replay.py")
PCAP = os.path.join(HOME, "traffic.pcap")
OUT = os.path.join(HOME, "metrics_out.json")
PORT = 9042

# Preserve the original configuration assertions.
assert os.path.exists(CONF), f"Configuration file {CONF} does not exist."
with open(CONF, "r") as f:
    conf_data = json.load(f)
assert "port" in conf_data, f"'port' key missing in {CONF}."
assert conf_data["port"] == PORT, f"Expected port {PORT} in {CONF}, but got {conf_data['port']}."

# Preserve the original source assertion, then additionally verify that a real
# synchronization object is instantiated and actively used.
assert os.path.exists(SERVER), f"{SERVER} does not exist."
with open(SERVER, "r") as f:
    content = f.read()
assert "Lock" in content or "Semaphore" in content, (
    f"{SERVER} does not appear to use threading locks to fix the race condition."
)

tree = ast.parse(content, filename=SERVER)
constructors = {"Lock", "RLock", "Semaphore", "BoundedSemaphore"}

def expr_key(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = expr_key(node.value)
        return (base + "." if base else "") + node.attr
    return None

def assigned_targets(node):
    if isinstance(node, (ast.Name, ast.Attribute)):
        key = expr_key(node)
        return {key} if key else set()
    if isinstance(node, (ast.Tuple, ast.List)):
        result = set()
        for elt in node.elts:
            result.update(assigned_targets(elt))
        return result
    return set()

sync_objects = set()
for node in ast.walk(tree):
    value = None
    targets = []
    if isinstance(node, ast.Assign):
        value = node.value
        targets = node.targets
    elif isinstance(node, ast.AnnAssign):
        value = node.value
        targets = [node.target]
    if isinstance(value, ast.Call):
        ctor = expr_key(value.func)
        if ctor and ctor.split(".")[-1] in constructors:
            for target in targets:
                sync_objects.update(assigned_targets(target))

assert sync_objects, "server.py does not instantiate a Lock, RLock, or Semaphore."

used_as_context = False
acquired = set()
released = set()
for node in ast.walk(tree):
    if isinstance(node, (ast.With, ast.AsyncWith)):
        for item in node.items:
            if expr_key(item.context_expr) in sync_objects:
                used_as_context = True
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        owner = expr_key(node.func.value)
        if owner in sync_objects and node.func.attr == "acquire":
            acquired.add(owner)
        if owner in sync_objects and node.func.attr == "release":
            released.add(owner)

assert used_as_context or (acquired & released), (
    "A synchronization object is created but is not used as a context manager "
    "or through matching acquire/release calls."
)


def wait_for_bind(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            stdout, _ = proc.communicate()
            raise AssertionError(f"server.py exited before binding to port {PORT}:\n{stdout}")
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.bind(("127.0.0.1", PORT))
        except OSError as exc:
            if exc.errno == errno.EADDRINUSE:
                probe.close()
                return
            probe.close()
            raise
        else:
            probe.close()
        time.sleep(0.05)
    proc.kill()
    stdout, _ = proc.communicate()
    raise AssertionError(f"server.py did not bind to port {PORT}:\n{stdout}")


def start_server():
    proc = subprocess.Popen(
        [sys.executable, SERVER],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    wait_for_bind(proc)
    time.sleep(0.1)
    return proc


def wait_for_exit(proc, timeout=15):
    try:
        stdout, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, _ = proc.communicate()
        raise AssertionError(f"server.py did not exit after SHUTDOWN:\n{stdout}")
    assert proc.returncode == 0, f"server.py exited with {proc.returncode}:\n{stdout}"


def read_output():
    assert os.path.exists(OUT), (
        f"Output file {OUT} does not exist. The server may not have processed the SHUTDOWN packet."
    )
    with open(OUT, "r") as f:
        return json.load(f)


def remove_output():
    try:
        os.unlink(OUT)
    except FileNotFoundError:
        pass

# Derive the expected totals from the supplied packet capture.
pcap_expected = defaultdict(int)
for pkt in rdpcap(PCAP):
    if UDP not in pkt:
        continue
    payload = bytes(pkt[UDP].payload).strip()
    if payload == b"SHUTDOWN":
        continue
    msg = json.loads(payload.decode("utf-8"))
    pcap_expected[msg["id"]] += msg["val"]
pcap_expected = dict(pcap_expected)

# Preserve the original exact expected-state assertion as a consistency check.
expected = {
    "metric_1": 200,
    "metric_2": 200,
    "metric_3": 200,
    "metric_4": 200,
    "metric_5": 200,
}
assert pcap_expected == expected, f"Unexpected metrics encoded in traffic.pcap: {pcap_expected}"

# Delete any agent-created output, launch the submitted server, and invoke the
# required replay helper. Thus only a fresh server run can create the checked file.
remove_output()
proc = start_server()
try:
    replay = subprocess.run(
        [sys.executable, REPLAY, str(PORT)],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=15,
    )
    assert replay.returncode == 0, f"replay.py failed:\n{replay.stdout}"
    wait_for_exit(proc)
except BaseException:
    if proc.poll() is None:
        proc.kill()
        proc.communicate()
    raise

data = read_output()
assert data == expected, (
    f"Contents of {OUT} do not match the expected aggregated metrics. "
    f"Expected {expected}, but got {data}. The race condition may not be fully fixed."
)

# Exercise the same server implementation with unpredictable concurrent updates.
# Waiting before SHUTDOWN isolates aggregation synchronization from shutdown timing.
remove_output()
proc = start_server()
try:
    token = secrets.token_hex(8)
    dynamic_expected = defaultdict(int)
    payloads = []
    for i in range(75):
        metric_id = f"verify_{token}_{i % 3}"
        value = secrets.randbelow(19) + 1
        dynamic_expected[metric_id] += value
        payloads.append(json.dumps({"id": metric_id, "val": value}).encode("utf-8"))

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for payload in payloads:
        sock.sendto(payload, ("127.0.0.1", PORT))
    # A correct lock serializes the deliberately delayed updates in under one second.
    time.sleep(2.5)
    sock.sendto(b"SHUTDOWN", ("127.0.0.1", PORT))
    sock.close()
    wait_for_exit(proc)
except BaseException:
    if proc.poll() is None:
        proc.kill()
        proc.communicate()
    raise

random_data = read_output()
assert random_data == dict(dynamic_expected), (
    "The running server did not correctly aggregate concurrent, verifier-generated "
    f"inputs. Expected {dict(dynamic_expected)}, got {random_data}."
)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
