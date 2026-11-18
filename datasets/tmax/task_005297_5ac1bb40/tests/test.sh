#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import importlib.util
import io
import json
import os
import uuid

import pytest

AUTH_KEYS_PATH = "/home/user/.ssh/authorized_keys"
LEGIT_KEY_PATH = "/home/user/.ssh/id_rsa.pub"
ROGUE_KEY_ORACLE = "/tests/rogue_rsa.pub"
APP_PATH = "/home/user/webapp/app.py"
UPLOAD_DIR = "/home/user/webapp/uploads"
REPORT_PATH = "/home/user/forensics_report.json"


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def key_material(line):
    fields = line.split()
    assert len(fields) >= 2, f"Invalid SSH public key line: {line!r}"
    return fields[0], fields[1]


def openssh_sha256_fingerprint(public_key_line):
    _, encoded = key_material(public_key_line)
    blob = base64.b64decode(encoded, validate=True)
    digest = base64.b64encode(hashlib.sha256(blob).digest()).decode("ascii").rstrip("=")
    return "SHA256:" + digest


def test_authorized_keys_remediated():
    assert os.path.isfile(AUTH_KEYS_PATH), f"File missing: {AUTH_KEYS_PATH}"
    assert os.path.isfile(LEGIT_KEY_PATH), f"File missing: {LEGIT_KEY_PATH}"
    assert os.path.isfile(ROGUE_KEY_ORACLE), f"Verifier oracle missing: {ROGUE_KEY_ORACLE}"

    with open(AUTH_KEYS_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "admin@local" in content, "Valid key 'admin@local' was incorrectly removed from authorized_keys"
    assert "evil@empire.c2" not in content, "Rogue key 'evil@empire.c2' is still present in authorized_keys"

    authorized_lines = read_nonempty_lines(AUTH_KEYS_PATH)
    legit_line = read_nonempty_lines(LEGIT_KEY_PATH)[0]
    rogue_line = read_nonempty_lines(ROGUE_KEY_ORACLE)[0]
    legit_material = key_material(legit_line)
    rogue_material = key_material(rogue_line)

    assert rogue_material not in [key_material(line) for line in authorized_lines], \
        "Rogue SSH key material is still authorized under a changed or removed comment"
    assert legit_material in [key_material(line) for line in authorized_lines], \
        "The legitimate SSH key material was removed or replaced"
    assert authorized_lines == [legit_line], \
        "authorized_keys must retain exactly the original legitimate key and remove only the rogue key"


def load_webapp():
    spec = importlib.util.spec_from_file_location("remediated_webapp", APP_PATH)
    assert spec is not None and spec.loader is not None, "Unable to load web application"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "app.py does not expose the Flask application as 'app'"
    return module.app


def test_webapp_remediated():
    assert os.path.isfile(APP_PATH), f"Web application missing: {APP_PATH}"

    with open(APP_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "secure_filename" in content, "Path traversal vulnerability not remediated: 'secure_filename' not found in app.py"
    assert "default-src 'self';" in content, "CSP header not properly secured: expected \"default-src 'self';\" in app.py"
    assert "unsafe-inline" not in content, "Insecure CSP directive 'unsafe-inline' is still present in app.py"

    app = load_webapp()
    app.config.update(TESTING=True)
    client = app.test_client()

    token = "verifier_" + uuid.uuid4().hex + ".txt"
    malicious_name = "../../../../tmp/" + token
    escaped_path = os.path.join("/tmp", token)
    expected_safe_path = os.path.join(UPLOAD_DIR, token)
    payload = b"path traversal verification payload"

    for path in (escaped_path, expected_safe_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    response = client.post(
        "/upload_file",
        data={"file": (io.BytesIO(payload), malicious_name)},
        content_type="multipart/form-data",
    )

    assert response.status_code == 200, f"Upload endpoint returned HTTP {response.status_code}"
    assert response.headers.get("Content-Security-Policy") == "default-src 'self';", \
        "Upload response does not enforce the exact required CSP header"
    assert not os.path.exists(escaped_path), "Traversal upload wrote a file outside the uploads directory"
    assert os.path.isfile(expected_safe_path), "Traversal filename was not safely stored inside uploads/"
    with open(expected_safe_path, "rb") as f:
        assert f.read() == payload, "Safely stored upload did not preserve the submitted contents"

    os.remove(expected_safe_path)


def test_forensics_report():
    assert os.path.isfile(REPORT_PATH), f"Forensics report missing: {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Forensics report is not valid JSON: {REPORT_PATH}")

    assert isinstance(report, dict), "Forensics report must be a JSON object"
    assert set(report) == {"c2_address", "vulnerable_route", "rogue_key_fingerprint"}, \
        "Forensics report does not have exactly the required schema"

    # Preserve the original report assertions.
    assert "c2_address" in report, "Missing 'c2_address' in forensics report"
    assert report["c2_address"] == "198.51.100.77:4444", f"Incorrect C2 address: {report['c2_address']}"

    assert "vulnerable_route" in report, "Missing 'vulnerable_route' in forensics report"
    assert report["vulnerable_route"] == "/upload_file", f"Incorrect vulnerable route: {report['vulnerable_route']}"

    assert "rogue_key_fingerprint" in report, "Missing 'rogue_key_fingerprint' in forensics report"
    fingerprint = report["rogue_key_fingerprint"]
    assert isinstance(fingerprint, str), "Rogue key fingerprint must be a string"
    assert fingerprint.startswith("SHA256:"), f"Fingerprint does not start with 'SHA256:': {fingerprint}"
    assert len(fingerprint) > 10, f"Fingerprint appears too short to be valid: {fingerprint}"

    rogue_line = read_nonempty_lines(ROGUE_KEY_ORACLE)[0]
    expected_fingerprint = openssh_sha256_fingerprint(rogue_line)
    assert fingerprint == expected_fingerprint, \
        f"Incorrect rogue SSH key fingerprint: expected {expected_fingerprint}, got {fingerprint}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
