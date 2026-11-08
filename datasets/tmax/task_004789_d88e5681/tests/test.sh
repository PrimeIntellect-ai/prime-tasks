#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import importlib.util
import json
import os
import secrets
import sys

import pytest

SERVER_PATH = "/home/user/app/server.py"
UPLOAD_DIR = "/home/user/app/uploads"


def test_audit_report():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report missing at {report_path}"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON")

    assert data.get("attacker_ip") == "198.51.100.42", "Incorrect attacker_ip in audit report"
    assert data.get("compromised_file") == "/home/user/.bashrc", "Incorrect compromised_file in audit report"


def get_flask_app():
    assert os.path.isfile(SERVER_PATH), f"Server file missing at {SERVER_PATH}"

    module_name = "server_" + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(module_name, SERVER_PATH)
    server_module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = server_module
    try:
        spec.loader.exec_module(server_module)
    except Exception as e:
        pytest.fail(f"Failed to load server.py: {e}")

    assert hasattr(server_module, "app"), "Flask 'app' object not found in server.py"
    return server_module.app


def test_waf_ip_block():
    app = get_flask_app()
    client = app.test_client()

    response = client.get("/", environ_base={"REMOTE_ADDR": "198.51.100.42"})
    assert response.status_code == 403, "Expected HTTP 403 Forbidden for blocked IP"
    assert b"Blocked IP" in response.data, "Expected 'Blocked IP' text in response for blocked IP"

    response = client.get("/upload", environ_base={"REMOTE_ADDR": "10.0.0.5"})
    if response.status_code == 403:
        assert b"Blocked IP" not in response.data, "Normal IP was incorrectly blocked by WAF"
    assert response.status_code != 403, "Normal IP was incorrectly blocked"

    # Exercise the IP policy on unpredictable paths and methods.
    for _ in range(3):
        path = "/probe-" + secrets.token_hex(12)
        response = client.get(path, environ_base={"REMOTE_ADDR": "198.51.100.42"})
        assert response.status_code == 403
        assert b"Blocked IP" in response.data

        response = client.get(path, environ_base={"REMOTE_ADDR": "203.0.113.17"})
        assert response.status_code != 403, "WAF blocked a non-attacker IP"


def test_waf_traversal_block():
    app = get_flask_app()
    client = app.test_client()

    response = client.get("/some/../test")
    assert response.status_code == 403, "Expected HTTP 403 Forbidden for path traversal in URL"
    assert b"Blocked Traversal" in response.data, "Expected 'Blocked Traversal' text in response"

    response = client.get("/some/%2e%2e/test")
    if response.status_code == 403:
        assert b"Blocked Traversal" in response.data, "Expected 'Blocked Traversal' text in response"

    # Unpredictable literal traversal paths must all be handled by the policy.
    for _ in range(3):
        left = secrets.token_hex(8)
        right = secrets.token_hex(8)
        response = client.get(f"/{left}/../{right}", environ_base={"REMOTE_ADDR": "203.0.113.17"})
        assert response.status_code == 403, "Literal ../ URL path was not blocked"
        assert b"Blocked Traversal" in response.data


def test_upload_remediation():
    app = get_flask_app()
    client = app.test_client()

    target_escape_file = "/home/user/test_escape_remediation.txt"
    if os.path.exists(target_escape_file):
        os.remove(target_escape_file)

    data = {
        "file": (io.BytesIO(b"malicious content"), "../../../home/user/test_escape_remediation.txt"),
        "filename": "../../../home/user/test_escape_remediation.txt",
    }
    client.post("/upload", data=data, content_type="multipart/form-data")
    assert not os.path.exists(target_escape_file), "Vulnerability still exists: file was written outside the uploads directory!"

    secure_path = "/home/user/app/uploads/test_escape_remediation.txt"
    if os.path.exists(secure_path):
        os.remove(secure_path)

    # A legitimate upload must still work and retain the existing response format.
    valid_name = "valid_" + secrets.token_hex(12) + ".txt"
    valid_content = secrets.token_bytes(37)
    valid_path = os.path.join(UPLOAD_DIR, valid_name)
    response = client.post(
        "/upload",
        data={"file": (io.BytesIO(valid_content), valid_name), "filename": valid_name},
        content_type="multipart/form-data",
        environ_base={"REMOTE_ADDR": "203.0.113.17"},
    )
    assert response.status_code == 200, "A legitimate upload no longer succeeds"
    assert response.data == b"Success", "The upload endpoint return format changed"
    assert os.path.isfile(valid_path), "Legitimate upload was not saved in the uploads directory"
    with open(valid_path, "rb") as f:
        assert f.read() == valid_content, "Legitimate upload content was not preserved"
    os.remove(valid_path)

    # Derive unpredictable outside targets and try both relative and absolute names.
    cases = []
    for _ in range(3):
        basename = "escape_" + secrets.token_hex(12) + ".txt"
        target = os.path.join("/home/user", basename)
        cases.append((os.path.relpath(target, UPLOAD_DIR), target))

    absolute_name = "absolute_" + secrets.token_hex(12) + ".txt"
    absolute_target = os.path.join("/home/user", absolute_name)
    cases.append((absolute_target, absolute_target))

    parent_name = "parent_" + secrets.token_hex(12) + ".txt"
    parent_target = os.path.join("/home/user/app", parent_name)
    cases.append(("../" + parent_name, parent_target))

    for supplied_name, outside_target in cases:
        if os.path.exists(outside_target):
            os.remove(outside_target)
        payload = secrets.token_bytes(29)
        response = client.post(
            "/upload",
            data={"file": (io.BytesIO(payload), supplied_name), "filename": supplied_name},
            content_type="multipart/form-data",
            environ_base={"REMOTE_ADDR": "203.0.113.17"},
        )
        assert response.status_code < 500, "Traversal input caused an internal server error instead of being neutralized or rejected"
        assert not os.path.exists(outside_target), f"Upload escaped the uploads directory to {outside_target}"

        sanitized_path = os.path.join(UPLOAD_DIR, os.path.basename(supplied_name))
        if os.path.isfile(sanitized_path):
            os.remove(sanitized_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
