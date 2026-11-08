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
import ctypes
import json
import os
import random
import signal
import socket
import subprocess
import tempfile
import time

import pytest
import requests

URL = "http://127.0.0.1:8000/api/v1/analyze_path"


def post(payload):
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API: {exc}")
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    assert isinstance(data.get("path_exists"), bool), f"Invalid response: {data}"
    return data["path_exists"]


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if int(fields[1].rsplit(":", 1)[1], 16) == 8000 and fields[3] == "0A":
                inodes.add(fields[9])
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(name)
        except OSError:
            pass
    raise AssertionError("Could not identify the process listening on port 8000")


def test_fixture_script_exists_and_runs():
    path = "/home/user/test_fixture.py"
    assert os.path.isfile(path), f"The test fixture script at {path} is missing or not a file."
    result = subprocess.run(
        ["python3", path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"Fixture failed:\n{result.stdout}"
    assert "TEST_PASSED" in result.stdout, f"Fixture did not print TEST_PASSED:\n{result.stdout}"


def test_api_guest_pivot_denied():
    payload = {
        "nodes": {"n1": "PublicPage", "n2": "UserDashboard"},
        "edges": [["n1", "n2"]], "source": "n1", "target": "n2", "token": "GUEST"
    }
    assert post(payload) is False


def test_api_user_pivot_allowed():
    payload = {
        "nodes": {"n1": "PublicPage", "n2": "UserDashboard"},
        "edges": [["n1", "n2"]], "source": "n1", "target": "n2", "token": "USER_TOKEN"
    }
    assert post(payload) is True


def test_api_user_pivot_denied():
    payload = {
        "nodes": {"n1": "PublicPage", "n2": "UserDashboard", "n3": "AdminPanel"},
        "edges": [["n1", "n2"], ["n2", "n3"]],
        "source": "n1", "target": "n3", "token": "USER_TOKEN"
    }
    assert post(payload) is False


def test_api_superadmin_pivot_allowed():
    payload = {
        "nodes": {"n1": "PublicPage", "n2": "UserDashboard", "n3": "AdminPanel", "n4": "SecretDB"},
        "edges": [["n1", "n2"], ["n2", "n3"], ["n3", "n4"]],
        "source": "n1", "target": "n4", "token": "SUPERADMIN"
    }
    assert post(payload) is True


def test_api_complex_graph_traversal():
    payload = {
        "nodes": {
            "start": "PublicPage", "mid1": "AdminPanel",
            "mid2": "UserDashboard", "end": "PublicPage"
        },
        "edges": [
            ["start", "mid1"], ["mid1", "end"],
            ["start", "mid2"], ["mid2", "end"]
        ],
        "source": "start", "target": "end", "token": "USER_TOKEN"
    }
    assert post(payload) is True


def read_process_state(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [x.decode(errors="surrogateescape") for x in f.read().split(b"\0") if x]
    with open(f"/proc/{pid}/environ", "rb") as f:
        env_items = [x for x in f.read().split(b"\0") if x]
    env = {}
    for item in env_items:
        key, sep, value = item.partition(b"=")
        if sep:
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    return argv, env, cwd


def wait_for_port(timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("Restarted service did not listen on 127.0.0.1:8000")


def expected_path(payload, validate):
    nodes = payload["nodes"]
    target = payload["target"]
    seen = {payload["source"]}
    queue = [payload["source"]]
    adjacency = {}
    for a, b in payload["edges"]:
        adjacency.setdefault(a, []).append(b)
    while queue:
        current = queue.pop(0)
        if current == target:
            return True
        for nxt in adjacency.get(current, []):
            if nxt in seen:
                continue
            allowed = validate(
                nodes[current].encode(), nodes[nxt].encode(), payload["token"].encode()
            )
            if allowed == 1:
                seen.add(nxt)
                queue.append(nxt)
    return False


def test_service_uses_legacy_library_and_general_graph_traversal():
    pid = listener_pid()
    maps = open(f"/proc/{pid}/maps", errors="replace").read()
    cmdline = open(f"/proc/{pid}/cmdline", "rb").read().lower()
    assert b"python" in cmdline, "The listener is not a Python service"
    assert "/app/libsec_eval.so" in maps, "The service has not loaded /app/libsec_eval.so"
    argv, env, cwd = read_process_state(pid)
    assert argv, "Could not determine the service command"

    challenge_c = r'''
#include <stdint.h>
static uint64_t add(uint64_t h, const char *s) {
    while (*s) { h ^= (unsigned char)*s++; h *= UINT64_C(1099511628211); }
    h ^= 255; h *= UINT64_C(1099511628211);
    return h;
}
int validate_transition(const char *a, const char *b, const char *t) {
    uint64_t h = UINT64_C(1469598103934665603);
    h = add(h, a); h = add(h, b); h = add(h, t);
    return ((h ^ (h >> 17) ^ (h >> 41)) % 7) < 3;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "challenge.c")
        out = os.path.join(td, "libsec_eval.so")
        with open(src, "w") as f:
            f.write(challenge_c)
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", src, "-o", out],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )

        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 3
        while time.time() < deadline and os.path.exists(f"/proc/{pid}"):
            time.sleep(0.05)
        if os.path.exists(f"/proc/{pid}"):
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)

        os.replace(out, "/app/libsec_eval.so")
        proc = subprocess.Popen(
            argv, cwd=cwd, env=env, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )

    try:
        wait_for_port()
        new_pid = listener_pid()
        new_maps = open(f"/proc/{new_pid}/maps", errors="replace").read()
        assert "/app/libsec_eval.so" in new_maps, "Restarted service did not load the supplied library"

        lib = ctypes.CDLL("/app/libsec_eval.so")
        validate = lib.validate_transition
        validate.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
        validate.restype = ctypes.c_int

        rng = random.Random(927451)
        alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        def word(prefix):
            return prefix + "_" + "".join(rng.choice(alphabet) for _ in range(11))

        # Direct edges use unpredictable types and tokens and prove transition
        # answers come from the currently supplied shared object.
        for i in range(24):
            payload = {
                "nodes": {word("from"): word("TypeA"), word("to"): word("TypeB")},
                "edges": [], "token": word("Token")
            }
            ids = list(payload["nodes"])
            payload["source"], payload["target"] = ids
            payload["edges"] = [[ids[0], ids[1]]]
            assert post(payload) is expected_path(payload, validate), f"Direct challenge case {i} failed"

        # Random cyclic and branching graphs verify actual reachability rather
        # than a decision based only on token or target resource type.
        for case in range(30):
            count = rng.randint(4, 10)
            ids = [word(f"node{i}") for i in range(count)]
            nodes = {node: word(f"Resource{i}") for i, node in enumerate(ids)}
            edges = []
            for a in ids:
                for b in ids:
                    if a != b and rng.random() < 0.23:
                        edges.append([a, b])
            payload = {
                "nodes": nodes,
                "edges": edges,
                "source": ids[rng.randrange(count)],
                "target": ids[rng.randrange(count)],
                "token": word("Auth")
            }
            expected = expected_path(payload, validate)
            assert post(payload) is expected, f"Random graph challenge case {case} failed"
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
