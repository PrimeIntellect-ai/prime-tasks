#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any server left running by the agent so the verifier executes server.py itself.
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8080/tcp >/dev/null 2>&1 || true
fi
pkill -f '/home/user/server.py' >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import concurrent.futures
import os
import random
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

SERVER_PATH = "/home/user/server.py"
LOG_PATH = "/home/user/perf.log"
PROJECT = "/home/user/rust_proj"
BIN_PATH = "/home/user/rust_proj/target/debug/rust_proj"

rng = random.SystemRandom()
a, b, c, d = [rng.randint(3, 40) for _ in range(4)]
DYNAMIC_CASES = [
    (f"{a}*({b}+{c})-{d}", a * (b + c) - d),
    (f"({a}*{b})/{b}+{c}", a + c),
    (f"(({a}+{b})*({c}-{d}))", (a + b) * (c - d)),
]
for _ in range(12):
    x, y, z = rng.randint(2, 30), rng.randint(2, 30), rng.randint(2, 30)
    DYNAMIC_CASES.append((f"({x}+{y})*{z}-{y}", (x + y) * z - y))


def request_expr(expr, timeout=10):
    query = urllib.parse.urlencode({"expr": expr})
    with urllib.request.urlopen(f"http://127.0.0.1:8080/evaluate?{query}", timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


@pytest.fixture(scope="session", autouse=True)
def running_server_and_rebuilt_project():
    assert os.path.isfile(SERVER_PATH), f"{SERVER_PATH} does not exist"

    with open(SERVER_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SERVER_PATH)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split('.')[0])
    assert imported.intersection({"asyncio", "aiohttp"}), "server.py does not use asyncio/aiohttp"
    assert any(isinstance(node, (ast.AsyncFunctionDef, ast.AsyncFor, ast.AsyncWith)) for node in ast.walk(tree)), \
        "server.py does not contain asynchronous server logic"

    with open(LOG_PATH, "w", encoding="utf-8"):
        pass

    server = subprocess.Popen(
        ["python3", SERVER_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.time() + 15
        while time.time() < deadline:
            assert server.poll() is None, "server.py exited before accepting requests"
            try:
                status, body = request_expr("1+1", timeout=1)
                if status == 200 and body.strip() == "2":
                    break
            except (OSError, urllib.error.URLError):
                time.sleep(0.1)
        else:
            pytest.fail("server.py did not listen successfully on 127.0.0.1:8080")

        # Remove any fabricated executable and force this package and build.rs to run again.
        subprocess.run(
            ["/opt/rust/bin/cargo", "clean", "-p", "rust_proj"],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=60,
        )
        if os.path.lexists(BIN_PATH):
            os.remove(BIN_PATH)
        build = subprocess.run(
            ["/opt/rust/bin/cargo", "build"],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=240,
        )
        assert build.returncode == 0, f"cargo build failed:\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
        assert server.poll() is None, "server.py exited while cargo build was running"
        yield
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)


def test_perf_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original assertions for the build.rs expressions.
    expr1_pattern = r"\[EXPR\]\s*10\*\(\s*5\s*\+\s*5\s*\)\s*\[RESULT\]\s*100\s*\[TIME_US\]\s*\d+"
    assert re.search(expr1_pattern, content), "Log file does not contain the expected entry for '10*(5+5)'."
    expr2_pattern = r"\[EXPR\]\s*\(\s*100\s*/\s*10\s*\)\s*-\s*2\s*\[RESULT\]\s*8\s*\[TIME_US\]\s*\d+"
    assert re.search(expr2_pattern, content), "Log file does not contain the expected entry for '(100/10)-2'."


def test_rust_binary_exists():
    assert os.path.isfile(BIN_PATH), f"Rust binary {BIN_PATH} does not exist. Did the compilation succeed?"
    assert os.access(BIN_PATH, os.X_OK), f"Rust binary {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cargo output is not an ELF executable"


def test_rust_binary_output():
    assert os.path.isfile(BIN_PATH), f"Rust binary {BIN_PATH} does not exist."
    result = subprocess.run([BIN_PATH], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running the Rust binary failed with return code {result.returncode}."
    expected_output = "Values are: 100 and 8"
    assert expected_output in result.stdout, f"Expected output '{expected_output}' not found in binary output: {result.stdout}"


def test_server_evaluates_generated_requests_concurrently():
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(DYNAMIC_CASES)) as pool:
        futures = [pool.submit(request_expr, expr) for expr, _ in DYNAMIC_CASES]
        responses = [future.result(timeout=15) for future in futures]

    for (expr, expected), (status, body) in zip(DYNAMIC_CASES, responses):
        assert status == 200, f"Unexpected status for {expr}: {status}"
        assert body == str(expected), f"Wrong or non-plain response for {expr}: {body!r}"


def test_expression_evaluation_is_safe():
    marker = f"/tmp/server_eval_escape_{os.getpid()}"
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    attack = f"__import__('os').system('touch {marker}')"
    try:
        request_expr(attack)
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    assert not os.path.exists(marker), "Expression evaluation executed arbitrary Python code"


def test_generated_requests_are_benchmarked_and_logged():
    deadline = time.time() + 5
    missing = list(DYNAMIC_CASES)
    while time.time() < deadline:
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        missing = []
        for expr, expected in DYNAMIC_CASES:
            pattern = re.compile(
                r"^\[EXPR\] " + re.escape(expr) +
                r" \[RESULT\] " + re.escape(str(expected)) +
                r" \[TIME_US\] \d+$"
            )
            if not any(pattern.fullmatch(line) for line in lines):
                missing.append((expr, expected))
        if not missing:
            break
        time.sleep(0.1)
    assert not missing, f"Missing exact benchmark log entries for generated requests: {missing}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
