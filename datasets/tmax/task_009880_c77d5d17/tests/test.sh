#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import ast
import re
import secrets
import importlib.util
import pytest

REPORT_PATH = "/home/user/report.txt"
APP_PATH = "/home/user/webapp/app.py"


def test_report_exists_and_content():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} does not exist. You must create the investigation report."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{REPORT_PATH} must contain at least two lines."

    expected_file = "/home/user/webapp/app.py"
    assert lines[0] == expected_file, f"First line of report is incorrect. Expected '{expected_file}', got '{lines[0]}'."

    expected_cwe = "CWE-601"
    assert lines[1].upper() == expected_cwe, f"Second line of report is incorrect. Expected '{expected_cwe}', got '{lines[1]}'."


def test_app_py_fixed():
    assert os.path.exists(APP_PATH), f"{APP_PATH} does not exist."

    with open(APP_PATH, "r") as f:
        code = f.read()

    try:
        tree = ast.parse(code)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {APP_PATH}: {e}")

    # Retain the original source-level validation checks.
    has_startswith = "startswith" in code
    has_urllib = "urllib.parse" in code or "urlparse" in code
    has_index_check = re.search(r"\[0\]", code) is not None
    has_regex = "re." in code or "match" in code
    has_in = " in " in code

    assert any([has_startswith, has_urllib, has_index_check, has_regex, has_in]), \
        "Could not find validation logic in app.py. Ensure you validate the 'next' parameter."

    redirect_called = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "redirect":
                redirect_called = True
                break

    assert redirect_called, "The 'redirect' function is no longer being called in app.py."


def test_login_redirect_validation_behavior():
    # Import and exercise the submitted application rather than trusting keywords.
    spec = importlib.util.spec_from_file_location("submitted_webapp", APP_PATH)
    assert spec is not None and spec.loader is not None, "Could not load app.py as a Python module."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert hasattr(module, "app"), "app.py must expose the Flask application as 'app'."
    app = module.app
    app.config.update(TESTING=True)
    client = app.test_client()

    token = secrets.token_hex(12)
    candidates = [
        "/",
        f"/safe-{token}",
        f"/account/{token}",
        f"//{token}.example/path",
        f"///{token}.example/path",
        f"http://{token}.example/path",
        f"https://{token}.example/path",
        f"http{token}",
        f"relative-{token}",
        "",
    ]

    def expected_destination(value):
        if value.startswith("/") and not value.startswith("//") and not value.startswith("http"):
            return value
        return "/dashboard"

    credentials = {"username": "admin", "password": "secret"}
    for candidate in candidates:
        response = client.post(
            "/login",
            query_string={"next": candidate},
            data=credentials,
            follow_redirects=False,
        )
        assert 300 <= response.status_code < 400, \
            f"Successful login with next={candidate!r} did not return a redirect."
        assert response.headers.get("Location") == expected_destination(candidate), \
            f"Unsafe or incorrect redirect for next={candidate!r}."

    response = client.post("/login", data=credentials, follow_redirects=False)
    assert 300 <= response.status_code < 400, "Successful login without next did not redirect."
    assert response.headers.get("Location") == "/dashboard", \
        "A missing next parameter must default to /dashboard."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
