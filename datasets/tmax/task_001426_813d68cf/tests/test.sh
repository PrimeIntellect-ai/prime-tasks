#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import difflib
import os
import random
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

EVALUATOR_SOURCE = "/home/user/evaluator.c"
EVALUATOR_BINARY = "/tmp/evaluator_under_test"
FORMULAS_PATH = "/home/user/formulas_v2.txt"
COSTS_V2_PATH = "/home/user/costs_v2.txt"
DIFF_PATH = "/home/user/cost_diff.txt"


def _eval_expr(expr):
    def _eval(node):
        if isinstance(node, ast.Num):
            return node.n
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.BinOp):
            left = _eval(node.left)
            right = _eval(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Mult):
                return left * right
            raise ValueError(f"Unsupported operator: {node.op}")
        if isinstance(node, ast.Expression):
            return _eval(node.body)
        raise ValueError(f"Unsupported node type: {type(node)}")

    return _eval(ast.parse(expr, mode="eval"))


def _expected_from_formulas(path):
    expected = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            try:
                mod_expr, checksum_str = line.split("|", 1)
                mod_str, expr_str = mod_expr.split(":", 1)
                mod = mod_str.strip()
                expr = expr_str.strip()
                checksum = int(checksum_str.strip())
                calculated = 0
                for char in expr:
                    calculated ^= ord(char)
                if calculated == checksum:
                    expected.append(f"{mod}: {_eval_expr(expr)}")
            except Exception:
                pass
    return expected


@pytest.fixture(scope="session")
def evaluator_binary():
    assert os.path.isfile(EVALUATOR_SOURCE), f"{EVALUATOR_SOURCE} is missing."
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", EVALUATOR_SOURCE, "-o", EVALUATOR_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"evaluator.c did not compile:\n{result.stderr}"
    assert os.path.isfile(EVALUATOR_BINARY) and os.access(EVALUATOR_BINARY, os.X_OK)
    return EVALUATOR_BINARY


def test_evaluator_c_exists():
    assert os.path.isfile(EVALUATOR_SOURCE), "/home/user/evaluator.c is missing."


def test_evaluator_executes_and_created_exact_costs(evaluator_binary):
    expected_lines = _expected_from_formulas(FORMULAS_PATH)
    result = subprocess.run(
        [evaluator_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert result.returncode == 0, f"Evaluator failed on formulas_v2.txt: {result.stderr}"
    expected_output = "".join(line + "\n" for line in expected_lines)
    assert result.stdout == expected_output, "Evaluator stdout is not the required exact output."
    with open(COSTS_V2_PATH, "r", encoding="utf-8") as f:
        saved_output = f.read()
    assert saved_output == result.stdout, "costs_v2.txt is not the exact output of evaluator.c."


def test_evaluator_on_generated_inputs(evaluator_binary):
    rng = random.SystemRandom()
    values = [rng.randint(2, 97) for _ in range(12)]
    expressions = [
        f"{values[0]} + {values[1]} * ({values[2]} + {values[3]})",
        f"({values[4]} + {values[5]}) * ({values[6]} + {values[7]} * {values[8]})",
        f"{values[9]}*({values[10]}+{values[11]})+{values[0]}",
    ]
    names = [f"Generated_{rng.randrange(10**9)}_{i}" for i in range(3)]
    lines = []
    expected = []
    for name, expr in zip(names, expressions):
        checksum = 0
        for char in expr:
            checksum ^= ord(char)
        lines.append(f"{name}: {expr} | {checksum}\n")
        expected.append(f"{name}: {_eval_expr(expr)}\n")

    bad_expr = f"({values[1]} + {values[2]}) * {values[3]}"
    bad_checksum = 0
    for char in bad_expr:
        bad_checksum ^= ord(char)
    lines.insert(1, f"Invalid_{rng.randrange(10**9)}: {bad_expr} | {bad_checksum ^ 255}\n")

    with open(FORMULAS_PATH, "rb") as f:
        original = f.read()
    try:
        with open(FORMULAS_PATH, "w", encoding="utf-8", newline="") as f:
            f.writelines(lines)
        result = subprocess.run(
            [evaluator_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=5
        )
        assert result.returncode == 0, f"Evaluator failed on generated input: {result.stderr}"
        assert result.stdout == "".join(expected), (
            "Evaluator did not correctly parse, validate, skip, and evaluate generated formulas."
        )
    finally:
        with open(FORMULAS_PATH, "wb") as f:
            f.write(original)


def test_costs_v2_content():
    assert os.path.isfile(FORMULAS_PATH), f"{FORMULAS_PATH} is missing."
    assert os.path.isfile(COSTS_V2_PATH), f"{COSTS_V2_PATH} is missing."

    expected_lines = set(_expected_from_formulas(FORMULAS_PATH))
    with open(COSTS_V2_PATH, "r", encoding="utf-8") as f:
        actual_lines = set(line.strip() for line in f if line.strip())

    assert expected_lines == actual_lines, (
        f"Expected {expected_lines} in costs_v2.txt, got {actual_lines}"
    )


def test_cost_diff_content():
    v1_path = "/home/user/costs_v1.txt"
    v2_path = COSTS_V2_PATH
    assert os.path.isfile(DIFF_PATH), f"{DIFF_PATH} is missing."

    with open(v1_path, "r", encoding="utf-8") as f:
        v1_lines = sorted([line.strip() for line in f if line.strip()])
    with open(v2_path, "r", encoding="utf-8") as f:
        v2_lines = sorted([line.strip() for line in f if line.strip()])

    expected_diff = list(difflib.unified_diff(
        v1_lines, v2_lines, fromfile=v1_path, tofile=v2_path, lineterm=""
    ))
    expected_changes = [
        line for line in expected_diff
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
    ]

    with open(DIFF_PATH, "r", encoding="utf-8") as f:
        actual_diff_lines = [line.strip() for line in f]
    actual_changes = [
        line for line in actual_diff_lines
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
    ]
    assert expected_changes == actual_changes, (
        "The additions and deletions in the diff do not match the expected changes."
    )


def test_cost_diff_is_complete_unified_diff():
    with open("/home/user/costs_v1.txt", "r", encoding="utf-8") as f:
        v1_lines = sorted(line.strip() for line in f if line.strip())
    with open(COSTS_V2_PATH, "r", encoding="utf-8") as f:
        v2_lines = sorted(line.strip() for line in f if line.strip())
    expected = list(difflib.unified_diff(
        v1_lines, v2_lines, fromfile="v1", tofile="v2", lineterm=""
    ))
    with open(DIFF_PATH, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()

    assert len(actual) >= 3, "cost_diff.txt is not a unified diff."
    assert actual[0].startswith("--- "), "Unified diff is missing its old-file header."
    assert actual[1].startswith("+++ "), "Unified diff is missing its new-file header."
    assert actual[2:] == expected[2:], (
        "Unified diff hunks, ranges, context, additions, or deletions are incorrect."
    )


def _fetch(url, timeout=3):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read()


def test_file_server_on_9000():
    with open(DIFF_PATH, "rb") as f:
        expected = f.read()
    status, content = _fetch("http://localhost:9000/cost_diff.txt")
    assert status == 200
    assert content == expected, "Port 9000 is not serving /home/user/cost_diff.txt."


def test_proxy_server_diff():
    assert os.path.isfile(DIFF_PATH), f"{DIFF_PATH} is missing."
    assert os.path.isfile("/home/user/proxy.py"), "/home/user/proxy.py is missing."
    with open(DIFF_PATH, "rb") as f:
        expected_content = f.read()
    try:
        status, actual_content = _fetch("http://localhost:8080/ci/diff")
        assert status == 200, f"Expected status 200, got {status}"
        assert actual_content == expected_content, (
            "Proxy did not return the exact contents of cost_diff.txt"
        )
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to proxy server or error occurred: {e}"


def test_proxy_server_404():
    try:
        _fetch("http://localhost:8080/other")
        assert False, "Expected HTTP Error 404, but request succeeded."
    except urllib.error.HTTPError as e:
        assert e.code == 404, f"Expected HTTP Error 404, got {e.code}"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to proxy server: {e}"


def _listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def _pids_for_inodes(inodes):
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
    return pids


def _listener_pids(port):
    return _pids_for_inodes(_listener_inodes(port))


def test_expected_server_processes_are_running():
    proxy_pids = _listener_pids(8080)
    file_pids = _listener_pids(9000)
    assert proxy_pids, "No process is listening on port 8080."
    assert file_pids, "No process is listening on port 9000."
    assert proxy_pids.isdisjoint(file_pids), "Ports 8080 and 9000 must be separate services."
    proxy_cmdlines = []
    for pid in proxy_pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                proxy_cmdlines.append(f.read().replace(b"\0", b" ").decode(errors="replace"))
        except FileNotFoundError:
            pass
    assert any("/home/user/proxy.py" in cmd for cmd in proxy_cmdlines), (
        "The port 8080 listener is not the required /home/user/proxy.py process."
    )


def test_proxy_really_fetches_from_port_9000():
    old_server_pids = _listener_pids(9000)
    assert old_server_pids, "No file server was running on port 9000."
    assert old_server_pids.isdisjoint(_listener_pids(8080))
    for pid in old_server_pids:
        os.kill(pid, signal.SIGTERM)

    deadline = time.time() + 3
    while _listener_inodes(9000) and time.time() < deadline:
        time.sleep(0.05)
    for pid in old_server_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    nonce = os.urandom(32).hex().encode("ascii")
    server_code = r'''
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
payload = bytes.fromhex(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/cost_diff.txt":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
'''
    replacement = subprocess.Popen(
        ["python3", "-c", server_code, nonce.hex()],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        deadline = time.time() + 4
        while not _listener_inodes(9000) and time.time() < deadline:
            if replacement.poll() is not None:
                error = replacement.stderr.read().decode(errors="replace")
                pytest.fail(f"Could not start controlled upstream server: {error}")
            time.sleep(0.05)
        assert _listener_inodes(9000), "Controlled upstream did not start."
        status, content = _fetch("http://localhost:8080/ci/diff")
        assert status == 200
        assert content == nonce, (
            "The service on port 8080 did not proxy /ci/diff to port 9000/cost_diff.txt."
        )
    finally:
        replacement.terminate()
        try:
            replacement.wait(timeout=2)
        except subprocess.TimeoutExpired:
            replacement.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
