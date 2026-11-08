#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import secrets
import socket
import subprocess
import threading
import time
from collections import defaultdict, deque

import pytest

APP_DIR = "/home/user/app"
CLEAN_CORPUS_DIR = os.path.join(APP_DIR, "clean_corpus")
EVIL_CORPUS_DIR = os.path.join(APP_DIR, "evil_corpus")
FILTER_SERVICE_DIR = os.path.join(APP_DIR, "filter_service")
VERIFIER_SCRIPT = os.path.join(APP_DIR, "verifier.py")


def test_rust_project_exists():
    assert os.path.isdir(FILTER_SERVICE_DIR), f"Rust project directory missing: {FILTER_SERVICE_DIR}"
    cargo_toml = os.path.join(FILTER_SERVICE_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing in {FILTER_SERVICE_DIR}"
    main_rs = os.path.join(FILTER_SERVICE_DIR, "src", "main.rs")
    assert os.path.isfile(main_rs), f"main.rs missing in {FILTER_SERVICE_DIR}/src/"


def test_verifier_script_passes():
    assert os.path.isfile(VERIFIER_SCRIPT), f"Verifier script missing: {VERIFIER_SCRIPT}"
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert len(clean_files) > 0, "No clean CSV files found."
    assert len(evil_files) > 0, "No evil CSV files found."

    try:
        result = subprocess.run(
            ["python3", VERIFIER_SCRIPT],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Verifier script timed out after 60 seconds.")

    if result.returncode != 0:
        pytest.fail(
            f"Verifier script failed with return code {result.returncode}.\n"
            f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
        )


def write_csv(path, edges):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target", "weight"])
        writer.writerows(edges)


def expected_unweighted_distances(path):
    graph = defaultdict(list)
    nodes = set()
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            source = row["source"]
            target = row["target"]
            graph[source].append(target)
            nodes.add(source)
            nodes.add(target)

    if "0" not in nodes:
        return {}

    distances = {"0": 0}
    queue = deque(["0"])
    while queue:
        source = queue.popleft()
        for target in graph[source]:
            if target not in distances:
                distances[target] = distances[source] + 1
                queue.append(target)
    return distances


def find_binary():
    try:
        build = subprocess.run(
            ["cargo", "build", "--quiet"],
            cwd=FILTER_SERVICE_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("cargo build timed out")
    assert build.returncode == 0, f"cargo build failed:\n{build.stdout}\n{build.stderr}"

    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version=1"],
        cwd=FILTER_SERVICE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata.returncode == 0, f"cargo metadata failed: {metadata.stderr}"
    data = json.loads(metadata.stdout)
    bins = []
    for package in data["packages"]:
        for target in package["targets"]:
            if "bin" in target.get("kind", []):
                bins.append(os.path.join(data["target_directory"], "debug", target["name"]))
    assert bins, "Cargo project has no binary target"
    binary = bins[0]
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), f"Built binary missing: {binary}"
    return binary


def run_pipeline(binary, paths):
    emitter = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sink = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    for server in (emitter, sink):
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        emitter.bind(("127.0.0.1", 8001))
        sink.bind(("127.0.0.1", 8002))
    except OSError as exc:
        emitter.close()
        sink.close()
        pytest.fail(f"Could not bind verifier service ports: {exc}")
    emitter.listen(5)
    sink.listen(5)
    emitter.settimeout(15)
    sink.settimeout(0.25)

    received = bytearray()
    errors = []
    stop_sink = threading.Event()

    def emit_paths():
        try:
            connection, _ = emitter.accept()
            with connection:
                payload = "".join(path + "\n" for path in paths).encode()
                connection.sendall(payload)
                connection.shutdown(socket.SHUT_WR)
        except Exception as exc:
            errors.append(f"emitter failed: {exc}")
        finally:
            emitter.close()

    def receive_results():
        try:
            while not stop_sink.is_set():
                try:
                    connection, _ = sink.accept()
                except socket.timeout:
                    continue
                with connection:
                    connection.settimeout(0.5)
                    while True:
                        try:
                            chunk = connection.recv(65536)
                        except socket.timeout:
                            if stop_sink.is_set():
                                break
                            continue
                        if not chunk:
                            break
                        received.extend(chunk)
        except Exception as exc:
            errors.append(f"sink failed: {exc}")
        finally:
            sink.close()

    emitter_thread = threading.Thread(target=emit_paths, daemon=True)
    sink_thread = threading.Thread(target=receive_results, daemon=True)
    emitter_thread.start()
    sink_thread.start()

    process = subprocess.Popen(
        [binary],
        cwd=FILTER_SERVICE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=40)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
        stop_sink.set()
        pytest.fail(f"Rust service timed out.\nStdout:\n{stdout}\nStderr:\n{stderr}")
    finally:
        stop_sink.set()

    emitter_thread.join(timeout=3)
    sink_thread.join(timeout=3)
    assert not emitter_thread.is_alive(), "Data emitter was never consumed"
    assert not sink_thread.is_alive(), "Data sink did not shut down"
    assert not errors, "; ".join(errors)
    assert process.returncode == 0, (
        f"Rust service exited with {process.returncode}.\nStdout:\n{stdout}\nStderr:\n{stderr}"
    )

    records = []
    text = received.decode("utf-8")
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Sink received invalid JSON on line {line_number}: {line!r}: {exc}")
        assert isinstance(value, dict), f"Sink JSON line is not an object: {value!r}"
        assert {"file", "node", "distance", "rank"}.issubset(value), (
            f"Sink record lacks required fields: {value!r}"
        )
        records.append(value)
    return records, stdout


def validate_clean_file(path, records):
    expected = expected_unweighted_distances(path)
    file_records = [record for record in records if record.get("file") == path]
    by_node = defaultdict(list)
    for record in file_records:
        by_node[str(record["node"])].append(record)

    # The wording permits omitting the origin itself, but every other reachable node is required.
    required_nodes = set(expected) - {"0"}
    assert required_nodes.issubset(by_node), (
        f"Missing reachable nodes for {path}: {sorted(required_nodes - set(by_node))}"
    )
    assert set(by_node).issubset(set(expected)), f"Unreachable nodes emitted for {path}"
    assert set(by_node) in (required_nodes, set(expected)), (
        f"Unexpected node set for {path}: {sorted(by_node)}"
    )

    for node, node_records in by_node.items():
        assert len(node_records) == 1, f"Duplicate result for {path}, node {node}"
        record = node_records[0]
        assert isinstance(record["distance"], (int, float)) and not isinstance(record["distance"], bool)
        assert record["distance"] == expected[node], (
            f"Wrong distance for {path}, node {node}: {record['distance']} != {expected[node]}"
        )
        assert isinstance(record["rank"], int) and not isinstance(record["rank"], bool)

    ordered_distances = sorted({expected[node] for node in by_node})
    rank_for_distance = {}
    for node, node_records in by_node.items():
        distance = expected[node]
        rank = node_records[0]["rank"]
        if distance in rank_for_distance:
            assert rank_for_distance[distance] == rank, f"Equal distances have different ranks in {path}"
        else:
            rank_for_distance[distance] = rank
    assert [rank_for_distance[d] for d in ordered_distances] == list(range(1, len(ordered_distances) + 1)), (
        f"Ranks are not a dense ascending rank for {path}: {rank_for_distance}"
    )


def test_filter_service_end_to_end():
    clean_files = sorted(glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv")))
    evil_files = sorted(glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv")))
    assert clean_files, "No clean CSV files found."
    assert evil_files, "No evil CSV files found."

    case_dir = os.path.join("/tmp", "filter_cases_" + secrets.token_hex(8))
    os.makedirs(case_dir)
    suffix = secrets.randbelow(100000) + 300000

    dynamic_clean = os.path.join(case_dir, "clean_" + secrets.token_hex(5) + ".csv")
    a, b, c, d, e = [str(suffix + i) for i in range(5)]
    write_csv(dynamic_clean, [
        ("0", a, 1), ("0", b, 1), (a, c, 1), (b, c, 1),
        (c, d, 1), (b, e, 1),
    ])

    # Four sources with ten identical targets is just below the rejection threshold.
    near_threshold = os.path.join(case_dir, "near_" + secrets.token_hex(5) + ".csv")
    targets = [str(suffix + 100 + i) for i in range(10)]
    sources = ["0"] + [str(suffix + 200 + i) for i in range(3)]
    write_csv(near_threshold, [(source, target, 1) for source in sources for target in targets])

    dynamic_evil = os.path.join(case_dir, "evil_" + secrets.token_hex(5) + ".csv")
    evil_sources = [str(suffix + 300 + i) for i in range(5)]
    evil_targets = [str(suffix + 400 + i) for i in range(10)]
    evil_edges = [(source, target, 1) for source in evil_sources for target in evil_targets]
    # Include node 0 so an implementation that fails to reject would visibly emit analytics.
    evil_edges.append(("0", evil_sources[0], 1))
    write_csv(dynamic_evil, evil_edges)

    all_clean = clean_files + [dynamic_clean, near_threshold]
    all_evil = evil_files + [dynamic_evil]
    paths = all_clean + all_evil

    binary = find_binary()
    records, stdout = run_pipeline(binary, paths)

    known_paths = set(paths)
    assert all(record.get("file") in known_paths for record in records), "Sink received results for an unknown file"
    for path in all_evil:
        assert not any(record.get("file") == path for record in records), (
            f"Evil file produced sink output: {path}"
        )
        assert f"REJECTED: {path}" in stdout.splitlines(), f"Missing rejection message for {path}"
    for path in all_clean:
        validate_clean_file(path, records)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
