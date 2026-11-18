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
import csv
import glob
import heapq
import os
import signal
import subprocess
import tempfile
import time
import uuid
from functools import lru_cache

import requests

URL = "http://127.0.0.1:8080/shortest_path"
HEADERS = {"Authorization": "Token research-2024"}
PROJECT = "/home/user/graph_api"


@lru_cache(maxsize=1)
def video_edges():
    """Independently derive the expected graph from the supplied video."""
    records = set()
    with tempfile.TemporaryDirectory() as directory:
        pattern = os.path.join(directory, "frame_%04d.png")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i",
             "/app/dataset_log.mp4", "-vf", "fps=2", pattern],
            check=True,
            timeout=60,
        )
        frames = sorted(glob.glob(os.path.join(directory, "frame_*.png")))
        assert frames, "ffmpeg did not extract any frames from the video"
        for frame in frames:
            result = subprocess.run(
                ["zbarimg", "--quiet", frame],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            for line in result.stdout.splitlines():
                payload = line.split(":", 1)[-1].strip()
                if not payload.startswith("GRAPH_EDGE;"):
                    continue
                parts = payload.split(";")
                assert len(parts) == 4, f"Malformed graph record in QR code: {payload}"
                records.add((parts[1], parts[2], int(parts[3])))
    assert records, "No GRAPH_EDGE QR records could be extracted from the video"
    return records


def parse_csv(path):
    edges = []
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if not row or all(not value.strip() for value in row):
                continue
            if len(row) != 3:
                return None
            source, target, weight = (value.strip() for value in row)
            try:
                weight = int(weight)
            except ValueError:
                if not edges and "weight" in weight.lower():
                    continue
                return None
            edges.append((source, target, weight))
    return edges


@lru_cache(maxsize=1)
def matching_csv_files():
    expected = video_edges()
    candidates = []
    for root in ("/home/user", "/app"):
        for path in glob.glob(root + "/**/*.csv", recursive=True):
            try:
                parsed = parse_csv(path)
            except (OSError, UnicodeError):
                continue
            if parsed is not None and len(parsed) == len(expected) and set(parsed) == expected:
                candidates.append(path)
    assert candidates, "No clean CSV containing the QR-derived graph was found"
    return candidates


def expected_shortest_paths(edges):
    adjacency = {}
    nodes = set()
    for source, target, weight in edges:
        adjacency.setdefault(source, []).append((target, weight))
        nodes.update((source, target))

    answers = {}
    for start in nodes:
        queue = [(0, (start,), start)]
        best = {start: 0}
        while queue:
            distance, path, node = heapq.heappop(queue)
            if distance != best[node]:
                continue
            answers[(start, node)] = (list(path), distance)
            for target, weight in adjacency.get(node, []):
                candidate = distance + weight
                if candidate < best.get(target, float("inf")):
                    best[target] = candidate
                    heapq.heappush(queue, (candidate, path + (target,), target))
    return nodes, answers


def port_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(os.path.basename(proc))
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def test_service_ready_log():
    log_path = "/home/user/service_ready.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"
    with open(log_path, "r") as handle:
        content = handle.read()
    assert "SERVICE_UP" in content, f"Log file does not contain 'SERVICE_UP', found: {content}"


def test_rust_project_and_extracted_csv_exist():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Rust Cargo.toml is missing"
    rust_sources = glob.glob(os.path.join(PROJECT, "**", "*.rs"), recursive=True)
    assert rust_sources, "No Rust source files were found in /home/user/graph_api"
    assert all(os.path.getsize(path) > 0 for path in rust_sources), "A Rust source file is empty"
    matching_csv_files()


def test_shortest_path_a_to_e():
    payload = {"start_node": "A", "end_node": "E"}
    try:
        response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as error:
        assert False, f"Failed to connect to the service: {error}"

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"
    assert "path" in data, "Response JSON missing 'path' key"
    assert "total_weight" in data, "Response JSON missing 'total_weight' key"
    assert data["path"] == ["A", "B", "C", "D", "E"], f"Incorrect path, got: {data['path']}"
    assert data["total_weight"] == 25, f"Incorrect total weight, got: {data['total_weight']}"


def test_unauthorized_access():
    payload = {"start_node": "A", "end_node": "B"}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as error:
        assert False, f"Failed to connect to the service: {error}"
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"

    response = requests.post(
        URL,
        json=payload,
        headers={"Authorization": "Token incorrect"},
        timeout=5,
    )
    assert response.status_code == 401, f"Incorrect token should return 401, got {response.status_code}"


def test_no_path_exists():
    payload = {"start_node": "E", "end_node": "A"}
    try:
        response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as error:
        assert False, f"Failed to connect to the service: {error}"
    assert response.status_code == 404, f"Expected 404 Not Found, got {response.status_code}. Response: {response.text}"
    assert response.json() == {"error": "No path exists"}


def test_all_video_graph_queries():
    edges = video_edges()
    nodes, answers = expected_shortest_paths(edges)
    for start in sorted(nodes):
        for end in sorted(nodes):
            if start == end:
                continue
            response = requests.post(
                URL,
                json={"start_node": start, "end_node": end},
                headers=HEADERS,
                timeout=5,
            )
            expected = answers.get((start, end))
            if expected is None:
                assert response.status_code == 404, (
                    f"Expected no path for {start}->{end}, got {response.status_code}: {response.text}"
                )
                assert response.json() == {"error": "No path exists"}
            else:
                assert response.status_code == 200, (
                    f"Expected a path for {start}->{end}, got {response.status_code}: {response.text}"
                )
                data = response.json()
                assert set(data) == {"path", "total_weight"}, f"Incorrect response schema: {data}"
                assert data["path"] == expected[0], f"Wrong path for {start}->{end}: {data}"
                assert data["total_weight"] == expected[1], f"Wrong weight for {start}->{end}: {data}"


def test_z_service_reloads_modified_csv_in_rust():
    """Restart via Cargo and use unpredictable CSV data to reject hardcoded servers."""
    source = "Verify_" + uuid.uuid4().hex
    target = "Verify_" + uuid.uuid4().hex
    weight = 100 + (uuid.uuid4().int % 900)

    csv_paths = matching_csv_files()
    for path in csv_paths:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{source},{target},{weight}\n")

    old_pids = port_pids()
    assert old_pids, "No process is listening on port 8080"
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in port_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    process = subprocess.Popen(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    response = None
    deadline = time.time() + 60
    try:
        while time.time() < deadline:
            if process.poll() is not None:
                output = process.stdout.read()
                assert False, f"cargo run exited before serving requests:\n{output}"
            try:
                response = requests.post(
                    URL,
                    json={"start_node": source, "end_node": target},
                    headers=HEADERS,
                    timeout=1,
                )
                if response.status_code == 200:
                    break
            except requests.exceptions.RequestException:
                pass
            time.sleep(0.25)

        assert response is not None and response.status_code == 200, (
            "The Cargo-launched service did not answer a query added to the CSV"
        )
        assert response.json() == {"path": [source, target], "total_weight": weight}

        listeners = port_pids()
        assert listeners, "No listener remained on port 8080"
        executables = []
        for pid in listeners:
            try:
                executables.append(os.path.realpath(f"/proc/{pid}/exe"))
            except OSError:
                pass
        target_dir = os.path.realpath(os.path.join(PROJECT, "target")) + os.sep
        assert any(executable.startswith(target_dir) for executable in executables), (
            f"Port 8080 is not owned by the compiled Rust project: {executables}"
        )
    finally:
        if process.poll() is None:
            process.terminate()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
