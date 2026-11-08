#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import re
import json
import secrets
import string
import subprocess
import urllib.request
import urllib.error
import importlib.util
import pytest


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, f"Could not create import spec for {path}."
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_audit_complete_log():
    log_path = "/home/user/audit_complete.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "AUDIT FINISHED" in content, f"Log file {log_path} does not contain 'AUDIT FINISHED'."


def test_nginx_configuration_is_valid_and_strips_header():
    conf_path = "/app/ecommerce_stack/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx configuration {conf_path} is missing."

    result = subprocess.run(
        ["nginx", "-t", "-c", conf_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, f"Submitted Nginx configuration is invalid:\n{result.stdout}"

    with open(conf_path, "r") as f:
        config = f.read()
    config_without_comments = re.sub(r"#.*", "", config)
    assert re.search(
        r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\s*;",
        config_without_comments,
        re.IGNORECASE,
    ), "Nginx must proxy external traffic to the Flask backend on port 5000."
    assert re.search(
        r"proxy_set_header\s+X-Internal-Role\s+(?:\"\"|'')\s*;",
        config_without_comments,
        re.IGNORECASE,
    ), "Nginx must explicitly clear X-Internal-Role before proxying requests."


def test_nginx_strips_internal_role():
    # Original service assertion: a spoofed external admin header must not pass.
    req = urllib.request.Request("http://localhost:8080/api/admin")
    req.add_header("X-Internal-Role", "admin")

    try:
        response = urllib.request.urlopen(req, timeout=5)
        status = response.getcode()
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")

    assert status == 403, f"Expected 403 Forbidden from Nginx for spoofed admin request, got {status}."

    # Exercise fresh request variants so a response tailored to one fixed request is insufficient.
    for value in ("ADMIN", " admin ", "administrator", secrets.token_hex(12)):
        url = "http://localhost:8080/api/admin?probe=" + secrets.token_hex(10)
        variant = urllib.request.Request(url)
        variant.add_header("x-internal-role", value)
        variant.add_header("X-Audit-Probe", secrets.token_hex(16))
        try:
            response = urllib.request.urlopen(variant, timeout=5)
            variant_status = response.getcode()
        except urllib.error.HTTPError as e:
            variant_status = e.code
        except Exception as e:
            pytest.fail(f"Failed to exercise Nginx header stripping: {e}")
        assert variant_status == 403, f"Nginx forwarded an externally supplied internal role value {value!r}."


def test_flask_accepts_internal_role_directly():
    # Original service assertion: a legitimate local/internal request still succeeds.
    req = urllib.request.Request("http://localhost:5000/api/admin")
    req.add_header("X-Internal-Role", "admin")

    try:
        response = urllib.request.urlopen(req, timeout=5)
        status = response.getcode()
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception as e:
        pytest.fail(f"Failed to connect to Flask on port 5000: {e}")

    assert status == 200, f"Expected 200 OK from Flask for direct admin request, got {status}."


def test_submitted_flask_artifact_behaviour():
    app_path = "/app/ecommerce_stack/backend/app.py"
    assert os.path.isfile(app_path), f"Flask application {app_path} is missing."
    try:
        backend = load_module(app_path, "submitted_ecommerce_backend")
    except Exception as e:
        pytest.fail(f"Failed to execute submitted Flask application: {e}")

    assert hasattr(backend, "app"), "Submitted backend does not expose its Flask app."
    client = backend.app.test_client()

    orders = client.get("/api/orders", headers={"X-Audit-Probe": secrets.token_hex(12)})
    assert orders.status_code == 200
    assert orders.get_json() == {"orders": []}

    assert client.get("/api/admin").status_code == 403
    allowed = client.get("/api/admin", headers={"X-Internal-Role": "admin"})
    assert allowed.status_code == 200
    assert allowed.get_json() == {"status": "admin access granted"}

    for role in ("ADMIN", "administrator", "user", secrets.token_hex(10)):
        denied = client.get(
            "/api/admin?probe=" + secrets.token_hex(8),
            headers={"X-Internal-Role": role, "X-Audit-Probe": secrets.token_hex(12)},
        )
        assert denied.status_code == 403, f"Backend granted admin access to role {role!r}."


def test_waf_filter_adversarial_corpus():
    waf_path = "/home/user/waf_filter.py"
    assert os.path.isfile(waf_path), f"WAF filter script {waf_path} is missing."

    try:
        waf_filter = load_module(waf_path, "waf_filter")
    except Exception as e:
        pytest.fail(f"Failed to load {waf_path}: {e}")

    assert hasattr(waf_filter, "verify_request"), "verify_request function is missing in waf_filter.py."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    evil_bypassed = []
    clean_modified = []

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            data = json.load(f)
        try:
            result = waf_filter.verify_request(data.get("headers", {}), data.get("cookies", {}))
            if result is not False:
                evil_bypassed.append(filename)
        except Exception:
            evil_bypassed.append(filename)

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            data = json.load(f)
        try:
            result = waf_filter.verify_request(data.get("headers", {}), data.get("cookies", {}))
            if result is not True:
                clean_modified.append(filename)
        except Exception:
            clean_modified.append(filename)

    total_evil = len(evil_files)
    total_clean = len(clean_files)
    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {total_evil} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {total_clean} clean modified/rejected: {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail("WAF filter failed corpus validation:\n" + "\n".join(error_msgs))

    # Fresh cases are generated at verification time and cover each requested class
    # in different header/cookie fields, preventing fixture-specific implementations.
    token = secrets.token_hex(10)
    evil_cases = [
        ({"X-File": f"../../etc/{token}"}, {"session": secrets.token_hex(8)}),
        ({"X-Path": f"..\\windows\\{token}"}, {}),
        ({"User-Agent": "Mozilla"}, {"next": f"../../../var/{token}"}),
        ({"X-Search": f"{token}' OR 1=1 --"}, {}),
        ({"X-Query": f"{token} UNION SELECT password FROM users"}, {}),
        ({}, {"session": f"{token}'; DROP TABLE orders;--"}),
        ({"X-Internal-Role": "admin", "X-Audit-Probe": token}, {"session": secrets.token_hex(8)}),
        ({"x-internal-role": "ADMIN"}, {}),
        ({"User-Agent": "Mozilla"}, {"role": "admin", "session": token}),
        ({}, {"is_admin": "true", "session": token}),
        ({}, {"admin": "1", "session": token}),
    ]

    alphabet = string.ascii_letters + string.digits
    random_session = ''.join(secrets.choice(alphabet) for _ in range(32))
    clean_cases = [
        ({"User-Agent": f"AuditClient/{token}", "Accept": "application/json"}, {"session": random_session}),
        ({"X-Internal-Role": "viewer", "X-Audit-Probe": token}, {"theme": "light"}),
        ({"X-Customer-Name": "O'Reilly", "X-Product": "select-grade union-jack"}, {"theme": "admin-blue"}),
        ({"Referer": f"https://shop.example/products/{token}"}, {"cart": token, "logged_in": "true"}),
        ({}, {}),
    ]

    for index, (headers, cookies) in enumerate(evil_cases):
        try:
            result = waf_filter.verify_request(dict(headers), dict(cookies))
        except Exception as e:
            pytest.fail(f"verify_request crashed on generated malicious case {index}: {e}")
        assert result is False, f"Generated malicious case {index} was allowed: headers={headers!r}, cookies={cookies!r}"

    for index, (headers, cookies) in enumerate(clean_cases):
        try:
            result = waf_filter.verify_request(dict(headers), dict(cookies))
        except Exception as e:
            pytest.fail(f"verify_request crashed on generated clean case {index}: {e}")
        assert result is True, f"Generated clean case {index} was rejected: headers={headers!r}, cookies={cookies!r}"
TEST_EOF

# Ensure the service test uses the submitted Nginx artifact rather than a stale process.
pkill -x nginx >/dev/null 2>&1 || true
nginx -c /app/ecommerce_stack/nginx/nginx.conf >/tmp/verifier_nginx.log 2>&1 || true
sleep 1

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
