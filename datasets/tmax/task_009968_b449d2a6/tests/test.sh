#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import textwrap
import time


def test_responses_file_exists_and_correct():
    responses_file = "/home/user/responses.txt"
    assert os.path.exists(responses_file), f"File {responses_file} does not exist"

    with open(responses_file, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 50, f"Expected exactly 50 lines in {responses_file}, but found {len(lines)}"

    for i, line in enumerate(lines):
        val = line.strip()
        assert val == "5", f"Expected line {i+1} to be '5', but got '{val}'"


def test_benchmark_result_file_exists():
    benchmark_result_file = "/home/user/benchmark_result.txt"
    assert os.path.exists(benchmark_result_file), f"File {benchmark_result_file} does not exist"

    with open(benchmark_result_file, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"File {benchmark_result_file} is empty"


def test_rpn_server_script_exists_and_valid():
    server_script = "/home/user/rpn_server.sh"
    assert os.path.exists(server_script), f"File {server_script} does not exist"
    assert os.access(server_script, os.X_OK), f"File {server_script} is not executable"

    with open(server_script, "r") as f:
        content = f.read()

    # Ensure bash arithmetic or let is used
    assert "$(('"[:-1] in content or "let " in content or "expr " in content, "rpn_server.sh does not appear to use bash arithmetic for evaluation"

    # Ensure no forbidden external tools are used for math
    forbidden_tools = ["awk", "bc", "python", "perl", "node", "ruby"]
    for tool in forbidden_tools:
        # Check for word boundaries to avoid matching substrings
        assert not re.search(rf'\b{tool}\b', content), f"rpn_server.sh must not use external tool '{tool}' for math evaluation"


def test_benchmark_script_exists():
    benchmark_script = "/home/user/benchmark.sh"
    assert os.path.exists(benchmark_script), f"File {benchmark_script} does not exist"
    assert os.access(benchmark_script, os.X_OK), f"File {benchmark_script} is not executable"


def _stop_process_group(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except Exception:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _bash_div(a, b):
    assert b != 0
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def _evaluate_rpn(expression):
    stack = []
    for token in expression.split():
        if token.isdigit():
            stack.append(int(token))
            continue
        assert token in {"+", "-", "*", "/"} and len(stack) >= 2
        b = stack.pop()
        a = stack.pop()
        if token == "+":
            stack.append(a + b)
        elif token == "-":
            stack.append(a - b)
        elif token == "*":
            stack.append(a * b)
        else:
            stack.append(_bash_div(a, b))
    assert len(stack) == 1
    return stack[0]


def _http_request(expression):
    request = (
        "GET /evaluate HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        f"X-Expr: {expression}\r\n"
        "Connection: close\r\n\r\n"
    ).encode("ascii")

    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
        sock.settimeout(5)
        sock.sendall(request)
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(4096)
            assert chunk, "Server closed the connection before completing HTTP headers"
            data += chunk
            assert len(data) < 65536, "HTTP headers are unreasonably large"

        raw_headers, body = data.split(b"\r\n\r\n", 1)
        header_lines = raw_headers.split(b"\r\n")
        assert header_lines[0] == b"HTTP/1.1 200 OK", f"Bad HTTP status line: {header_lines[0]!r}"

        headers = {}
        for line in header_lines[1:]:
            assert b":" in line, f"Malformed HTTP header: {line!r}"
            name, value = line.split(b":", 1)
            headers[name.decode("latin1").strip().lower()] = value.decode("latin1").strip()
        assert headers.get("content-type", "").lower() == "text/plain", "Missing or incorrect Content-Type header"

        if "content-length" in headers:
            expected_length = int(headers["content-length"])
            while len(body) < expected_length:
                chunk = sock.recv(4096)
                assert chunk, "Response ended before Content-Length bytes were received"
                body += chunk
            assert len(body) == expected_length, "Response contained bytes beyond Content-Length"
        else:
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                body += chunk
        return body


def test_live_server_and_executed_benchmark():
    # Remove a server the agent may have left running, then execute the submitted
    # server artifact ourselves so placeholders cannot pass on static files alone.
    subprocess.run(["pkill", "-f", "/home/user/rpn_server.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "socat"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nc"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)

    server = subprocess.Popen(
        ["/home/user/rpn_server.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
        text=True,
    )
    try:
        expressions = []
        for _ in range(8):
            a, b, c, d = [secrets.randbelow(80) + 1 for _ in range(4)]
            expressions.extend([
                f"{a} {b} + {c} * {d} -",
                f"{a} {b} - {c} * {d} +",
                f"{a} {b} * {c} + {d} /",
            ])

        # Retry only while the listening socket is starting. Once a response is
        # obtained, all HTTP and result checks are strict.
        first = expressions.pop(0)
        deadline = time.time() + 8
        while True:
            try:
                body = _http_request(first)
                break
            except (ConnectionRefusedError, ConnectionResetError, socket.timeout, OSError):
                if server.poll() is not None:
                    stderr = server.stderr.read() if server.stderr else ""
                    raise AssertionError(f"rpn_server.sh exited before serving requests: {stderr}")
                if time.time() >= deadline:
                    raise AssertionError("rpn_server.sh did not listen on port 8080")
                time.sleep(0.1)
        expected = _evaluate_rpn(first)
        assert body == f"{expected}\n".encode(), f"Wrong body for {first!r}: {body!r}"

        for expression in expressions:
            expected = _evaluate_rpn(expression)
            body = _http_request(expression)
            assert body == f"{expected}\n".encode(), f"Wrong body for {expression!r}: {body!r}"
    finally:
        _stop_process_group(server)

    # Run benchmark.sh against an instrumented HTTP service. This proves that it
    # actually performs 50 sequential requests with the required path and header.
    subprocess.run(["pkill", "-x", "socat"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nc"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    for path in ["/home/user/responses.txt", "/home/user/benchmark_result.txt", "/tmp/benchmark_probe.json", "/tmp/benchmark_probe.ready"]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    probe_source = r'''
import http.server, json, threading, time
LOG = "/tmp/benchmark_probe.json"
state = {"requests": [], "active": 0, "max_active": 0}
lock = threading.Lock()

def save():
    with open(LOG + ".tmp", "w") as f:
        json.dump(state, f)
    import os
    os.replace(LOG + ".tmp", LOG)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        with lock:
            state["active"] += 1
            state["max_active"] = max(state["max_active"], state["active"])
            state["requests"].append({"path": self.path, "expr": self.headers.get("X-Expr")})
            save()
        try:
            time.sleep(0.025)
            body = b"5\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
        finally:
            with lock:
                state["active"] -= 1
                save()
    def log_message(self, *args):
        pass

class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True

server = Server(("127.0.0.1", 8080), Handler)
with open("/tmp/benchmark_probe.ready", "w") as f:
    f.write("ready")
server.serve_forever()
'''
    with open("/tmp/benchmark_probe.py", "w") as f:
        f.write(textwrap.dedent(probe_source))

    probe = subprocess.Popen(
        [sys.executable, "/tmp/benchmark_probe.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
        text=True,
    )
    try:
        deadline = time.time() + 5
        while not os.path.exists("/tmp/benchmark_probe.ready"):
            if probe.poll() is not None:
                raise AssertionError(f"Benchmark probe failed to start: {probe.stderr.read()}")
            assert time.time() < deadline, "Benchmark probe did not start"
            time.sleep(0.05)

        completed = subprocess.run(
            ["/home/user/benchmark.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert completed.returncode == 0, f"benchmark.sh failed:\n{completed.stderr}"
        time.sleep(0.2)

        assert os.path.exists("/tmp/benchmark_probe.json"), "benchmark.sh sent no HTTP requests"
        with open("/tmp/benchmark_probe.json") as f:
            observed = json.load(f)
        requests = observed["requests"]
        assert len(requests) == 50, f"Expected 50 benchmark requests, observed {len(requests)}"
        required_expr = "15 7 1 1 + - / 3 * 2 1 1 + + -"
        for i, request in enumerate(requests, 1):
            assert request["path"] == "/evaluate", f"Request {i} used path {request['path']!r}"
            assert request["expr"] == required_expr, f"Request {i} used X-Expr {request['expr']!r}"
        assert observed["max_active"] == 1, "Benchmark requests were not sequential"

        with open("/home/user/responses.txt") as f:
            lines = f.read().strip().splitlines()
        assert len(lines) == 50, f"Expected exactly 50 freshly generated response lines, found {len(lines)}"
        assert all(line.strip() == "5" for line in lines), "Fresh benchmark responses were not all 5"

        with open("/home/user/benchmark_result.txt") as f:
            timing = f.read().strip()
        assert timing, "Fresh benchmark_result.txt is empty"
        assert re.search(r"\d", timing), "benchmark_result.txt does not contain a measured duration"
    finally:
        _stop_process_group(probe)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
