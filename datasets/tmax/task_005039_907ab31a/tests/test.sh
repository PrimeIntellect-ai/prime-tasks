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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import re
import subprocess
import uuid
from decimal import Decimal

import pytest
import requests

URL = "http://127.0.0.1:8080/ingest"
DECODER_PATH = "/app/vendored/telemetry-decoder/decoder.py"


def recover_secret():
    commits = subprocess.check_output(
        ["git", "-C", "/app/service", "rev-list", "--all"], text=True
    ).splitlines()
    candidates = []
    for commit in commits:
        try:
            content = subprocess.check_output(
                ["git", "-C", "/app/service", "show", f"{commit}:config.py"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            continue
        match = re.search(r'^\s*SECRET\s*=\s*[\"\']([^\"\']+)[\"\']', content, re.MULTILINE)
        if match and match.group(1) != "TODO":
            candidates.append(match.group(1))
    assert candidates, "No removed authentication secret was recovered from git history."
    assert len(set(candidates)) == 1, "Git history contains ambiguous authentication secrets."
    return candidates[0]


SECRET = recover_secret()
HEADERS = {"Authorization": f"Bearer {SECRET}"}


def load_decoder():
    assert os.path.isfile(DECODER_PATH), "decoder.py is missing."
    spec = importlib.util.spec_from_file_location("submitted_decoder", DECODER_PATH)
    assert spec is not None and spec.loader is not None, "decoder.py is not an importable Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "decode", None)), "decoder.py does not provide a callable decode function."
    return module


def configured_secret():
    with open("/app/service/config.py", "r", encoding="utf-8") as f:
        tree = ast.parse(f.read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "SECRET" for t in node.targets):
            return ast.literal_eval(node.value)
    pytest.fail("/app/service/config.py does not define SECRET.")


def test_git_forensics_result_is_installed():
    assert configured_secret() == SECRET, "The service is not configured with the secret recovered from git history."


def test_service_auth():
    """Test that the service rejects unauthorized requests and accepts authorized ones."""
    try:
        resp = requests.post(URL, json={"test": "data"}, timeout=2)
        assert resp.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {resp.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")

    wrong = {"Authorization": f"Bearer wrong-{uuid.uuid4().hex}"}
    resp = requests.post(URL, headers=wrong, json={"test": uuid.uuid4().hex}, timeout=2)
    assert resp.status_code in (401, 403), "The service accepted an incorrect bearer token."

    resp = requests.post(URL, headers=HEADERS, json={"test": uuid.uuid4().hex}, timeout=2)
    assert resp.status_code == 200, f"Recovered secret was not accepted: {resp.status_code} {resp.text}"


def test_precision_fix():
    """Test that the service maintains Decimal precision for *_coord keys."""
    payload = {"x_coord": "123.4567890123456789", "data": "valid"}
    resp = requests.post(URL, headers=HEADERS, json=payload, timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    data = resp.json()
    assert "123.4567890123456789" in resp.text, "High-precision decimal value was lost in the response."

    decoder = load_decoder()
    for _ in range(12):
        key = f"{uuid.uuid4().hex}_coord"
        value = f"{uuid.uuid4().int % 1000000}.{uuid.uuid4().int:032d}"
        decoded = decoder.decode(json.dumps({key: value, "ordinary": value}).encode("utf-8"))
        assert isinstance(decoded[key], Decimal), "A *_coord value was not decoded as decimal.Decimal."
        assert str(decoded[key]) == value, "Decoder lost coordinate precision."
        assert decoded["ordinary"] == value, "Decoder unexpectedly changed a non-coordinate value."

        resp = requests.post(URL, headers=HEADERS, json={key: value}, timeout=2)
        assert resp.status_code == 200, f"Dynamic coordinate request failed: {resp.status_code} {resp.text}"
        assert resp.json()[key] == value, "Service did not preserve a dynamically generated coordinate exactly."


def test_corrupted_utf8():
    """Test that corrupted UTF-8 payloads do not crash the server."""
    bad_payload = b'{"data": "invalid \xff\xff"}'
    headers = HEADERS.copy()
    headers["Content-Type"] = "application/json"
    resp = requests.post(URL, headers=headers, data=bad_payload, timeout=2)
    assert resp.status_code != 500, "Server crashed (500) on invalid UTF-8 payload."

    decoder = load_decoder()
    marker = uuid.uuid4().hex
    decoded = decoder.decode(b'{"data":"' + marker.encode() + b'\xff\xfe"}')
    assert decoded == {"data": marker}, "Decoder did not safely ignore corrupted UTF-8 bytes."


def test_error_cache_does_not_grow_without_bound():
    decoder = load_decoder()
    for i in range(5000):
        payload = (f'{{"broken": {i} trailing}}').encode("ascii")
        try:
            decoder.decode(payload)
        except Exception:
            pass

    if hasattr(decoder, "error_cache"):
        cache = decoder.error_cache
        try:
            size = len(cache)
        except TypeError:
            pytest.fail("error_cache still exists and is not a bounded/clearable container.")
        assert size <= 1024, f"error_cache grew to {size} entries after unique failures and remains effectively unbounded."


def test_decoder_code_fixes():
    """Test that the decoder.py file was actually modified to fix the issues."""
    decoder_path = "/app/vendored/telemetry-decoder/decoder.py"
    assert os.path.isfile(decoder_path), "decoder.py is missing."
    with open(decoder_path, "r") as f:
        content = f.read()
    assert "Decimal" in content, "decoder.py does not use Decimal for precision."
    assert "float(" not in content or "float" not in content.split("Decimal")[1], "decoder.py still seems to use float() for coordinates."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
