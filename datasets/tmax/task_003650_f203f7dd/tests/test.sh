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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import tempfile
import time

import pytest
import requests
from PIL import Image

BASE_URL = "http://127.0.0.1:8080"


def extract_edges_from_image():
    image = Image.open("/app/topology.png").convert("L")
    candidates = []
    for scale in (4, 6, 8):
        enlarged = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
        for threshold in (None, 180, 220):
            prepared = enlarged if threshold is None else enlarged.point(lambda p: 255 if p > threshold else 0)
            path = f"/tmp/topology_{scale}_{threshold}.png"
            prepared.save(path)
            try:
                result = subprocess.run(
                    ["tesseract", path, "stdout", "--psm", "6", "-c", "tessedit_char_whitelist=ABCDEF->"],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    timeout=10,
                    check=False,
                )
            finally:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            edges = set()
            for line in result.stdout.upper().splitlines():
                letters = re.findall(r"[A-F]", line)
                if len(letters) == 2 and letters[0] != letters[1]:
                    edges.add((letters[0], letters[1]))
            candidates.append(edges)

    edges = max(candidates, key=len)
    assert len(edges) == 7, f"Could not independently extract all seven access rules from topology.png; got {sorted(edges)}"
    return edges


EDGES = extract_edges_from_image()
NODES = sorted({node for edge in EDGES for node in edge})
assert NODES == list("ABCDEF"), f"Unexpected nodes extracted from image: {NODES}"


def listener_pid():
    socket_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                socket_inodes.add(fields[9])

    for proc_dir in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(os.path.join(proc_dir, "fd", "*")):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in socket_inodes:
                return int(proc_dir.rsplit("/", 1)[1])
    return None


def find_server_sources():
    sources = []
    for root in ("/app", "/home", "/root", "/tmp"):
        for path in glob.glob(root + "/**/*.c", recursive=True):
            try:
                text = open(path, "r", errors="ignore").read()
            except OSError:
                continue
            if all(token in text for token in ("socket", "bind", "listen", "accept")):
                sources.append(path)
    return sources


def test_c_server_artifact_exists_and_is_running():
    pid = listener_pid()
    assert pid is not None, "No process is listening specifically on 127.0.0.1:8080"

    exe = os.path.realpath(f"/proc/{pid}/exe")
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The listening server is not a native compiled executable"

    sources = find_server_sources()
    assert sources, "No C source implementing the socket HTTP server was found"

    compilation_errors = []
    compiled = False
    for source in sources:
        output = tempfile.mktemp(prefix="verified_server_", dir="/tmp")
        result = subprocess.run(
            ["gcc", "-O2", source, "-o", output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        if result.returncode == 0:
            compiled = True
            os.remove(output)
            break
        compilation_errors.append(f"{source}: {result.stderr[-500:]}")
    assert compiled, "Server C source could not be compiled:\n" + "\n".join(compilation_errors)


def expected_shortest_path(src, dst):
    adjacency = {node: [] for node in NODES}
    for a, b in EDGES:
        adjacency[a].append(b)

    queue = [[src]]
    visited = {src}
    while queue:
        path = queue.pop(0)
        current = path[-1]
        if current == dst:
            return path
        for nxt in adjacency[current]:
            if nxt not in visited:
                visited.add(nxt)
                queue.append(path + [nxt])
    return []


def request_path(src, dst):
    try:
        response = requests.get(
            f"{BASE_URL}/audit/shortest_path",
            params={"src": src, "dst": dst},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed request for {src}->{dst}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code} for {src}->{dst}"
    assert "application/json" in response.headers.get("Content-Type", "").lower(), "Expected Content-Type: application/json"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert set(data.keys()) == {"path", "length"}, f"Unexpected JSON schema: {data}"
    assert isinstance(data["path"], list), "path must be a JSON array"
    assert isinstance(data["length"], int) and not isinstance(data["length"], bool), "length must be an integer"
    return data


def check_shortest_path(src, dst, expected_length, expected_paths):
    data = request_path(src, dst)
    assert data["length"] == expected_length, f"Expected length {expected_length}, got {data['length']}"
    if expected_length == -1:
        assert data["path"] == [], f"Expected empty path, got {data['path']}"
    else:
        assert data["path"] in expected_paths, f"Expected one of {expected_paths}, got {data['path']}"


# Preserve the original verifier's exact assertions.
def test_original_fixed_cases():
    check_shortest_path("A", "F", 2, [["A", "B", "F"]])
    check_shortest_path("A", "D", 2, [["A", "E", "D"]])
    check_shortest_path("F", "A", -1, [[]])
    check_shortest_path("B", "D", 2, [["B", "C", "D"]])


def test_all_node_pairs_in_randomized_order():
    pairs = [(src, dst) for src in NODES for dst in NODES]
    random.SystemRandom().shuffle(pairs)

    for src, dst in pairs:
        expected = expected_shortest_path(src, dst)
        data = request_path(src, dst)
        if not expected:
            assert data == {"path": [], "length": -1}, f"Incorrect unreachable result for {src}->{dst}: {data}"
            continue

        path = data["path"]
        assert data["length"] == len(expected) - 1, f"Incorrect shortest length for {src}->{dst}: {data}"
        assert len(path) == data["length"] + 1, f"Path and length disagree for {src}->{dst}: {data}"
        assert path[0] == src and path[-1] == dst, f"Wrong path endpoints for {src}->{dst}: {path}"
        assert all(isinstance(node, str) and len(node) == 1 and node in NODES for node in path)
        assert all((a, b) in EDGES for a, b in zip(path, path[1:])), f"Path uses a nonexistent edge: {path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
