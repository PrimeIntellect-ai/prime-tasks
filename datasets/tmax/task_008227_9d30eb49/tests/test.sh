#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import signal
import subprocess
import threading
import time
import urllib.request
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def test_valid_logs_exists():
    path = "/home/user/valid_logs.txt"
    assert os.path.isfile(path), f"Expected output file {path} does not exist. Did the Rust pipeline run successfully?"


def test_valid_logs_content():
    path = "/home/user/valid_logs.txt"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    try:
        actual_ids = [int(line) for line in lines]
    except ValueError:
        pytest.fail(f"File {path} contains non-integer values. It should only contain valid log IDs.")

    expected_ids = [1, 2, 4, 6, 8]

    assert actual_ids == expected_ids, (
        f"The contents of {path} do not match the expected valid IDs. "
        f"Expected: {expected_ids}, but got: {actual_ids}. "
        "Check your distance calculation, threshold logic, and sorting."
    )


def test_embedding_service_is_running():
    request = urllib.request.Request(
        "http://127.0.0.1:8080/embed",
        data=json.dumps({"text": "INFO verifier health check"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        payload = json.load(response)
    assert payload == {"embedding": [1.0] * 10}, "The required embedding service is not responding correctly"


def test_rust_project_exists_and_compiles():
    manifest = "/home/user/etl_cleaner/Cargo.toml"
    source = "/home/user/etl_cleaner/src/main.rs"
    assert os.path.isfile(manifest), "Missing Rust Cargo.toml"
    assert os.path.isfile(source), "Missing Rust src/main.rs"

    result = subprocess.run(
        ["cargo", "build", "--manifest-path", manifest],
        cwd="/home/user/etl_cleaner",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust project did not compile:\n{result.stdout}"


def _kill_port_8080_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_pipeline_executes_against_full_dynamic_dataset():
    csv_path = "/home/user/data/logs.csv"
    output_path = "/home/user/valid_logs.txt"
    original_csv = open(csv_path, "rb").read()
    original_output = open(output_path, "rb").read()

    vectors = [
        [3.0] * 5 + [0.0] * 5,
        [0.0] * 5 + [3.0] * 5,
        [2.0] * 10,
        [3.01] * 5 + [0.0] * 5,
        [0.0] * 5 + [-3.2] * 5,
        [1.0] * 10,
        [2.2] * 10,
    ]
    ids = random.sample(range(10000, 90000), len(vectors))
    rows = []
    embedding_by_text = {}
    for row_id, vector in zip(ids, vectors):
        text = "verification-" + secrets.token_hex(12)
        rows.append((row_id, text))
        embedding_by_text[text] = vector
    random.shuffle(rows)

    expected_ids = sorted(
        row_id
        for row_id, text in rows
        if math.hypot(
            sum(embedding_by_text[text][:5]),
            sum(embedding_by_text[text][5:]),
        ) <= 15.0
    )
    requests_seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/embed":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length))
                text = payload["text"]
                vector = embedding_by_text[text]
            except Exception:
                self.send_error(400)
                return
            requests_seen.append(text)
            body = json.dumps({"embedding": vector}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = None
    thread = None
    try:
        _kill_port_8080_listener()
        server = HTTPServer(("127.0.0.1", 8080), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "text"])
            writer.writerows(rows)
        os.remove(output_path)

        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", "/home/user/etl_cleaner/Cargo.toml"],
            cwd="/home/user/etl_cleaner",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust ETL pipeline failed when executed:\n{result.stdout}"
        assert os.path.isfile(output_path), "Executing the Rust pipeline did not create valid_logs.txt"

        counts = Counter(requests_seen)
        missing = [text for _, text in rows if counts[text] == 0]
        assert not missing, "The pipeline did not query the embedding API for every CSV row"
        assert set(counts).issubset(embedding_by_text), "The pipeline queried embeddings for unexpected text"

        with open(output_path) as f:
            lines = [line.strip() for line in f if line.strip()]
        try:
            actual_ids = [int(line) for line in lines]
        except ValueError:
            pytest.fail("Dynamically generated output contains non-integer values")
        assert actual_ids == expected_ids, (
            f"Executed pipeline produced {actual_ids}; expected {expected_ids} from the supplied embeddings"
        )
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=2)
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        with open(output_path, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
