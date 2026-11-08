#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import shutil
import subprocess
import tempfile
import time

ROUTES_CONF = "/home/user/routes.conf"
FAST_WAF = "/home/user/fast_waf"
SOURCE = "/home/user/fast_waf.c"
TEST_LOG = "/home/user/test_run.log"
ORACLE = "/app/legacy_waf_oracle"


def patched_config_bytes():
    with tempfile.TemporaryDirectory() as td:
        shutil.copyfile("/app/routes_base.conf", os.path.join(td, "routes_base.conf"))
        shutil.copyfile("/app/security_update.patch", os.path.join(td, "security_update.patch"))
        with open(os.path.join(td, "security_update.patch"), "rb") as patch_input:
            proc = subprocess.run(
                ["patch", "-s"], cwd=td, stdin=patch_input,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
        assert proc.returncode == 0, f"Could not construct expected patched configuration: {proc.stderr.decode(errors='replace')}"
        with open(os.path.join(td, "routes_base.conf"), "rb") as f:
            return f.read()


def parse_routes(config_bytes):
    routes = {}
    for raw in config_bytes.decode().splitlines():
        fields = raw.split()
        if len(fields) >= 2:
            routes[fields[0]] = fields[1]
    return routes


def expected_output(config_bytes, request_text):
    routes = parse_routes(config_bytes)
    counts = {}
    output = []
    for line in request_text.splitlines():
        if not line:
            continue
        fields = line.split()
        if len(fields) < 4:
            continue
        try:
            timestamp = int(fields[0])
        except ValueError:
            continue
        ip, method, path = fields[1], fields[2], fields[3]
        key = (ip, timestamp)
        counts[key] = counts.get(key, 0) + 1
        if counts[key] > 10:
            action = "DENIED_RATE_LIMIT"
        else:
            matches = [(len(prefix), service) for prefix, service in routes.items() if path.startswith(prefix)]
            if matches:
                action = "ROUTED_TO_" + max(matches, key=lambda item: item[0])[1]
            else:
                action = "DENIED_INVALID_ROUTE"
        output.append(f"{ip} {path} -> {action}")
    return output


def run_program(program, config_path, request_text, timeout=30):
    proc = subprocess.run(
        [program, config_path], input=request_text,
        capture_output=True, text=True, timeout=timeout
    )
    assert proc.returncode == 0, f"{program} exited with {proc.returncode}: {proc.stderr[:1000]}"
    return proc.stdout.splitlines()


def check_behavior(config_bytes, request_text, use_home_config=False):
    expected = expected_output(config_bytes, request_text)
    with tempfile.TemporaryDirectory() as td:
        if use_home_config:
            config_path = ROUTES_CONF
        else:
            config_path = os.path.join(td, "routes.conf")
            with open(config_path, "wb") as f:
                f.write(config_bytes)

        oracle_output = run_program(ORACLE, config_path, request_text)
        assert oracle_output == expected, "Verifier model disagrees with legacy oracle"
        candidate_output = run_program(FAST_WAF, config_path, request_text)
        assert candidate_output == expected, "fast_waf produced incorrect routing or rate-limit decisions"


def deterministic_requests():
    lines = ["", "malformed", "not-a-time 1.2.3.4 GET /api/v1/users"]
    paths = [
        "/api/v1/users", "/api/v1/users/42", "/api/v1/auth", "/api/v1/billing/invoice",
        "/api/v1/orders", "/api/v1/productsXYZ", "/api/v1/secure", "/api/v1/secure/admin",
        "/api/v1/login", "/api/v2/data", "/health", "/unknown/path"
    ]
    for i, path in enumerate(paths):
        lines.append(f"{1700000000 + i} 192.0.2.{i + 1} GET {path}")

    # Exact-timestamp, per-IP buckets: invalid routes also consume capacity.
    for i in range(16):
        path = "/api/v1/users" if i % 2 == 0 else "/not/a/route"
        lines.append(f"1800000000 198.51.100.7 POST {path}")
    for i in range(12):
        lines.append(f"1800000000 198.51.100.8 DELETE /api/v1/secure/{i}")
    for i in range(12):
        lines.append(f"1800000001 198.51.100.7 PUT /api/v1/orders/{i}")
    for i in range(12):
        lines.append(f"1799999999 198.51.100.7 GET /api/v1/products/{i}")
    return "\n".join(lines) + "\n"


def randomized_requests(seed=731947, count=12000):
    rng = random.Random(seed)
    ips = [f"203.0.113.{i}" for i in range(1, 13)]
    timestamps = [1900000000 + i for i in range(7)]
    methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    bases = [
        "/api/v1/users", "/api/v1/auth", "/api/v1/billing", "/api/v1/orders",
        "/api/v1/products", "/api/v1/secure", "/api/v1", "/api/v2/data",
        "/unknown", "/", "/api/v1/securely"
    ]
    lines = []
    for i in range(count):
        base = rng.choice(bases)
        suffix = rng.choice(["", "/child", f"/{rng.randrange(1000)}", "XYZ"])
        lines.append(f"{rng.choice(timestamps)} {rng.choice(ips)} {rng.choice(methods)} {base}{suffix}")
    return "\n".join(lines) + "\n"


def generate_performance_requests(filepath, num_requests=200000):
    rng = random.Random(4201337)
    ips = [f"192.168.1.{i}" for i in range(1, 255)] + [f"10.0.0.{i}" for i in range(1, 255)]
    methods = ["GET", "POST", "PUT", "DELETE"]
    paths = [
        "/api/v1/users", "/api/v1/login", "/api/v1/logout", "/api/v1/settings",
        "/api/v2/data", "/health", "/metrics", "/unknown/path", "/api/v1/secure"
    ]
    current_time = 1600000000
    with open(filepath, "w") as f:
        for _ in range(num_requests):
            if rng.random() < 0.2:
                current_time += 1
            f.write(f"{current_time} {rng.choice(ips)} {rng.choice(methods)} {rng.choice(paths)}\n")


def test_fast_waf_performance_and_accuracy():
    assert os.path.isfile(ROUTES_CONF), f"routes.conf is missing at {ROUTES_CONF}"
    assert os.path.isfile(FAST_WAF), f"fast_waf binary is missing at {FAST_WAF}"
    assert os.access(FAST_WAF, os.X_OK), f"fast_waf at {FAST_WAF} is not executable"
    assert os.path.isfile(SOURCE), f"fast_waf.c is missing at {SOURCE}"
    assert os.path.isfile(TEST_LOG), f"test_run.log is missing at {TEST_LOG}"
    with open(FAST_WAF, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_waf is not a compiled ELF executable"
    assert not filecmp.cmp(FAST_WAF, ORACLE, shallow=False), "fast_waf must not be a byte-identical copy of the oracle"

    expected_config = patched_config_bytes()
    with open(ROUTES_CONF, "rb") as f:
        actual_config = f.read()
    assert actual_config == expected_config, "routes.conf is not the result of applying security_update.patch to routes_base.conf"

    check_behavior(expected_config, deterministic_requests(), use_home_config=True)
    check_behavior(expected_config, randomized_requests(), use_home_config=True)

    custom_config = (
        b"/a A_SERVICE\n"
        b"/a/b B_SERVICE\n"
        b"/a/b/c C_SERVICE\n"
        b"/dup OLD_SERVICE\n"
        b"ignored_only_one_field\n"
        b"/dup NEW_SERVICE trailing fields are ignored\n"
        b"/z Z_SERVICE\n"
    )
    custom_lines = [
        "2000000000 10.1.1.1 GET /a",
        "2000000001 10.1.1.1 GET /a/other",
        "2000000002 10.1.1.1 GET /a/b",
        "2000000003 10.1.1.1 GET /a/b/c/more",
        "2000000004 10.1.1.1 GET /dup/value",
        "2000000005 10.1.1.1 GET /zebra",
        "2000000006 10.1.1.1 GET /none",
    ]
    for i in range(14):
        custom_lines.append(f"2000000100 10.9.8.7 GET /a/b/c/{i}")
    check_behavior(custom_config, "\n".join(custom_lines) + "\n")

    requests_file = "/tmp/large_requests.txt"
    generate_performance_requests(requests_file, 200000)

    with open(requests_file, "r") as inp:
        start_time = time.time()
        oracle_proc = subprocess.run([ORACLE, ROUTES_CONF], stdin=inp, capture_output=True, text=True)
        oracle_time = time.time() - start_time
    assert oracle_proc.returncode == 0, "Oracle failed to run"
    oracle_output = oracle_proc.stdout.strip().split("\n")

    with open(requests_file, "r") as inp:
        start_time = time.time()
        fast_waf_proc = subprocess.run([FAST_WAF, ROUTES_CONF], stdin=inp, capture_output=True, text=True)
        fast_waf_time = time.time() - start_time
    assert fast_waf_proc.returncode == 0, "fast_waf failed to run"
    fast_waf_output = fast_waf_proc.stdout.strip().split("\n")

    assert len(fast_waf_output) == len(oracle_output), f"Output length mismatch: expected {len(oracle_output)}, got {len(fast_waf_output)}"
    matches = sum(1 for o, f in zip(oracle_output, fast_waf_output) if o == f)
    accuracy = matches / len(oracle_output)
    speedup = oracle_time / fast_waf_time if fast_waf_time > 0 else float("inf")
    assert accuracy >= 0.999, f"Decision Accuracy={accuracy:.4f} is below threshold 0.999"
    assert speedup >= 1.5, f"Speedup={speedup:.2f}x is below threshold 1.5x (Oracle: {oracle_time:.4f}s, Fast WAF: {fast_waf_time:.4f}s)"

    with open(ROUTES_CONF, "rb") as f:
        assert f.read() == expected_config, "routes.conf was modified during verification"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
