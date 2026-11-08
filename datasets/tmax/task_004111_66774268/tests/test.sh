#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import signal
import socket
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

import psycopg2
import pymongo
import pytest

NGINX_CONF = "/home/user/nginx/nginx.conf"
RUN_FLASK = "/home/user/app/run_flask.sh"
APP_PATH = "/home/user/app/app.py"
DETECTOR = "/home/user/detect_cross_join.py"


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become available")


def stop_matching(pattern):
    subprocess.run(["pkill", "-f", pattern], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)


def start_submitted_nginx():
    syntax = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert syntax.returncode == 0, syntax.stdout + syntax.stderr

    subprocess.run(["nginx", "-s", "quit"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.7)
    subprocess.run(["pkill", "-9", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)
    launched = subprocess.run(
        ["nginx", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert launched.returncode == 0, launched.stdout + launched.stderr
    wait_for_port(8080)


def test_nginx_configuration():
    nginx_conf_path = NGINX_CONF
    assert os.path.isfile(nginx_conf_path), f"Nginx config not found at {nginx_conf_path}"
    with open(nginx_conf_path, "r") as f:
        content = f.read()

    assert "proxy_pass" in content, "Nginx config is missing proxy_pass directive."
    assert "http://127.0.0.1:5000" in content or "http://localhost:5000" in content, \
        "Nginx config does not properly proxy to Flask app on port 5000."


def test_flask_environment_variables():
    run_flask_path = RUN_FLASK
    assert os.path.isfile(run_flask_path), f"Flask run script not found at {run_flask_path}"
    with open(run_flask_path, "r") as f:
        content = f.read()

    assert "POSTGRES_URI" in content, "POSTGRES_URI not set in run_flask.sh"
    assert "MONGO_URI" in content, "MONGO_URI not set in run_flask.sh"
    assert "127.0.0.1:5432" in content or "localhost:5432" in content, "PostgreSQL port/host missing"
    assert "biomed" in content, "PostgreSQL database name 'biomed' missing"
    assert "researcher" in content, "PostgreSQL user missing"
    assert "secret" in content, "PostgreSQL password missing"
    assert "127.0.0.1:27017" in content or "localhost:27017" in content, "MongoDB port/host missing"
    assert "biomed_notes" in content, "MongoDB database 'biomed_notes' missing"


def test_run_flask_effective_environment_and_database_connectivity():
    assert os.path.isfile(APP_PATH)
    capture = f"/tmp/flask_env_{secrets.token_hex(8)}.json"
    with open(APP_PATH, "rb") as f:
        original = f.read()

    probe = (
        "import json, os\n"
        f"with open({capture!r}, 'w') as f:\n"
        "    json.dump({'POSTGRES_URI': os.environ.get('POSTGRES_URI'), "
        "'MONGO_URI': os.environ.get('MONGO_URI')}, f)\n"
    ).encode()

    proc = None
    try:
        with open(APP_PATH, "wb") as f:
            f.write(probe)
        proc = subprocess.Popen(
            ["bash", RUN_FLASK],
            cwd="/home/user/app",
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                 "HOME": "/home/user"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.time() + 6
        while time.time() < deadline and not os.path.exists(capture):
            if proc.poll() is not None and not os.path.exists(capture):
                break
            time.sleep(0.1)
        assert os.path.isfile(capture), "run_flask.sh did not pass its environment to app.py"
        with open(capture) as f:
            values = json.load(f)
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        with open(APP_PATH, "wb") as f:
            f.write(original)
        try:
            os.unlink(capture)
        except FileNotFoundError:
            pass

    postgres_uri = values.get("POSTGRES_URI")
    mongo_uri = values.get("MONGO_URI")
    assert isinstance(postgres_uri, str) and postgres_uri, "POSTGRES_URI is not exported to Flask"
    assert isinstance(mongo_uri, str) and mongo_uri, "MONGO_URI is not exported to Flask"

    pg = urlparse(postgres_uri)
    assert pg.scheme in ("postgres", "postgresql")
    assert pg.hostname in ("127.0.0.1", "localhost") and pg.port == 5432
    assert pg.username == "researcher" and pg.password == "secret"
    assert pg.path == "/biomed"

    mongo = urlparse(mongo_uri)
    assert mongo.scheme in ("mongodb", "mongodb+srv")
    assert mongo.hostname in ("127.0.0.1", "localhost") and mongo.port == 27017
    assert mongo.path == "/biomed_notes"

    conn = psycopg2.connect(postgres_uri, connect_timeout=4)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT current_database(), current_user")
            assert cur.fetchone() == ("biomed", "researcher")
    finally:
        conn.close()

    client = pymongo.MongoClient(mongo_uri, serverSelectionTimeoutMS=4000)
    try:
        assert client.get_default_database().name == "biomed_notes"
        assert client.admin.command("ping").get("ok") == 1.0
    finally:
        client.close()


def test_end_to_end_proxy():
    # First use an unpredictable backend response to prove Nginx really proxies to port 5000.
    stop_matching(APP_PATH)
    nonce = secrets.token_hex(20)
    backend_path = f"/tmp/backend_probe_{secrets.token_hex(8)}.py"
    backend_code = '''
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = self.headers.get("X-Proxy-Nonce", "")
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        body = json.dumps({"proxied_nonce": n, "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Backend-Probe", n)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 5000), H).serve_forever()
'''
    with open(backend_path, "w") as f:
        f.write(backend_code)
    backend = subprocess.Popen(["python3", backend_path])
    real_flask = None
    try:
        wait_for_port(5000)
        start_submitted_nginx()
        req = urllib.request.Request(
            "http://127.0.0.1:8080/query",
            data=b'{}',
            headers={"Content-Type": "application/json", "X-Proxy-Nonce": nonce},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            body = json.loads(response.read().decode())
            assert response.status == 200
            assert response.headers.get("X-Backend-Probe") == nonce
            assert body == {"proxied_nonce": nonce, "path": "/query"}
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=2)
        except subprocess.TimeoutExpired:
            backend.kill()
        try:
            os.unlink(backend_path)
        except FileNotFoundError:
            pass

    # Restore the submitted Flask launch path and require the endpoint's actual Flask response.
    real_flask = subprocess.Popen(
        ["bash", RUN_FLASK], cwd="/home/user/app",
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_port(5000)
        url = "http://127.0.0.1:8080/query"
        payload = json.dumps({
            "sql_relations": ["patients"],
            "join_conditions": [],
            "mongo_filter": {},
            "cross_map": ""
        }).encode("utf-8")
        req = urllib.request.Request(url, data=payload,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                assert response.status in [200, 400, 500], f"Unexpected status code {response.status}"
                assert response.status == 200
                assert json.loads(response.read().decode()) == {"status": "success", "data": []}
        except urllib.error.HTTPError as e:
            assert e.code != 502, "Nginx returned 502 Bad Gateway. Nginx to Flask proxying is failing."
            pytest.fail(f"Flask endpoint returned HTTP {e.code}")
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")
    finally:
        if real_flask.poll() is not None:
            pytest.fail("run_flask.sh did not keep the Flask application running")


def test_cross_join_detector_script_exists():
    script_path = DETECTOR
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"


def run_detector(filepath):
    result = subprocess.run(
        ["python3", DETECTOR, filepath], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_adversarial_corpus_evil():
    evil_dir = "/home/user/corpora/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, "No evil corpus files found."
    bypassed = []
    for filepath in evil_files:
        if run_detector(filepath) != "REJECT":
            bypassed.append(os.path.basename(filepath))
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_adversarial_corpus_clean():
    clean_dir = "/home/user/corpora/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, "No clean corpus files found."
    modified = []
    for filepath in clean_files:
        if run_detector(filepath) != "ACCEPT":
            modified.append(os.path.basename(filepath))
    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/rejected: {', '.join(modified)}")


def connected(relations, edges):
    if len(relations) <= 1:
        return True
    graph = {r: set() for r in relations}
    for a, b in edges:
        graph[a].add(b)
        graph[b].add(a)
    seen = set()
    stack = [relations[0]]
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        stack.extend(graph[node] - seen)
    return len(seen) == len(relations)


def test_detector_on_hidden_generated_graphs():
    rng = random.SystemRandom()
    cases = []
    # Random graphs vary edge counts, ordering and connected components; answers are derived here.
    while len(cases) < 48:
        count = rng.randint(1, 9)
        tag = secrets.token_hex(4)
        relations = [f"tbl_{tag}_{i}" for i in range(count)]
        possible = [(relations[i], relations[j]) for i in range(count) for j in range(i + 1, count)]
        rng.shuffle(possible)
        edge_count = rng.randint(0, len(possible)) if possible else 0
        edges = possible[:edge_count]
        cases.append((relations, edges, "ACCEPT" if connected(relations, edges) else "REJECT"))

    # Explicitly include sparse connected graphs and dense-but-disconnected graphs.
    tag = secrets.token_hex(4)
    r = [f"node_{tag}_{i}" for i in range(6)]
    cases.append((r, [(r[i], r[i + 1]) for i in range(5)], "ACCEPT"))
    cases.append((r, [(r[i], r[j]) for i in range(5) for j in range(i + 1, 5)], "REJECT"))

    assert any(c[2] == "ACCEPT" for c in cases)
    assert any(c[2] == "REJECT" for c in cases)
    with tempfile.TemporaryDirectory(prefix="graph_inputs_") as directory:
        for index, (relations, edges, expected) in enumerate(cases):
            shuffled_relations = list(relations)
            shuffled_edges = list(edges)
            rng.shuffle(shuffled_relations)
            rng.shuffle(shuffled_edges)
            conditions = []
            for a, b in shuffled_edges:
                if rng.choice([True, False]):
                    a, b = b, a
                conditions.append(f"{a}.key = {b}.foreign_key")
            payload = {
                "sql_relations": shuffled_relations,
                "join_conditions": conditions,
                "mongo_filter": {"probe": secrets.token_hex(5)},
                "cross_map": ""
            }
            path = os.path.join(directory, f"case_{secrets.token_hex(6)}_{index}.json")
            with open(path, "w") as f:
                json.dump(payload, f)
            output = run_detector(path)
            assert output == expected, f"Expected {expected} for relations={relations}, edges={edges}; got {output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
