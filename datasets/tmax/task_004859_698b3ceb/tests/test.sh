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
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

import requests

API_URL = "http://127.0.0.1:8000/api/v1/query"
HEADERS = {"Authorization": "Bearer build-ops-xyz-99"}
SERVER = "/home/user/server.py"
PROJECT = "/home/user/matheval"
LIBRARY = os.path.join(PROJECT, "libmatheval.so")
VIDEO = "/app/build_metrics.mp4"
LOG = "/tmp/submitted_server.log"


def stop_servers():
    subprocess.run(["pkill", "-f", "[/]home/user/server.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.4)


def start_server():
    log = open(LOG, "ab", buffering=0)
    proc = subprocess.Popen(
        [sys.executable, SERVER], cwd="/home/user", stdout=log, stderr=log,
        start_new_session=True
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            log.close()
            raise AssertionError(f"server.py exited during startup; see {LOG}")
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.25):
                return proc, log
        except OSError:
            time.sleep(0.2)
    proc.terminate()
    log.close()
    raise AssertionError("server.py did not bind to 127.0.0.1:8000")


def terminate(proc, log):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=3)
        except Exception:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except Exception:
                pass
    if log is not None:
        log.close()
    stop_servers()


def extract_from_video():
    # Decode every frame through ffmpeg and classify its average RGB color.
    command = [
        "ffmpeg", "-v", "error", "-i", VIDEO, "-vf", "scale=1:1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"
    ]
    raw = subprocess.check_output(command)
    assert len(raw) % 3 == 0 and raw, "ffmpeg did not decode RGB frames"
    colors = {
        "+": (255, 0, 0), "-": (0, 255, 0), "*": (0, 0, 255),
        "1": (255, 255, 0), "(": (255, 255, 255), ")": (0, 0, 0),
        "=": (0, 255, 255), None: (128, 128, 128),
    }
    symbols = []
    for pos in range(0, len(raw), 3):
        pixel = tuple(raw[pos:pos + 3])
        symbol, reference = min(
            colors.items(), key=lambda item: sum((pixel[i] - item[1][i]) ** 2 for i in range(3))
        )
        distance = sum((pixel[i] - reference[i]) ** 2 for i in range(3)) ** 0.5
        assert distance < 45, f"unrecognized video frame color {pixel}"
        if symbol is not None:
            symbols.append(symbol)

    expressions, current = [], []
    for symbol in symbols:
        if symbol == "=":
            assert current, "empty expression in video"
            expressions.append("".join(current))
            current = []
        else:
            current.append(symbol)
    assert not current, "video has an unterminated expression"
    assert expressions == ["(11+1)*111", "11111-11"], expressions
    return expressions


def safe_integer_eval(expression):
    tree = ast.parse(expression, mode="eval")

    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult)):
            left, right = visit(node.left), visit(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            return left * right
        raise AssertionError(f"unexpected expression node: {node!r}")

    return visit(tree)


def verify_library(expressions):
    assert os.path.isfile(os.path.join(PROJECT, "Makefile")), "Makefile is missing"
    assert os.path.isfile(os.path.join(PROJECT, "evaluate.c")), "evaluate.c is missing"
    subprocess.run(["make", "clean"], cwd=PROJECT, check=True, timeout=20)
    subprocess.run(["make"], cwd=PROJECT, check=True, timeout=20)
    assert os.path.isfile(LIBRARY), "libmatheval.so was not built"
    with open(LIBRARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libmatheval.so is not an ELF shared library"

    library = ctypes.CDLL(LIBRARY)
    evaluator = library.evaluate_expression
    evaluator.argtypes = [ctypes.c_char_p]
    evaluator.restype = ctypes.c_int

    cases = list(expressions)
    rng = random.SystemRandom()
    for _ in range(10):
        a, b, c, d = [rng.randint(1, 9) for _ in range(4)]
        cases.append(f"(({a}+{b})*({c}-{d})+({a}*{c}))")
    cases.append("(" * 24 + "1+1" + ")" * 24)

    for expression in cases:
        actual = evaluator(expression.encode("ascii"))
        expected = safe_integer_eval(expression)
        assert actual == expected, (
            f"evaluate_expression({expression!r}) returned {actual}, expected {expected}"
        )


def assert_payload(response, index, expressions, expected_override=None):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    assert data.get("index") == index, f"Expected index {index}, got {data.get('index')}"
    assert data.get("expression") == expressions[index], (
        f"Expected extracted expression {expressions[index]!r}, got {data.get('expression')!r}"
    )
    expected = safe_integer_eval(expressions[index]) if expected_override is None else expected_override
    assert data.get("result") == expected, f"Expected result {expected}, got {data.get('result')}"


def main():
    assert os.path.isfile(VIDEO), "build metrics video is missing"
    assert os.path.isfile(SERVER), "server.py is missing"
    expressions = extract_from_video()

    extraction_log = "/home/user/extracted_expressions.txt"
    if os.path.exists(extraction_log):
        with open(extraction_log, encoding="utf-8") as handle:
            logged = [line.rstrip("\n") for line in handle]
        assert logged == expressions, "extracted_expressions.txt does not match the video"

    verify_library(expressions)
    stop_servers()
    proc = log = None
    backup = None
    try:
        # Preserve the original unauthorized-request assertion in an isolated rate-limit window.
        proc, log = start_server()
        response = requests.post(API_URL, json={"expression_index": 0}, timeout=3)
        assert response.status_code == 401, (
            f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"
        )
        terminate(proc, log)
        proc = log = None

        # Start with a fresh limiter and verify both extracted expressions and exact 3/minute limit.
        proc, log = start_server()
        assert_payload(requests.post(API_URL, json={"expression_index": 0}, headers=HEADERS, timeout=3), 0, expressions)
        assert_payload(requests.post(API_URL, json={"expression_index": 1}, headers=HEADERS, timeout=3), 1, expressions)
        assert_payload(requests.post(API_URL, json={"expression_index": 0}, headers=HEADERS, timeout=3), 0, expressions)
        limited = requests.post(API_URL, json={"expression_index": 0}, headers=HEADERS, timeout=3)
        assert limited.status_code == 429, (
            f"Expected 429 on the fourth authenticated request, got {limited.status_code}: {limited.text}"
        )
        terminate(proc, log)
        proc = log = None

        # Replace the library temporarily with an unpredictable probe. This proves that the API
        # actually loads and uses libmatheval.so through its C ABI instead of hard-coding answers.
        backup = tempfile.mktemp(prefix="libmatheval-backup-", suffix=".so")
        shutil.copy2(LIBRARY, backup)
        secret = random.SystemRandom().randint(200000000, 900000000)
        probe_c = tempfile.mktemp(prefix="probe-", suffix=".c")
        probe_so = tempfile.mktemp(prefix="probe-", suffix=".so")
        with open(probe_c, "w", encoding="utf-8") as handle:
            handle.write(f"int evaluate_expression(const char *expr) {{ (void)expr; return {secret}; }}\n")
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c], check=True, timeout=20)
        shutil.copy2(probe_so, LIBRARY)

        proc, log = start_server()
        probe_response = requests.post(API_URL, json={"expression_index": 1}, headers=HEADERS, timeout=3)
        assert_payload(probe_response, 1, expressions, expected_override=secret)
        terminate(proc, log)
        proc = log = None
    finally:
        if proc is not None:
            terminate(proc, log)
        if backup is not None and os.path.exists(backup):
            shutil.copy2(backup, LIBRARY)
            os.unlink(backup)
        # Leave the submitted API running with the submitted library, as required.
        stop_servers()
        final_proc, final_log = start_server()
        final_log.close()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
