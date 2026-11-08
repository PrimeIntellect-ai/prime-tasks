#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

APP_DIR = "/home/user/app"
URL = "http://127.0.0.1:8080/api/v1/levenshtein"


def reference_distance(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def wait_for_port(open_expected, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.2)
        try:
            is_open = sock.connect_ex(("127.0.0.1", 8080)) == 0
        finally:
            sock.close()
        if is_open == open_expected:
            return True
        time.sleep(0.1)
    return False


def post_raw(body):
    req = urllib.request.Request(
        URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return urllib.request.urlopen(req, timeout=4)


def test_required_files_and_real_unit_tests():
    assert os.path.isdir(APP_DIR), f"{APP_DIR} does not exist"
    test_path = os.path.join(APP_DIR, "distance_test.go")
    assert os.path.isfile(test_path), "distance_test.go is missing"

    source = open(test_path, encoding="utf-8").read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    for literal in ('"kitten"', '"sitting"', '"flitten"', '"abc"'):
        assert literal in source_without_comments, f"Required unit-test value {literal} is missing"
    for expected in (0, 3):
        assert re.search(rf"\b{expected}\b", source_without_comments), f"Expected distance {expected} is missing from the unit tests"

    log_path = "/home/user/unit_tests.log"
    with open(log_path, "wb") as log:
        proc = subprocess.run(
            ["go", "test", "-v", "./..."],
            cwd=APP_DIR,
            stdout=log,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    assert proc.returncode == 0, f"go test failed: {proc.stderr.decode(errors='replace')}"
    assert os.path.isfile(log_path), f"Unit test log missing at {log_path}"
    content = open(log_path, encoding="utf-8").read()
    assert "PASS" in content, "The unit tests did not pass or 'PASS' is missing from the log."


def test_levenshtein_directly_on_derived_cases():
    rng = random.SystemRandom()
    alphabet = "abcxyz"
    pairs = [
        ("kitten", "sitting"),
        ("flitten", "flitten"),
        ("", "abc"),
        ("abc", ""),
        ("gumbo", "gambol"),
        ("saturday", "sunday"),
    ]
    for _ in range(30):
        a = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 13)))
        b = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 13)))
        pairs.append((a, b))

    rows = "\n".join(
        f'        {{{json.dumps(a)}, {json.dumps(b)}, {reference_distance(a, b)}}},'
        for a, b in pairs
    )
    verifier_test = f'''package main
import "testing"
func TestVerifierDerivedLevenshteinCases(t *testing.T) {{
    cases := []struct {{ a, b string; want int }}{{
{rows}
    }}
    for _, tc := range cases {{
        if got := Levenshtein(tc.a, tc.b); got != tc.want {{
            t.Fatalf("Levenshtein(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
        }}
    }}
}}
'''
    path = os.path.join(APP_DIR, "zz_verifier_generated_test.go")
    old = None
    if os.path.exists(path):
        old = open(path, "rb").read()
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(verifier_test)
        proc = subprocess.run(
            ["go", "test", "-run", "^TestVerifierDerivedLevenshteinCases$", "./..."],
            cwd=APP_DIR,
            capture_output=True,
            timeout=60,
        )
        assert proc.returncode == 0, (proc.stdout + proc.stderr).decode(errors="replace")
    finally:
        if old is None:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        else:
            with open(path, "wb") as f:
                f.write(old)


def test_e2e_script_is_executed_and_cleans_up():
    script_path = os.path.join(APP_DIR, "e2e_test.sh")
    assert os.path.isfile(script_path), "e2e_test.sh is missing"
    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True)
    assert syntax.returncode == 0, syntax.stderr.decode(errors="replace")

    source = open(script_path, encoding="utf-8").read()
    active = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"(^|[ /])curl(?:\s|$)", active), "e2e_test.sh must use curl"
    assert "&" in active, "e2e_test.sh must start the server in the background"
    assert re.search(r"\b(kill|trap)\b", active), "e2e_test.sh must clean up the server"
    assert not wait_for_port(True, timeout=0.3), "Port 8080 was already occupied before the E2E test"

    result_path = "/home/user/e2e_results.json"
    try:
        os.remove(result_path)
    except FileNotFoundError:
        pass
    proc = subprocess.run(
        ["bash", script_path],
        cwd=APP_DIR,
        capture_output=True,
        timeout=40,
    )
    assert proc.returncode == 0, (proc.stdout + proc.stderr).decode(errors="replace")
    assert os.path.isfile(result_path), f"E2E results missing at {result_path}"
    try:
        data = json.load(open(result_path, encoding="utf-8"))
    except json.JSONDecodeError:
        pytest.fail("e2e_results.json is not valid JSON")
    assert "distance" in data, "Key 'distance' not found in e2e_results.json"
    assert data["distance"] == 2, f"Expected distance 2 for 'book' and 'back', got {data['distance']}"
    assert wait_for_port(False, timeout=5), "e2e_test.sh did not clean up its server"


def test_api_server_on_varied_derived_inputs_and_errors():
    build_path = os.path.join(tempfile.gettempdir(), "levenshtein-verifier-server")
    build_proc = subprocess.run(
        ["go", "build", "-o", build_path, "."],
        cwd=APP_DIR,
        capture_output=True,
        timeout=60,
    )
    assert build_proc.returncode == 0, f"Failed to build Go app: {build_proc.stderr.decode(errors='replace')}"

    server_proc = subprocess.Popen(
        [build_path], cwd=APP_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        assert wait_for_port(True), "Server did not start on port 8080"

        rng = random.SystemRandom()
        alphabet = "abcdefxyz"
        pairs = [("apple", "apply"), ("", "abc"), ("abc", ""), ("same", "same")]
        for _ in range(20):
            a = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 11)))
            b = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 11)))
            pairs.append((a, b))

        for a, b in pairs:
            body = json.dumps({"str1": a, "str2": b}).encode()
            with post_raw(body) as response:
                assert response.status == 200
                raw = response.read().decode()
                try:
                    data = json.loads(raw)
                except json.JSONDecodeError:
                    pytest.fail(f"API response is not valid JSON: {raw}")
                want = reference_distance(a, b)
                assert data.get("distance") == want, (
                    f"Expected distance {want} for {a!r}, {b!r}, got {data.get('distance')}"
                )

        for bad_body in (b"invalid json", b"{}", b'{"str1":"x"}', b'{"str2":"x"}'):
            try:
                with post_raw(bad_body):
                    pytest.fail(f"Expected HTTP 400 for invalid or missing-field body {bad_body!r}")
            except urllib.error.HTTPError as e:
                assert e.code == 400, f"Expected HTTP 400 Bad Request, got {e.code}"
    finally:
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_proc.wait()
        try:
            os.remove(build_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
