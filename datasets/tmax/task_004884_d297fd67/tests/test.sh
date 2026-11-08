#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import importlib.util
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
CLASSIFY_SCRIPT = "/home/user/classify.py"
CLASSIFICATION_FILE = "/home/user/classification.json"
WAF_FILE = "/app/waf/waf.py"

nonce = secrets.token_hex(8)

def encoded_payload(value):
    return json.dumps({"payload": base64.b64encode(value.encode("utf-8")).decode("ascii")}).encode("utf-8")

DYNAMIC_CLEAN = [
    encoded_payload(f"ordinary customer message {nonce}"),
    encoded_payload(f"Please select a color from the menu, reference {nonce}"),
    encoded_payload(json.dumps({"profile": {"display_name": f"Alice-{nonce}", "theme": "light"}})),
]
DYNAMIC_EVIL = [
    encoded_payload(f"<ScRiPt>alert('{nonce}')</sCrIpT>"),
    encoded_payload(f"' OR 1=1 -- {nonce}"),
    encoded_payload(json.dumps({"query": {"filter": f"1 UNION/**/SELECT password FROM users -- {nonce}"}})),
    encoded_payload(f"<img src=x onerror=alert('{nonce}')>"),
    encoded_payload(f"cos\nsystem\n(S'echo {nonce}'\ntR."),
]
DYNAMIC_FILES = {}


def post_request(url, data):
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url}: {e}")


def assert_waf_results(url, clean_payloads, evil_payloads):
    for data in clean_payloads:
        status, _ = post_request(url, data)
        assert status == 200, f"Expected clean payload to receive 200 from {url}, got {status}"
    for data in evil_payloads:
        status, _ = post_request(url, data)
        assert status == 403, f"Expected malicious payload to receive 403 from {url}, got {status}"


def test_00_classify_script_exists_imports_waf_and_generates_report():
    assert os.path.isfile(CLASSIFY_SCRIPT), f"Classification script missing: {CLASSIFY_SCRIPT}"

    with open(CLASSIFY_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, CLASSIFY_SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{CLASSIFY_SCRIPT} is not valid Python 3: {exc}")

    imported_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "waf" or alias.name.endswith(".waf"):
                    imported_aliases.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.module and (node.module == "waf" or node.module.endswith(".waf")):
            for alias in node.names:
                if alias.name != "*":
                    imported_aliases.add(alias.asname or alias.name)

    assert imported_aliases, f"{CLASSIFY_SCRIPT} must import the updated WAF logic"
    loaded_names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load)}
    assert imported_aliases & loaded_names, "The WAF import in classify.py is never used"

    for label, directory, payloads in (
        ("clean", CLEAN_DIR, DYNAMIC_CLEAN),
        ("evil", EVIL_DIR, DYNAMIC_EVIL),
    ):
        for index, payload in enumerate(payloads):
            filename = f"case_{secrets.token_hex(10)}_{index}.json"
            path = os.path.join(directory, filename)
            with open(path, "wb") as f:
                f.write(payload)
            DYNAMIC_FILES[filename] = label

    if os.path.exists(CLASSIFICATION_FILE):
        os.remove(CLASSIFICATION_FILE)
    started = time.time()
    env = os.environ.copy()
    env["PYTHONPATH"] = "/app/waf" + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run(
        [sys.executable, CLASSIFY_SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"classify.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(CLASSIFICATION_FILE), "classify.py did not generate classification.json"
    assert os.path.getmtime(CLASSIFICATION_FILE) >= started - 1, "classification.json was not freshly generated"

    with open(CLASSIFICATION_FILE, "r", encoding="utf-8") as f:
        classification = json.load(f)
    expected_names = set(os.listdir(CLEAN_DIR)) | set(os.listdir(EVIL_DIR))
    assert set(classification) == expected_names, "classification.json must contain exactly every corpus basename"
    for filename, label in DYNAMIC_FILES.items():
        assert classification.get(filename) == label, f"Incorrect generated classification for {filename}"


def test_classification_json():
    assert os.path.isfile(CLASSIFICATION_FILE), f"Classification file missing: {CLASSIFICATION_FILE}"

    with open(CLASSIFICATION_FILE, "r") as f:
        try:
            classification = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {CLASSIFICATION_FILE}")

    clean_files = os.listdir(CLEAN_DIR)
    evil_files = os.listdir(EVIL_DIR)

    evil_bypassed = []
    clean_modified = []

    for c_file in clean_files:
        if classification.get(c_file) != "clean":
            clean_modified.append(c_file)

    for e_file in evil_files:
        if classification.get(e_file) != "evil":
            evil_bypassed.append(e_file)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (not classified 'clean'): {', '.join(clean_modified)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_submitted_waf_module_under_python3():
    assert os.path.isfile(WAF_FILE), f"WAF implementation missing: {WAF_FILE}"
    spec = importlib.util.spec_from_file_location("submitted_waf", WAF_FILE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        pytest.fail(f"waf.py could not be imported under Python 3: {exc}")
    assert hasattr(module, "WAFHandler"), "waf.py does not define WAFHandler"

    import http.server
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), module.WAFHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        assert_waf_results(f"http://127.0.0.1:{server.server_port}/", DYNAMIC_CLEAN, DYNAMIC_EVIL)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_waf_direct_http():
    clean_files = os.listdir(CLEAN_DIR)
    evil_files = os.listdir(EVIL_DIR)

    evil_bypassed = []
    clean_modified = []

    for c_file in clean_files:
        with open(os.path.join(CLEAN_DIR, c_file), "rb") as f:
            data = f.read()
        status, _ = post_request("http://localhost:5000/", data)
        if status != 200:
            clean_modified.append(c_file)

    for e_file in evil_files:
        with open(os.path.join(EVIL_DIR, e_file), "rb") as f:
            data = f.read()
        status, _ = post_request("http://localhost:5000/", data)
        if status != 403:
            evil_bypassed.append(e_file)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed WAF directly: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected by WAF directly): {', '.join(clean_modified)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))

    assert_waf_results("http://localhost:5000/", DYNAMIC_CLEAN, DYNAMIC_EVIL)


def test_end_to_end_proxy():
    clean_files = os.listdir(CLEAN_DIR)
    evil_files = os.listdir(EVIL_DIR)

    if not clean_files or not evil_files:
        pytest.fail("Corpus directories are empty.")

    c_file = clean_files[0]
    with open(os.path.join(CLEAN_DIR, c_file), "rb") as f:
        clean_data = f.read()

    status, body = post_request("http://localhost:8000/", clean_data)
    assert status == 200, f"Expected 200 OK from Proxy for clean payload, got {status}"

    try:
        resp_json = json.loads(body)
        assert resp_json.get("status") == "success" and resp_json.get("data") == "processed", \
            f"Expected backend response {{'status': 'success', 'data': 'processed'}}, got {resp_json}"
    except json.JSONDecodeError:
        pytest.fail(f"Expected JSON response from proxy/backend, got: {body}")

    e_file = evil_files[0]
    with open(os.path.join(EVIL_DIR, e_file), "rb") as f:
        evil_data = f.read()

    status, _ = post_request("http://localhost:8000/", evil_data)
    assert status == 403, f"Expected 403 Forbidden from Proxy for evil payload, got {status}"

    for data in DYNAMIC_CLEAN:
        status, body = post_request("http://localhost:8000/", data)
        assert status == 200, f"Proxy rejected a generated clean payload with status {status}"
        response = json.loads(body)
        assert response.get("status") == "success" and response.get("data") == "processed"
    for data in DYNAMIC_EVIL:
        status, _ = post_request("http://localhost:8000/", data)
        assert status == 403, f"Proxy allowed a generated malicious payload with status {status}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
