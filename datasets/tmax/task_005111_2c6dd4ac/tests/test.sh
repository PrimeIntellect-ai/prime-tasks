#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import socket
import string
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

APP = "/home/user/app"
BINARY = APP + "/cypher_sanitizer"
SOURCE = APP + "/cypher_sanitizer.c"


def run_classifier(path, query):
    return subprocess.run(
        [path], input=query.encode("utf-8"), capture_output=True, timeout=3
    )


def assert_classification(path, query, expected_output, expected_code):
    result = run_classifier(path, query)
    assert result.returncode == expected_code, (
        f"Wrong exit code for {query!r}: expected {expected_code}, "
        f"got {result.returncode}; stderr={result.stderr!r}"
    )
    assert result.stdout.decode("utf-8", errors="replace").strip() == expected_output, (
        f"Wrong output for {query!r}: {result.stdout!r}"
    )


def random_word(rng, prefix):
    return prefix + "".join(rng.choice(string.ascii_letters) for _ in range(14))


def random_case(rng, text):
    return "".join(
        c.upper() if c.isalpha() and rng.randrange(2) else c.lower()
        for c in text
    )


def generated_cases():
    rng = random.SystemRandom()
    cases = []

    for _ in range(12):
        a = random_word(rng, "a")
        b = random_word(rng, "b")
        p = random_word(rng, "p")
        label = random_word(rng, "Label")
        rel = random_word(rng, "REL")
        ws1 = rng.choice([" ", "  ", "\t", "\n"])
        ws2 = rng.choice([" ", "  ", "\t"])

        cases.append((
            random_case(rng, f"MATCH{ws1}{p}=({a}:{label})-[*]->({b}){ws2}RETURN {p}"),
            "EVIL", 1,
        ))
        cases.append((
            random_case(rng, f"MATCH {p}=({a})-[*..]->({b}) RETURN {p}"),
            "EVIL", 1,
        ))
        cases.append((
            random_case(rng, f"CALL{ws1}db.{rng.choice(['labels', 'schema', 'relationshipTypes'])}()"),
            "EVIL", 1,
        ))
        cases.append((
            random_case(rng, f"MATCH{ws1}({a}:{label}),{ws2}({b}:{label}) RETURN {a}, {b}"),
            "EVIL", 1,
        ))

        cases.append((
            random_case(rng, f"MATCH ({a}:{label})-[:{rel}]->({b}) RETURN {a}, {b}"),
            "CLEAN", 0,
        ))
        cases.append((
            random_case(rng, f"MATCH ({a}:{label}) WHERE {a}.active = true RETURN {a} LIMIT 7"),
            "CLEAN", 0,
        ))
        cases.append((
            random_case(rng, f"MATCH ({a}:{label}), ({b}:{label}) WHERE {a}.id = {b}.id RETURN {a}"),
            "CLEAN", 0,
        ))
        cases.append((
            random_case(rng, f"CREATE ({a}:{label} {{name: 'sample'}}) RETURN {a}"),
            "CLEAN", 0,
        ))

    long_label = random_word(rng, "LongLabel")
    cases.append(("MATCH (n:" + long_label + ") RETURN n" + (" " * 3700), "CLEAN", 0))
    rng.shuffle(cases)
    return cases


def test_cypher_sanitizer_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cypher_sanitizer must be a compiled executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."


def test_source_builds_and_hidden_queries_are_classified():
    rebuilt = "/tmp/cypher_sanitizer_rebuilt"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert build.returncode == 0, f"C source did not compile:\n{build.stderr}"

    cases = generated_cases()
    for executable in (BINARY, rebuilt):
        for query, output, code in cases:
            assert_classification(executable, query, output, code)


def test_adversarial_corpus():
    evil_dir = "/home/user/corpora/evil/"
    clean_dir = "/home/user/corpora/clean/"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.cypher')]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.cypher')]

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        filepath = os.path.join(evil_dir, ef)
        with open(filepath, 'rb') as f:
            query_bytes = f.read()
        result = subprocess.run([BINARY], input=query_bytes, capture_output=True, timeout=3)
        stdout = result.stdout.decode('utf-8').strip()
        if result.returncode != 1 or stdout != "EVIL":
            evil_bypassed.append(ef)

    for cf in clean_files:
        filepath = os.path.join(clean_dir, cf)
        with open(filepath, 'rb') as f:
            query_bytes = f.read()
        result = subprocess.run([BINARY], input=query_bytes, capture_output=True, timeout=3)
        stdout = result.stdout.decode('utf-8').strip()
        if result.returncode != 0 or stdout != "CLEAN":
            clean_modified.append(cf)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not error_messages, " | ".join(error_messages)


def test_service_configuration():
    nginx_conf_path = APP + "/nginx.conf"
    env_path = APP + "/.env"

    assert os.path.isfile(nginx_conf_path), f"{nginx_conf_path} is missing."
    with open(nginx_conf_path, "r") as f:
        nginx_content = f.read()
    assert "127.0.0.1:5000" in nginx_content or "localhost:5000" in nginx_content, \
        "Nginx configuration does not route to Flask API on port 5000."

    nginx_test = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path], capture_output=True, text=True, timeout=10
    )
    assert nginx_test.returncode == 0, f"Invalid Nginx configuration: {nginx_test.stderr}"

    assert os.path.isfile(env_path), f"{env_path} is missing."
    with open(env_path, "r") as f:
        env_content = f.read()
    assert "127.0.0.1:7687" in env_content or "localhost:7687" in env_content, \
        "Flask .env does not configure GRAPH_DB_URL to port 7687."

    values = {}
    for line in env_content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    graph_url = values.get("GRAPH_DB_URL", "")
    assert graph_url, "GRAPH_DB_URL is not defined in .env."
    assert "127.0.0.1:7687" in graph_url or "localhost:7687" in graph_url, \
        "GRAPH_DB_URL must target the graph database on port 7687."


def listening_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listening_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for name in os.listdir("/proc"):
        if not name.isdigit():
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


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_listener(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listening_inodes(port):
            return
        time.sleep(0.1)
    pytest.fail(f"No service began listening on port {port}.")


class GraphProbe:
    def __init__(self, marker):
        self.marker = marker
        self.received = []
        self.stop_event = threading.Event()
        self.ready = threading.Event()
        self.sock = None
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()
        assert self.ready.wait(3), "Mock graph database failed to start."

    def run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock = sock
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("127.0.0.1", 7687))
        sock.listen(20)
        sock.settimeout(0.2)
        self.ready.set()
        while not self.stop_event.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                conn.settimeout(0.5)
                chunks = []
                while True:
                    try:
                        chunk = conn.recv(8192)
                    except socket.timeout:
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
                    if sum(map(len, chunks)) >= 65536:
                        break
                payload = b"".join(chunks)
                self.received.append(payload)
                body = json.dumps({"backend": self.marker, "rows": [{"ok": True}]}).encode()
                try:
                    if payload.lstrip().startswith((b"GET ", b"POST ", b"PUT ")):
                        conn.sendall(
                            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                            + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode()
                            + body
                        )
                    else:
                        conn.sendall(body + b"\n")
                except OSError:
                    pass

    def saw(self, token):
        needle = token.encode()
        return any(needle in payload for payload in self.received)

    def close(self):
        self.stop_event.set()
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.thread.join(timeout=2)


def process_description(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def test_end_to_end_flow():
    script_path = APP + "/start_services.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    for port in (8080, 5000, 7687):
        stop_port(port)

    token = "verify_" + os.urandom(18).hex()
    marker = "graph_backend_" + os.urandom(12).hex()
    probe = GraphProbe(marker)
    probe.start()
    starter = None

    try:
        starter = subprocess.Popen(
            ["bash", script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for_listener(5000)
        wait_for_listener(8080)

        nginx_pids = listener_pids(8080)
        descriptions = [process_description(pid).lower() for pid in nginx_pids]
        assert any("nginx" in desc for desc in descriptions), \
            f"Port 8080 is not being served by Nginx: {descriptions}"
        assert listener_pids(5000), "The Flask API is not listening on port 5000."

        query = f"MATCH (n:{token}) RETURN n LIMIT 1"
        data = json.dumps({"query": query}).encode("utf-8")
        req = urllib.request.Request(
            "http://127.0.0.1:8080/query",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as response:
                assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
                body = response.read().decode("utf-8", errors="replace")
                assert body, "Response body should not be empty."
                server_header = response.headers.get("Server", "").lower()
                assert "nginx" in server_header, \
                    f"External response did not pass through Nginx (Server={server_header!r})."
        except urllib.error.URLError as exc:
            pytest.fail(f"End-to-end flow failed: {exc}")

        deadline = time.time() + 3
        while time.time() < deadline and not probe.saw(token):
            time.sleep(0.05)
        assert probe.saw(token), \
            "The unique Cypher query never reached the graph database on port 7687."
    finally:
        if starter is not None and starter.poll() is None:
            starter.terminate()
            try:
                starter.wait(timeout=2)
            except subprocess.TimeoutExpired:
                starter.kill()
        probe.close()
        for port in (8080, 5000):
            stop_port(port)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
