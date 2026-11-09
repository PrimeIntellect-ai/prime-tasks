#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'BACKEND_EOF' > /tmp/verifier_upstream.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length_header = self.headers.get("Content-Length", "0")
        length = int(length_header)
        body = self.rfile.read(length)
        status = 201 if self.path.startswith("/verify-status-") else 200
        response = {
            "received_path": self.path,
            "received_body": body.decode("utf-8"),
            "content_length": length_header,
            "content_type": self.headers.get("Content-Type"),
        }
        encoded = json.dumps(response).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass

HTTPServer.allow_reuse_address = True
HTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
BACKEND_EOF

pkill -f '^python3 /home/user/upstream.py$' 2>/dev/null || true
sleep 0.3
python3 /tmp/verifier_upstream.py >/tmp/verifier_upstream.log 2>&1 &
export VERIFIER_BACKEND_PID=$!

pkill -f 'python3 .*proxy.py' 2>/dev/null || true
sleep 0.3
cd /home/user/workspace 2>/dev/null || true
python3 /home/user/workspace/proxy.py >/tmp/verifier_proxy.log 2>&1 &
export VERIFIER_PROXY_PID=$!

for i in $(seq 1 30); do
    nc -z 127.0.0.1 9000 >/dev/null 2>&1 && nc -z 127.0.0.1 8080 >/dev/null 2>&1 && break
    sleep 0.2
done

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request

import pytest

WORKSPACE = "/home/user/workspace"
SANITIZER_PATH = os.path.join(WORKSPACE, "sanitizer.py")
TEST_PATH = os.path.join(WORKSPACE, "test_sanitizer.py")
PROXY_PATH = os.path.join(WORKSPACE, "proxy.py")


def assert_live_python_process(env_name, expected_fragment):
    pid = int(os.environ[env_name])
    stat_path = f"/proc/{pid}/stat"
    assert os.path.exists(stat_path), f"{expected_fragment} process exited"
    with open(stat_path, "r") as f:
        assert f.read().split()[2] != "Z", f"{expected_fragment} process is a zombie"
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    assert expected_fragment in cmdline, f"Expected running process for {expected_fragment}, got {cmdline!r}"


def load_sanitizer():
    module_name = "verified_sanitizer_" + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(module_name, SANITIZER_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "sanitize_payload"), "sanitize_payload function missing in sanitizer.py"
    assert callable(module.sanitize_payload), "sanitize_payload is not callable"
    return module


def clean(value):
    if isinstance(value, dict):
        return {key: clean(item) for key, item in value.items() if not key.startswith("_")}
    if isinstance(value, list):
        return [clean(item) for item in value]
    return value


def expected_bytes(value):
    return json.dumps(clean(value), sort_keys=True, separators=(",", ":")).encode("utf-8")


def backend_response(path, body):
    return json.dumps({
        "received_path": path,
        "received_body": body.decode("utf-8"),
        "content_length": str(len(body)),
        "content_type": "application/json",
    }).encode("utf-8")


def post_proxy(path, raw):
    request = urllib.request.Request(
        "http://127.0.0.1:8080" + path,
        data=raw,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status, response.read()


def test_success_file():
    success_file = os.path.join(WORKSPACE, "SUCCESS")
    assert os.path.exists(success_file), f"{success_file} does not exist."
    with open(success_file, "r") as f:
        content = f.read().strip()
    assert "DONE" in content, f"{success_file} does not contain 'DONE'."


def test_required_artifacts_and_processes():
    assert os.path.isfile(SANITIZER_PATH), f"{SANITIZER_PATH} is not a regular file"
    assert os.path.isfile(TEST_PATH), f"{TEST_PATH} is not a regular file"
    assert os.path.isfile(PROXY_PATH), f"{PROXY_PATH} is not a regular file"
    assert_live_python_process("VERIFIER_BACKEND_PID", "verifier_upstream.py")
    assert_live_python_process("VERIFIER_PROXY_PID", "proxy.py")


def test_pytest_suite_passes():
    assert os.path.exists(TEST_PATH), f"{TEST_PATH} does not exist."
    result = subprocess.run(
        [sys.executable, "-m", "pytest", TEST_PATH],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"pytest suite failed:\n{result.stdout}\n{result.stderr}"


def test_authored_suite_has_three_tests_and_covers_required_behaviors():
    with open(TEST_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=TEST_PATH)
    test_functions = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_")
    ]
    assert len(test_functions) >= 3, "test_sanitizer.py must define at least three distinct test functions"

    mutants = {
        "top-level private-key removal": '''import json\ndef sanitize_payload(json_bytes):\n def walk(x, depth=0):\n  if isinstance(x, dict):\n   return {k: walk(x[k], depth+1) for k in sorted(x) if depth == 0 or not k.startswith("_")}\n  if isinstance(x, list): return [walk(v, depth+1) for v in x]\n  return x\n return json.dumps(walk(json.loads(json_bytes)), separators=(",", ":")).encode()\n''',
        "deep private-key removal": '''import json\ndef sanitize_payload(json_bytes):\n def walk(x, depth=0):\n  if isinstance(x, dict):\n   return {k: walk(x[k], depth+1) for k in sorted(x) if not (depth == 0 and k.startswith("_"))}\n  if isinstance(x, list): return [walk(v, depth+1) for v in x]\n  return x\n return json.dumps(walk(json.loads(json_bytes)), separators=(",", ":")).encode()\n''',
        "list-order preservation": '''import json\ndef sanitize_payload(json_bytes):\n def walk(x):\n  if isinstance(x, dict): return {k: walk(x[k]) for k in sorted(x) if not k.startswith("_")}\n  if isinstance(x, list): return [walk(v) for v in reversed(x)]\n  return x\n return json.dumps(walk(json.loads(json_bytes)), separators=(",", ":")).encode()\n''',
        "alphabetical key sorting": '''import json\ndef sanitize_payload(json_bytes):\n def walk(x):\n  if isinstance(x, dict): return {k: walk(v) for k, v in x.items() if not k.startswith("_")}\n  if isinstance(x, list): return [walk(v) for v in x]\n  return x\n return json.dumps(walk(json.loads(json_bytes)), separators=(",", ":")).encode()\n''',
    }

    with open(SANITIZER_PATH, "rb") as f:
        original = f.read()
    try:
        for behavior, mutant in mutants.items():
            with open(SANITIZER_PATH, "w", encoding="utf-8") as f:
                f.write(mutant)
            shutil.rmtree(os.path.join(WORKSPACE, "__pycache__"), ignore_errors=True)
            result = subprocess.run(
                [sys.executable, "-m", "pytest", "-q", TEST_PATH],
                cwd=WORKSPACE,
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert result.returncode != 0, (
                f"The authored tests do not detect broken {behavior}. "
                f"Mutant output:\n{result.stdout}\n{result.stderr}"
            )
    finally:
        with open(SANITIZER_PATH, "wb") as f:
            f.write(original)
        shutil.rmtree(os.path.join(WORKSPACE, "__pycache__"), ignore_errors=True)


def test_sanitizer_module():
    sanitizer = load_sanitizer()
    raw_payload = b'{"z": 1, "_hidden": "secret", "a": {"_ignore": true, "c": [3, 2, 1], "b": 2}}'
    expected = b'{"a":{"b":2,"c":[3,2,1]},"z":1}'
    result = sanitizer.sanitize_payload(raw_payload)
    assert result == expected, f"sanitize_payload returned {result} instead of {expected}"


def test_sanitizer_on_unpredictable_recursive_inputs():
    sanitizer = load_sanitizer()
    token = secrets.token_hex(12)
    payloads = [
        {
            "z" + token: [
                {"q" + token: 7, "_secret" + token: "remove", "a" + token: [3, 1, 2]},
                [False, {"_deep" + token: 9, "b" + token: None, "a" + token: 1}],
            ],
            "_root" + token: {"keep": False},
            "a" + token: {"z": 0, "_private": 2, "a": {"_x": 1, "ok": "yes"}},
        },
        [{"z": 2, "_x" + token: 3, "a": 1}, 4, [3, 2, 1]],
        {"b" + token: "text", "a" + token: 1.25, "_" + token: True},
        [True, None, "unchanged", 17],
    ]
    for value in payloads:
        raw = json.dumps(value, indent=2).encode("utf-8")
        result = sanitizer.sanitize_payload(raw)
        assert isinstance(result, bytes), "sanitize_payload must return bytes"
        assert result == expected_bytes(value)


def test_proxy_server():
    raw_payload = b'{"z": 1, "_hidden": "secret", "a": {"_ignore": true, "c": [3, 2, 1], "b": 2}}'
    expected_body = '{"a":{"b":2,"c":[3,2,1]},"z":1}'
    try:
        status, resp_body = post_proxy("/api/test", raw_payload)
        assert status == 200, f"Proxy returned status {status}"
    except Exception as e:
        pytest.fail(f"Failed to communicate with proxy server on port 8080: {e}")
    try:
        resp_json = json.loads(resp_body.decode("utf-8"))
    except json.JSONDecodeError:
        pytest.fail(f"Proxy did not return valid JSON: {resp_body!r}")
    received_body = resp_json.get("received_body", "")
    assert received_body == expected_body, f"Proxy did not sanitize correctly. Expected: '{expected_body}', Got: '{received_body}'"
    assert resp_json.get("received_path") == "/api/test", "Proxy did not preserve the URL path."


def test_proxy_forwards_dynamic_paths_bodies_headers_status_and_exact_response():
    token = secrets.token_hex(12)
    cases = [
        {
            "z" + token: 1,
            "_top" + token: "gone",
            "a" + token: [{"z": 4, "_nested" + token: 5, "a": 3}, 2, 1],
        },
        [{"d": 4, "_c" + token: 3, "b": [{"_a": 0, "x": 1}]}, "tail"],
        {"m": {"z": [5, 4, 3], "_y": 8, "a": False}, "a": None},
    ]
    for index, value in enumerate(cases):
        path = f"/verify-status-{token}/case-{index}"
        raw = json.dumps(value, indent=1).encode("utf-8")
        expected = expected_bytes(value)
        status, response_body = post_proxy(path, raw)
        assert status == 201, "Proxy did not return the upstream status code"
        assert response_body == backend_response(path, expected), (
            "Proxy did not preserve the path, forward the sanitized body with the required "
            "Content-Length and Content-Type, or return the exact upstream response body"
        )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
RESULT=$?
if [ "$RESULT" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
