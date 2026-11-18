#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import time
import urllib.parse
import urllib.request

ORACLE = "/tests/rpn_cli_reference"
CLI = "/app/rpn_cli"
FAST = "/app/fast_eval"


def generate_rpn_expr():
    length = random.randint(3, 15)
    if length % 2 == 0:
        length += 1
    stack_depth = 0
    expr = []
    for i in range(length):
        if stack_depth >= 2 and (length - i) <= stack_depth - 1:
            expr.append(random.choice(['+', '-', '*']))
            stack_depth -= 1
        elif stack_depth < 2:
            if random.random() < 0.2:
                expr.append(f"{random.randint(0,20)}.{random.randint(0,20)}.{random.randint(0,20)}")
            else:
                expr.append(str(random.randint(0, 1000)))
            stack_depth += 1
        elif random.random() < 0.5:
            if random.random() < 0.2:
                expr.append(f"{random.randint(0,20)}.{random.randint(0,20)}.{random.randint(0,20)}")
            else:
                expr.append(str(random.randint(0, 1000)))
            stack_depth += 1
        else:
            expr.append(random.choice(['+', '-', '*', 'VER_LT', 'VER_GT', 'VER_EQ']))
            stack_depth -= 1
    while stack_depth > 1:
        expr.append(random.choice(['+', '-', '*']))
        stack_depth -= 1
    return " ".join(expr)


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Binary missing: {path}"
    assert os.access(path, os.X_OK), f"Binary is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected a compiled ELF binary: {path}"


def run_cli(path, expr):
    return subprocess.run([path, expr], capture_output=True, text=True, timeout=5)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle missing: {ORACLE}"
    assert_elf_executable(CLI)
    with open(ORACLE, "rb") as f:
        oracle_bytes = f.read()
    with open(CLI, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent binary must not be a byte-identical copy of the reference"

    fixed = {
        "10.0.0 2.0.0 VER_LT": "0",
        "10.0.0 2.0.0 VER_GT": "1",
        "2.10.3 2.10.3 VER_EQ": "1",
        "1.20.0 1.3.99 VER_LT": "0",
        "3 4 + 5 *": "35",
    }
    for expr, expected in fixed.items():
        proc = run_cli(CLI, expr)
        assert proc.returncode == 0, f"Agent failed on input: {expr}"
        assert proc.stdout.strip() == expected, f"Wrong result for {expr}"

    random.seed(42)
    for _ in range(1000):
        expr = generate_rpn_expr()
        oracle_proc = run_cli(ORACLE, expr)
        agent_proc = run_cli(CLI, expr)
        if oracle_proc.returncode == 0:
            assert agent_proc.returncode == 0, f"Agent failed on input: {expr}\nOracle output: {oracle_proc.stdout}"
            assert oracle_proc.stdout.strip() == agent_proc.stdout.strip(), \
                f"Mismatch on input: {expr}\nOracle: {oracle_proc.stdout.strip()}\nAgent: {agent_proc.stdout.strip()}"


def test_nginx_config_fixed():
    with open("/app/nginx.conf", "r") as f:
        conf = f.read()
    assert "5000" in conf, "Nginx config missing port 5000 (legacy)"
    assert "5001" in conf, "Nginx config missing port 5001 (fast)"

    # Remove comments before checking that each location has the required upstream.
    active = re.sub(r"#.*", "", conf)
    legacy = re.search(r"location\s+(?:=\s*)?/api/v1/eval/legacy\s*\{([^}]*)\}", active, re.S)
    fast = re.search(r"location\s+(?:=\s*)?/api/v1/eval/fast\s*\{([^}]*)\}", active, re.S)
    assert legacy, "Missing active legacy location"
    assert fast, "Missing active fast location"
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000(?:[/;]|$)", legacy.group(1)), \
        "Legacy location must proxy to port 5000"
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5001(?:[/;]|$)", fast.group(1)), \
        "Fast location must proxy to port 5001"
    subprocess.run(["nginx", "-t", "-c", "/app/nginx.conf"], check=True, capture_output=True, text=True)


def fetch(path, timeout=2):
    with urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=timeout) as response:
        assert response.status == 200
        return response.read().decode().strip()


def test_end_to_end_services_and_routing():
    assert_elf_executable(FAST)
    processes = []
    try:
        legacy = subprocess.Popen(
            ["python3", "/app/legacy_service.py"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Keep stdin open because fast_eval waits on getchar() while serving.
        fast = subprocess.Popen(
            [FAST], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        nginx = subprocess.Popen(
            ["nginx", "-c", "/app/nginx.conf", "-g", "daemon off; pid /tmp/verifier-nginx.pid;"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes = [nginx, fast, legacy]

        deadline = time.time() + 12
        while True:
            assert legacy.poll() is None, "Legacy service exited during startup"
            assert fast.poll() is None, "Fast service exited during startup"
            assert nginx.poll() is None, "Nginx exited during startup"
            try:
                expr = urllib.parse.urlencode({"expr": "1 2 +"})
                if fetch("/api/v1/eval/legacy?" + expr) == "3" and fetch("/api/v1/eval/fast?" + expr) == "3":
                    break
            except Exception:
                pass
            if time.time() >= deadline:
                raise AssertionError("Services did not become reachable through Nginx")
            time.sleep(0.1)

        cases = {
            "10.0.0 2.0.0 VER_GT": "1",
            "10.0.0 2.0.0 VER_LT": "0",
            "2.10.3 2.10.3 VER_EQ": "1",
            "7 5 - 8 *": "16",
            "81 9 / 4 +": "13",
        }
        for expr, expected in cases.items():
            query = urllib.parse.urlencode({"expr": expr})
            legacy_result = fetch("/api/v1/eval/legacy?" + query)
            fast_result = fetch("/api/v1/eval/fast?" + query)
            assert legacy_result == expected, f"Unexpected legacy result for {expr}: {legacy_result}"
            assert fast_result == legacy_result, f"Fast/legacy mismatch for {expr}: {fast_result} != {legacy_result}"
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
        for proc in processes:
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
