#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import yaml


def test_routes_json_exists_and_correct():
    json_path = "/home/user/routes.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {json_path} as JSON: {e}")

    expected_mapping = {
        "/api/v1/auth": "http://127.0.0.1:5001",
        "/api/v1/billing": "http://127.0.0.1:5002",
        "/api/v2/catalog": "http://127.0.0.1:5003",
    }
    assert data == expected_mapping, f"JSON content in {json_path} does not match expected mapping."


def test_nginx_conf_exists_and_valid():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."

    cmd = ["nginx", "-t", "-c", conf_path, "-g", "pid /home/user/nginx.pid;"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx configuration validation failed:\n{result.stderr}"


def test_nginx_conf_contents():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "events" in content, "Nginx config missing 'events' block."
    assert "http" in content, "Nginx config missing 'http' block."
    assert "9000" in content, "Nginx config missing port 9000 in server block."
    assert "/home/user/error.log" in content, "Nginx config missing error_log directive pointing to /home/user/error.log"
    assert "/home/user/access.log" in content, "Nginx config missing access_log directive pointing to /home/user/access.log"

    expected_proxy_passes = [
        "proxy_pass http://127.0.0.1:5001",
        "proxy_pass http://127.0.0.1:5002",
        "proxy_pass http://127.0.0.1:5003",
    ]
    for pp in expected_proxy_passes:
        assert pp in content, f"Nginx config missing expected directive: '{pp}'"


def _candidate_scripts():
    excluded = {
        "/home/user/routes.yaml",
        "/home/user/routes.json",
        "/home/user/nginx.conf",
        "/home/user/error.log",
        "/home/user/access.log",
        "/home/user/nginx.pid",
    }
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for name in files:
            if name.startswith("."):
                continue
            path = os.path.join(root, name)
            if path in excluded or not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                continue
            try:
                with open(path, "rb") as f:
                    head = f.read(256)
            except OSError:
                continue
            if name.endswith((".py", ".sh")) or head.startswith(b"#!"):
                candidates.append(path)
    return sorted(candidates)


def _command_for(path):
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith(".sh"):
        return ["bash", path]
    with open(path, "rb") as f:
        first = f.readline().decode("utf-8", "replace").lower()
    if "python" in first:
        return ["python3", path]
    if any(shell in first for shell in ("/sh", "bash", "dash")):
        return ["bash", path]
    if os.access(path, os.X_OK):
        return [path]
    raise AssertionError(f"Cannot execute candidate script {path}")


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)
    os.environ["HOME"] = account.pw_dir


def _strip_comments(text):
    lines = []
    for line in text.splitlines():
        out = []
        quote = None
        escaped = False
        for ch in line:
            if escaped:
                out.append(ch)
                escaped = False
            elif ch == "\\":
                out.append(ch)
                escaped = True
            elif quote:
                out.append(ch)
                if ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                out.append(ch)
                quote = ch
            elif ch == "#":
                break
            else:
                out.append(ch)
        lines.append("".join(out))
    return "\n".join(lines)


def _parse_nginx(text):
    token_re = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[{};]|[^\s{};]+''')
    tokens = token_re.findall(_strip_comments(text))

    def clean(token):
        if len(token) >= 2 and token[0] == token[-1] and token[0] in "'\"":
            return token[1:-1]
        return token

    def parse_scope(pos, nested):
        nodes = []
        while pos < len(tokens):
            if tokens[pos] == "}":
                if not nested:
                    raise ValueError("unexpected closing brace")
                return nodes, pos + 1
            header = []
            while pos < len(tokens) and tokens[pos] not in (";", "{", "}"):
                header.append(clean(tokens[pos]))
                pos += 1
            if not header or pos >= len(tokens) or tokens[pos] == "}":
                raise ValueError("malformed nginx statement")
            if tokens[pos] == ";":
                nodes.append((header, None))
                pos += 1
            else:
                children, pos = parse_scope(pos + 1, True)
                nodes.append((header, children))
        if nested:
            raise ValueError("unclosed nginx block")
        return nodes, pos

    nodes, end = parse_scope(0, False)
    if end != len(tokens):
        raise ValueError("trailing nginx tokens")
    return nodes


def _blocks(nodes, name):
    return [(header, children) for header, children in nodes if children is not None and header and header[0] == name]


def _directives(nodes, name):
    return [header for header, children in nodes if children is None and header and header[0] == name]


def _assert_structural_config(conf_path, mapping):
    with open(conf_path, "r") as f:
        nodes = _parse_nginx(f.read())

    assert _blocks(nodes, "events"), "No top-level events block was generated"
    http_blocks = _blocks(nodes, "http")
    assert http_blocks, "No top-level http block was generated"

    valid_server = None
    for _, http in http_blocks:
        error_logs = _directives(http, "error_log")
        access_logs = _directives(http, "access_log")
        assert any(len(d) >= 2 and d[1] == "/home/user/error.log" for d in error_logs), \
            "error_log is not a directive directly inside the http block"
        assert any(len(d) >= 2 and d[1] == "/home/user/access.log" for d in access_logs), \
            "access_log is not a directive directly inside the http block"

        for _, server in _blocks(http, "server"):
            listens = _directives(server, "listen")
            listens_9000 = any(
                len(d) >= 2 and (d[1] == "9000" or d[1].endswith(":9000"))
                for d in listens
            )
            if not listens_9000:
                continue
            locations = _blocks(server, "location")
            if all(any(
                header[-1] == path and any(
                    len(d) >= 2 and d[1] == target
                    for d in _directives(body, "proxy_pass")
                )
                for header, body in locations
            ) for path, target in mapping.items()):
                valid_server = server
                break
    assert valid_server is not None, \
        "A server listening on 9000 must contain a real location/proxy_pass block for every YAML service"


def _free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _exercise_proxy(conf_path, paths, replies):
    servers = []
    threads = []
    nginx = None
    try:
        for port, reply in replies.items():
            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    body = self.server.reply.encode()
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                def log_message(self, *args):
                    pass
            server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
            server.reply = reply
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        try:
            os.remove("/home/user/nginx.pid")
        except FileNotFoundError:
            pass
        nginx = subprocess.Popen(
            ["nginx", "-c", conf_path, "-g", "pid /home/user/nginx.pid; daemon off;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=_demote_to_user,
            start_new_session=True,
        )

        deadline = time.time() + 6
        last_error = None
        while time.time() < deadline:
            if nginx.poll() is not None:
                stdout, stderr = nginx.communicate()
                raise AssertionError(f"Nginx could not run in user space: {stdout}\n{stderr}")
            try:
                with urllib.request.urlopen("http://127.0.0.1:9000" + paths[0], timeout=1) as response:
                    if response.read().decode() == replies[paths[0][0]]:
                        break
            except Exception as exc:
                last_error = exc
                time.sleep(0.15)
        else:
            raise AssertionError(f"Generated Nginx server did not become reachable: {last_error}")

        for port, path in paths:
            with urllib.request.urlopen("http://127.0.0.1:9000" + path, timeout=3) as response:
                body = response.read().decode()
            assert body == replies[port], f"Request for {path} was not routed to its corresponding backend"
    finally:
        if nginx is not None and nginx.poll() is None:
            try:
                os.killpg(nginx.pid, signal.SIGTERM)
                nginx.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(nginx.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for server in servers:
            server.shutdown()
            server.server_close()


def test_created_script_reads_yaml_and_builds_real_proxies():
    candidates = _candidate_scripts()
    assert candidates, "No script was created under /home/user"

    yaml_path = "/home/user/routes.yaml"
    output_paths = ["/home/user/routes.json", "/home/user/nginx.conf"]
    saved = {}
    for path in [yaml_path] + output_paths:
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    ports = [_free_port() for _ in range(3)]
    nonce = uuid.uuid4().hex
    paths = [f"/verify/{nonce}/{i}" for i in range(3)]
    mapping = {path: f"http://127.0.0.1:{port}" for path, port in zip(paths, ports)}
    document = {
        "services": [
            {"name": f"dynamic-{i}-{nonce}", "path": path, "target": mapping[path]}
            for i, path in enumerate(paths)
        ]
    }
    failures = []

    try:
        with open(yaml_path, "w") as f:
            yaml.safe_dump(document, f, sort_keys=False)

        for candidate in candidates:
            for path in output_paths:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            try:
                result = subprocess.run(
                    _command_for(candidate), cwd="/home/user", capture_output=True,
                    text=True, timeout=20, preexec_fn=_demote_to_user,
                )
                assert result.returncode == 0, f"exit {result.returncode}: {result.stderr}"
                assert all(os.path.isfile(path) for path in output_paths), "did not create both required outputs"
                with open("/home/user/routes.json", "r") as f:
                    generated = json.load(f)
                assert generated == mapping, "routes.json was not derived from the changed routes.yaml"

                syntax = subprocess.run(
                    ["nginx", "-t", "-c", "/home/user/nginx.conf", "-g", "pid /home/user/nginx.pid;"],
                    capture_output=True, text=True,
                )
                assert syntax.returncode == 0, syntax.stderr
                _assert_structural_config("/home/user/nginx.conf", mapping)

                replies = {port: f"backend-{i}-{nonce}" for i, port in enumerate(ports)}
                _exercise_proxy("/home/user/nginx.conf", list(zip(ports, paths)), replies)
                return
            except Exception as exc:
                failures.append(f"{candidate}: {exc}")

        pytest.fail("No created script regenerated and correctly routed randomized YAML data:\n" + "\n".join(failures))
    finally:
        for path, content in saved.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
