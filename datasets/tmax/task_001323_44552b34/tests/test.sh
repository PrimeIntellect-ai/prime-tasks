#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

CONFIG_PATH = "/app/config.env"
SCRIPT_PATH = "/home/user/filter.sh"


def post_json(url, payload, timeout=3):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, json.loads(response.read().decode())


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.1)
    return False


def run_filter(path, timeout=8):
    try:
        return subprocess.run([SCRIPT_PATH, path], capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        pytest.fail(f"filter timed out for {path}")


def test_config_updated():
    assert os.path.isfile(CONFIG_PATH), f"File {CONFIG_PATH} is missing"
    with open(CONFIG_PATH) as f:
        content = f.read()

    # Preserve the original assertions.
    assert "MODEL_PORT=8001" in content, "MODEL_PORT is not set to 8001 in config.env"
    assert "VECTOR_PORT=8002" in content, "VECTOR_PORT is not set to 8002 in config.env"
    assert "DIMENSIONS=10" in content, "DIMENSIONS is not set to 10 in config.env"

    # Also validate the effective final assignments rather than mere substrings.
    values = {}
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
        assert match, f"Invalid config.env line: {raw!r}"
        value = match.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[match.group(1)] = value

    assert values.get("MODEL_PORT") == "8001"
    assert values.get("VECTOR_PORT") == "8002"
    assert values.get("DIMENSIONS") == "10"


def test_services_running_and_correct():
    assert wait_for_port(8001, 1), "Embedding service is not listening on port 8001"
    assert wait_for_port(8002, 1), "Vector DB is not listening on port 8002"

    text = "verifier-health-" + uuid.uuid4().hex
    status, embedded = post_json("http://127.0.0.1:8001/embed", {"text": text})
    assert status == 200
    assert set(embedded) == {"vector"}
    vector = embedded["vector"]
    expected = [byte / 255.0 for byte in hashlib.md5(text.encode()).digest()[:10]]
    assert isinstance(vector, list) and len(vector) == 10
    assert vector == pytest.approx(expected)

    status, result = post_json("http://127.0.0.1:8002/distance", {"vector": vector})
    assert status == 200
    assert set(result) == {"distance"}
    assert result["distance"] == pytest.approx(expected[0] * 10.0)


def test_filter_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode(errors="replace").strip()
    assert re.search(r"(?:^|/)(?:env\s+)?bash(?:\s|$)", first_line), \
        "filter.sh must be a Bash script"


def test_clean_corpus_accepted():
    clean_dir = "/home/user/corpora/clean"
    assert os.path.isdir(clean_dir), f"{clean_dir} directory is missing"
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(clean_dir)):
        if fname.endswith(".json"):
            total += 1
            result = run_filter(os.path.join(clean_dir, fname))
            if result.returncode != 0:
                failed_files.append(fname)
    assert total > 0, f"No JSON files found in {clean_dir}"
    assert not failed_files, (
        f"{len(failed_files)} of {total} clean modified (rejected instead of accepted). "
        f"Offending files: {', '.join(failed_files)}"
    )


def test_evil_corpus_rejected():
    evil_dir = "/home/user/corpora/evil"
    assert os.path.isdir(evil_dir), f"{evil_dir} directory is missing"
    failed_files = []
    total = 0
    for fname in sorted(os.listdir(evil_dir)):
        if fname.endswith(".json"):
            total += 1
            result = run_filter(os.path.join(evil_dir, fname))
            if result.returncode != 1:
                failed_files.append(fname)
    assert total > 0, f"No JSON files found in {evil_dir}"
    assert not failed_files, (
        f"{len(failed_files)} of {total} evil bypassed (accepted or crashed instead of "
        f"rejected with code 1). Offending files: {', '.join(failed_files)}"
    )


def listener_pids(ports):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port in ports:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_listeners(ports):
    pids = listener_pids(set(ports))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(set(ports)):
        time.sleep(0.1)
    for pid in listener_pids(set(ports)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(set(ports)):
        time.sleep(0.05)
    assert not listener_pids(set(ports)), "Could not free service ports for behavioral test"


def restart_real_services():
    stop_listeners([8001, 8002])
    subprocess.run(
        ["/app/start.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        check=False,
    )
    assert wait_for_port(8001), "Embedding service did not restart"
    assert wait_for_port(8002), "Vector DB did not restart"


def test_filter_dynamic_pipeline_and_error_handling():
    # Argument-count behavior is checked before replacing the services.
    no_arg = subprocess.run([SCRIPT_PATH], capture_output=True, timeout=5)
    two_args = subprocess.run([SCRIPT_PATH, "/dev/null", "/dev/null"], capture_output=True, timeout=5)
    assert no_arg.returncode != 0, "filter accepted zero arguments"
    assert two_args.returncode != 0, "filter accepted more than one argument"

    token = uuid.uuid4().hex
    texts = {
        "accept": f"accept-{token}",
        "distance": f"distance-{token}",
        "predatory": f"predatory-{token}",
        "near_source": f"near-source-{token}",
        "bad_dimension": f"bad-dimension-{token}",
        "embed_error": f"embed-error-{token}",
    }
    vectors = {
        texts["accept"]: [0.111] + [0.01] * 9,
        texts["distance"]: [0.222] + [0.02] * 9,
        texts["predatory"]: [0.333] + [0.03] * 9,
        texts["near_source"]: [0.444] + [0.04] * 9,
    }
    distances = {0.111: 4.25, 0.222: 7.75, 0.333: 1.25, 0.444: 2.0}

    temp_root = tempfile.mkdtemp(prefix="etl-verifier-")
    log_path = os.path.join(temp_root, "requests.jsonl")
    spec_path = os.path.join(temp_root, "spec.json")
    server_path = os.path.join(temp_root, "mock_services.py")
    with open(spec_path, "w") as f:
        json.dump({"texts": texts, "vectors": vectors, "distances": distances}, f)

    server_code = r'''import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
spec = json.load(open(sys.argv[1]))
log_path = sys.argv[2]

def log(entry):
    with open(log_path, "a") as f:
        f.write(json.dumps(entry) + "\n")
        f.flush()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length))
        except Exception:
            self.reply(400, {"error": "invalid json"})
            return
        if self.server.server_port == 8001 and self.path == "/embed":
            text = body.get("text") if isinstance(body, dict) else None
            log({"service": "embed", "text": text})
            if text == spec["texts"]["embed_error"]:
                self.reply(503, {"error": "forced embedding failure"})
            elif text == spec["texts"]["bad_dimension"]:
                self.reply(200, {"vector": [0.9] * 9})
            elif text in spec["vectors"]:
                self.reply(200, {"vector": spec["vectors"][text]})
            else:
                self.reply(422, {"error": "unknown verifier text"})
            return
        if self.server.server_port == 8002 and self.path == "/distance":
            vector = body.get("vector") if isinstance(body, dict) else None
            log({"service": "distance", "vector": vector})
            valid = list(spec["vectors"].values())
            if vector not in valid:
                self.reply(422, {"error": "vector was not an embedding response"})
                return
            key = str(vector[0])
            self.reply(200, {"distance": spec["distances"][key]})
            return
        self.reply(404, {"error": "wrong endpoint"})

servers = [ThreadingHTTPServer(("127.0.0.1", p), Handler) for p in (8001, 8002)]
for server in servers:
    threading.Thread(target=server.serve_forever, daemon=True).start()
threading.Event().wait()
'''
    with open(server_path, "w") as f:
        f.write(server_code)

    mock = None
    try:
        stop_listeners([8001, 8002])
        mock = subprocess.Popen(
            [sys.executable, server_path, spec_path, log_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        assert wait_for_port(8001) and wait_for_port(8002), "Mock services failed to start"

        cases = [
            # Deliberately place an accepted file under an 'evil' pathname and a
            # rejected file under a 'clean' pathname to defeat path-based scripts.
            ("corpora/evil/random_accept.json", texts["accept"], "nature", 0),
            ("corpora/clean/random_distance_reject.json", texts["distance"], "nature", 1),
            ("unrelated/random_source_reject.json", texts["predatory"], "predatory_journal_x", 1),
            ("unrelated/random_near_source.json", texts["near_source"], "predatory_journal_x ", 0),
            ("unrelated/random_bad_dimension.json", texts["bad_dimension"], "nature", 1),
            ("unrelated/random_embed_error.json", texts["embed_error"], "nature", 1),
        ]

        for relative, abstract, source, expected in cases:
            path = os.path.join(temp_root, relative)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                json.dump({"id": uuid.uuid4().hex, "abstract": abstract,
                           "metadata": {"source": source}}, f)
            result = run_filter(path)
            assert result.returncode == expected, (
                f"dynamic case {relative} returned {result.returncode}, expected {expected}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

        with open(log_path) as f:
            events = [json.loads(line) for line in f if line.strip()]
        embedded_texts = {event.get("text") for event in events if event.get("service") == "embed"}
        assert set(texts.values()).issubset(embedded_texts), \
            "filter did not POST every dynamic abstract to /embed"

        sent_vectors = [event.get("vector") for event in events if event.get("service") == "distance"]
        for text in (texts["accept"], texts["distance"], texts["predatory"], texts["near_source"]):
            assert vectors[text] in sent_vectors, \
                "filter did not pass the embedding response to /distance"
    finally:
        if mock is not None:
            mock.terminate()
            try:
                mock.wait(timeout=3)
            except subprocess.TimeoutExpired:
                mock.kill()
                mock.wait(timeout=2)
        restart_real_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
