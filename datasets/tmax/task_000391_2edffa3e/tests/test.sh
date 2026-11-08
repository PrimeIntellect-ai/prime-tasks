#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE = "/home/user/waf_simulator"
SOURCE = "/home/user/waf_simulator.rs"
ALLOWED_PORT = 8443
COOKIE_PREFIX = "X-RT-"
ALLOWED_CSP_DOMAIN = "https://assets.internal.net"


def run_simulator(executable, request_path):
    try:
        return subprocess.run(
            [executable, request_path],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"WAF simulator timed out for {request_path}")


def test_waf_simulator_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"WAF simulator executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"WAF simulator at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "WAF simulator must be a compiled native executable"


def test_waf_simulator_against_corpora():
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]

    assert len(evil_files) > 0, f"No JSON files found in evil corpus: {evil_dir}"
    assert len(clean_files) > 0, f"No JSON files found in clean corpus: {clean_dir}"

    evil_bypassed = []
    for evil_file in evil_files:
        file_path = os.path.join(evil_dir, evil_file)
        result = subprocess.run([EXECUTABLE, file_path], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(evil_file)

    clean_rejected = []
    for clean_file in clean_files:
        file_path = os.path.join(clean_dir, clean_file)
        result = subprocess.run([EXECUTABLE, file_path], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(clean_file)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_rejected)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


@pytest.fixture(scope="module")
def rebuilt_executable(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"Rust source not found at {SOURCE}"
    output = tmp_path_factory.mktemp("rust-build") / "waf_simulator"
    result = subprocess.run(
        ["rustc", SOURCE, "-o", str(output)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Rust source failed to compile: {result.stderr}"
    assert output.is_file() and os.access(output, os.X_OK)
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    return str(output)


def expected_result(request):
    if request.get("target_port") != ALLOWED_PORT:
        return 1

    headers = request.get("headers")
    if not isinstance(headers, dict):
        return 1

    cookie = headers.get("Cookie")
    if not isinstance(cookie, str):
        return 1

    auth_value = None
    for part in cookie.split(";"):
        part = part.strip()
        if part.startswith("AuthToken="):
            auth_value = part[len("AuthToken="):]
            break
    if auth_value is None or not auth_value.startswith(COOKIE_PREFIX):
        return 1

    csp = headers.get("Content-Security-Policy", "")
    if not isinstance(csp, str):
        return 1
    for directive in csp.split(";"):
        tokens = directive.strip().split()
        if tokens and tokens[0].lower() == "script-src":
            for source in tokens[1:]:
                if source not in ("'self'", ALLOWED_CSP_DOMAIN):
                    return 1
    return 0


def make_dynamic_requests():
    rng = random.SystemRandom()
    requests = []

    for _ in range(8):
        suffix = secrets.token_hex(rng.randint(3, 10))
        requests.append({
            "target_port": ALLOWED_PORT,
            "headers": {
                "Cookie": f"Session={secrets.token_hex(4)}; AuthToken={COOKIE_PREFIX}{suffix}; Theme=dark",
                "Content-Security-Policy": rng.choice([
                    "script-src 'self' https://assets.internal.net",
                    "script-src https://assets.internal.net",
                    "script-src 'self'",
                ]),
            },
            "body": secrets.token_urlsafe(18),
        })

    for _ in range(6):
        bad_port = rng.randint(1, 65535)
        while bad_port == ALLOWED_PORT:
            bad_port = rng.randint(1, 65535)
        requests.append({
            "target_port": bad_port,
            "headers": {
                "Cookie": f"AuthToken={COOKIE_PREFIX}{secrets.token_hex(6)}",
                "Content-Security-Policy": "script-src 'self' https://assets.internal.net",
            },
            "body": secrets.token_urlsafe(18),
        })

    for _ in range(6):
        wrong_prefix = rng.choice(["Y-RT-", "x-rt-", "RT-", "BAD-"])
        requests.append({
            "target_port": ALLOWED_PORT,
            "headers": {
                "Cookie": f"Other={secrets.token_hex(3)}; AuthToken={wrong_prefix}{secrets.token_hex(6)}",
                "Content-Security-Policy": "script-src 'self' https://assets.internal.net",
            },
            "body": secrets.token_urlsafe(18),
        })

    for _ in range(6):
        unauthorized = f"https://{secrets.token_hex(6)}.example.invalid"
        requests.append({
            "target_port": ALLOWED_PORT,
            "headers": {
                "Cookie": f"AuthToken={COOKIE_PREFIX}{secrets.token_hex(6)}",
                "Content-Security-Policy": f"script-src 'self' {unauthorized}",
            },
            "body": secrets.token_urlsafe(18),
        })

    rng.shuffle(requests)
    return requests


def test_randomized_requests_at_unlabeled_paths(rebuilt_executable):
    executables = [EXECUTABLE, rebuilt_executable]
    requests = make_dynamic_requests()

    with tempfile.TemporaryDirectory(prefix=f"waf-{secrets.token_hex(8)}-") as request_dir:
        cases = []
        for request in requests:
            path = Path(request_dir) / f"{secrets.token_hex(16)}.json"
            with open(path, "w", encoding="utf-8") as f:
                json.dump(request, f, separators=(",", ":"))
            cases.append((str(path), expected_result(request)))

        random.SystemRandom().shuffle(cases)
        for executable in executables:
            for path, expected in cases:
                actual = run_simulator(executable, path)
                assert actual == expected, (
                    f"{executable} returned {actual}, expected {expected}, "
                    f"for randomized request {path}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
