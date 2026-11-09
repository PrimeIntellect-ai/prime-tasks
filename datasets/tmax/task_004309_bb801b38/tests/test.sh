#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import subprocess
import time
import urllib.request
import uuid

import pytest
import redis

START_SCRIPT = "/home/user/start_services.sh"
WORKER_DIR = "/home/user/pipeline/rust_worker"
RESULTS_FILE = "/home/user/classification_results.csv"


def post_graph(graph):
    data = json.dumps(graph).encode("utf-8")
    req = urllib.request.Request(
        "http://localhost:5000/process",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as response:
        assert 200 <= response.status < 300


def expected_status(graph):
    nodes = list(graph["nodes"])
    adjacency = {node: set() for node in nodes}
    for edge in graph["edges"]:
        u, v = edge
        if u == v:
            continue
        adjacency.setdefault(u, set()).add(v)
        adjacency.setdefault(v, set()).add(u)

    max_degree = max((len(adjacency.get(node, set())) for node in nodes), default=0)
    coefficients = []
    for node in nodes:
        neighbors = list(adjacency.get(node, set()))
        degree = len(neighbors)
        if degree < 2:
            coefficients.append(0.0)
            continue
        links = 0
        for i in range(degree):
            for j in range(i + 1, degree):
                if neighbors[j] in adjacency.get(neighbors[i], set()):
                    links += 1
        coefficients.append((2.0 * links) / (degree * (degree - 1)))

    average = sum(coefficients) / len(nodes) if nodes else 0.0
    return "CLEAN" if max_degree <= 4 and average > 0.0 else "EVIL"


def read_results():
    results = {}
    if not os.path.isfile(RESULTS_FILE):
        return results
    with open(RESULTS_FILE, "r") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 2:
                results[str(parts[0]).strip()] = parts[1].strip().upper()
    return results


def worker_is_running():
    for proc_path in glob.glob("/proc/[0-9]*"):
        try:
            exe = os.path.realpath(os.path.join(proc_path, "exe"))
            cmdline = open(os.path.join(proc_path, "cmdline"), "rb").read().decode("utf-8", "ignore")
        except (OSError, ProcessLookupError):
            continue
        if os.path.basename(exe) == "rust_worker" or re.search(r"(^|[\\x00 /])rust_worker([\\x00 ]|$)", cmdline):
            return True
    return False


def test_adversarial_corpus_verification():
    assert os.path.isfile(START_SCRIPT), f"Missing start script: {START_SCRIPT}"
    assert os.access(START_SCRIPT, os.X_OK), f"Start script is not executable: {START_SCRIPT}"

    cargo_toml = os.path.join(WORKER_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), "Missing Rust worker Cargo.toml"
    with open(cargo_toml, "r") as handle:
        manifest = handle.read()
    assert re.search(r"(?m)^\s*rayon\s*=", manifest), "Cargo.toml must depend on rayon"

    rust_files = glob.glob(os.path.join(WORKER_DIR, "src", "**", "*.rs"), recursive=True)
    assert rust_files, "Rust worker has no Rust source files"
    rust_source = "\n".join(open(path, "r").read() for path in rust_files)
    assert "rayon" in rust_source, "Rust worker source does not use rayon"
    assert re.search(r"\b(par_iter(?:_mut)?|into_par_iter|par_bridge|scope|join)\b", rust_source), \
        "Rust worker does not contain a Rayon parallel operation"

    cargo = "/root/.cargo/bin/cargo"
    if not os.path.isfile(cargo):
        cargo = "/home/user/.cargo/bin/cargo"
    build = subprocess.run(
        [cargo, "build", "--release"],
        cwd=WORKER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert build.returncode == 0, "cargo build --release failed:\n" + build.stdout[-4000:]
    release_binary = os.path.join(WORKER_DIR, "target", "release", "rust_worker")
    assert os.path.isfile(release_binary) and os.access(release_binary, os.X_OK), \
        "Release worker binary was not produced"

    # A submission must create fresh results during this run, not rely on a prewritten CSV.
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    subprocess.run(["pkill", "-f", "redis-server"], check=False)
    subprocess.run(["pkill", "-f", "api.py"], check=False)
    subprocess.run(["pkill", "-f", "rust_worker"], check=False)

    process = subprocess.Popen(
        ["bash", START_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        client = redis.Redis(host="localhost", port=6379, db=0)
        deadline = time.time() + 20
        while True:
            try:
                client.ping()
                req = urllib.request.Request(
                    "http://localhost:5000/process",
                    data=b'{"id":"startup_probe","nodes":[],"edges":[]}',
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                urllib.request.urlopen(req, timeout=1).close()
                break
            except Exception:
                if time.time() >= deadline:
                    pytest.fail("Redis and API did not become ready")
                time.sleep(0.25)

        # Discard the readiness probe and any stale queued work/results.
        client.flushdb()
        if os.path.exists(RESULTS_FILE):
            os.remove(RESULTS_FILE)

        deadline = time.time() + 10
        while not worker_is_running() and time.time() < deadline:
            time.sleep(0.2)
        assert worker_is_running(), "No running Rust worker process was found"

        clean_files = glob.glob("/home/user/corpus/clean/*.json")
        evil_files = glob.glob("/home/user/corpus/evil/*.json")
        assert len(clean_files) > 0, "No clean corpus files found."
        assert len(evil_files) > 0, "No evil corpus files found."

        expected = {}

        # Preserve the original corpus checks.
        for filepath, status in [(p, "CLEAN") for p in clean_files] + [(p, "EVIL") for p in evil_files]:
            with open(filepath, "r") as handle:
                raw = handle.read()
            parsed = json.loads(raw)
            graph_id = parsed.get("graph_id")
            if graph_id is None:
                graph_id = os.path.splitext(os.path.basename(filepath))[0]
            expected[str(graph_id)] = status
            req = urllib.request.Request(
                "http://localhost:5000/process",
                data=raw.encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=3).close()

        token = uuid.uuid4().hex
        generated = [
            {"id": f"hidden_triangle_{token}", "nodes": [11, 23, 47], "edges": [[11, 23], [23, 47], [47, 11]]},
            {"id": f"hidden_k5_{token}", "nodes": [2, 5, 9, 14, 20],
             "edges": [[u, v] for i, u in enumerate([2, 5, 9, 14, 20]) for v in [2, 5, 9, 14, 20][i + 1:]]},
            {"id": f"hidden_triangle_isolates_{token}", "nodes": [3, 8, 13, 21, 34, 55],
             "edges": [[3, 8], [8, 13], [13, 3]]},
            {"id": f"hidden_path_{token}", "nodes": [101, 103, 107, 109, 113],
             "edges": [[101, 103], [103, 107], [107, 109], [109, 113]]},
            {"id": f"hidden_high_degree_clustered_{token}", "nodes": [30, 31, 32, 33, 34, 35],
             "edges": [[30, 31], [30, 32], [30, 33], [30, 34], [30, 35], [31, 32], [32, 33]]},
            {"id": f"hidden_square_{token}", "nodes": [61, 67, 71, 73],
             "edges": [[61, 67], [67, 71], [71, 73], [73, 61]]},
        ]

        # Exercise the HTTP API on unseen graph IDs and structures. Expectations are
        # computed from the specified graph statistics rather than corpus location.
        for graph in generated[:4]:
            expected[graph["id"]] = expected_status(graph)
            post_graph(graph)

        # Also enqueue unseen tasks directly, proving the queue-consuming worker path
        # works independently of HTTP request handling.
        for graph in generated[4:]:
            expected[graph["id"]] = expected_status(graph)
            client.lpush("graph_queue", json.dumps(graph))

        deadline = time.time() + 25
        actual = {}
        while time.time() < deadline:
            actual = read_results()
            if all(graph_id in actual for graph_id in expected):
                break
            time.sleep(0.25)

        assert os.path.isfile(RESULTS_FILE), f"Results file not found: {RESULTS_FILE}"
        assert worker_is_running(), "Rust worker exited before verification completed"

        evil_bypassed = []
        clean_modified = []
        for graph_id, status in expected.items():
            actual_status = actual.get(graph_id)
            if status == "EVIL" and actual_status != "EVIL":
                evil_bypassed.append(graph_id)
            elif status == "CLEAN" and actual_status != "CLEAN":
                clean_modified.append(graph_id)

        errors = []
        if evil_bypassed:
            errors.append(f"evil graphs misclassified or missing: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"clean graphs misclassified or missing: {', '.join(clean_modified)}")
        if errors:
            pytest.fail(" | ".join(errors))
    finally:
        subprocess.run(["pkill", "-f", "redis-server"], check=False)
        subprocess.run(["pkill", "-f", "api.py"], check=False)
        subprocess.run(["pkill", "-f", "rust_worker"], check=False)
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
