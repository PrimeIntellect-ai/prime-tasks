#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import subprocess
import sys
import pytest


def test_cwe_report_exists_and_correct():
    """Verify that the CWE report has exactly the two required lines."""
    report_path = "/home/user/cwe_report.txt"
    assert os.path.isfile(report_path), f"CWE report file missing at {report_path}"

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    upper_content = content.upper()
    assert "CWE-327" in upper_content or "CWE-311" in upper_content, \
        "CWE report is missing the correct CWE ID for weak cryptography (e.g., CWE-327)."
    assert "CWE-693" in upper_content or "CWE-116" in upper_content or "CWE-346" in upper_content, \
        "CWE report is missing the correct CWE ID for protection mechanism failure / missing CSP (e.g., CWE-693)."

    assert content in ("CWE-327\nCWE-693", "CWE-327\nCWE-693\n"), \
        "cwe_report.txt must contain exactly two lines: CWE-327 and CWE-693."


def expected_admin_token():
    guest_plaintext = b"role=guest"
    guest_ciphertext = bytes.fromhex("015c0f374e5416370047")
    key = bytes(guest_ciphertext[i] ^ guest_plaintext[i] for i in range(4))
    admin_plaintext = b"role=admin"
    return bytes(admin_plaintext[i] ^ key[i % len(key)] for i in range(len(admin_plaintext))).hex()


def test_admin_token_forged_correctly_and_script_runs():
    """Verify both the exact saved token and an executable forging artifact."""
    token_path = "/home/user/admin_token.txt"
    forge_path = "/home/user/forge.py"
    expected = expected_admin_token()

    assert os.path.isfile(token_path), f"Admin token file missing at {token_path}"
    assert os.path.isfile(forge_path), f"Forging script missing at {forge_path}"

    with open(token_path, "rb") as f:
        actual_bytes = f.read()
    assert actual_bytes == expected.encode("ascii"), \
        "admin_token.txt must contain only the correct lowercase hex token with no newline or other text."

    with open(forge_path, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        ast.parse(source, filename=forge_path)
    except SyntaxError as exc:
        pytest.fail(f"forge.py is not valid Python: {exc}")

    # Remove the precomputed result before execution so a script that does no work
    # cannot pass merely because admin_token.txt was written directly beforehand.
    os.unlink(token_path)
    try:
        result = subprocess.run(
            [sys.executable, forge_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, \
            f"forge.py failed when executed: {result.stderr}"

        generated_file = None
        if os.path.isfile(token_path):
            with open(token_path, "rb") as f:
                generated_file = f.read()

        stdout_token = result.stdout.strip()
        produced_correctly = generated_file == expected.encode("ascii") or stdout_token == expected
        assert produced_correctly, \
            "Executing forge.py must derive and produce the correct admin token, either on stdout or in admin_token.txt."
    finally:
        # Leave the required final artifact in its exact requested form.
        with open(token_path, "wb") as f:
            f.write(expected.encode("ascii"))


def load_application_module():
    app_path = "/home/user/app/app.py"
    assert os.path.isfile(app_path), f"Application file missing at {app_path}"

    spec = importlib.util.spec_from_file_location("submitted_app", app_path)
    assert spec is not None and spec.loader is not None, "Could not load app.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "app.py does not define the Flask application 'app'."
    assert hasattr(module.app, "test_client"), "The 'app' object is not a Flask application."
    return module.app


def test_csp_header_on_every_response():
    """Exercise successful and error responses and check the exact CSP header."""
    app_path = "/home/user/app/app.py"
    with open(app_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_header_str = "Content-Security-Policy"
    expected_policy_str = "default-src 'self'; script-src 'self';"
    assert expected_header_str in content, "The Content-Security-Policy header name was not found in app.py."
    assert expected_policy_str in content, "The expected CSP policy string was not found in app.py."

    app = load_application_module()
    app.testing = True
    client = app.test_client()

    responses = [
        client.get("/"),
        client.get("/admin"),
        client.get("/this-route-does-not-exist"),
        client.post("/admin"),
    ]
    for response in responses:
        values = response.headers.getlist(expected_header_str)
        assert values == [expected_policy_str], \
            f"Response status {response.status_code} did not contain exactly the required CSP header."


def test_network_policy_updated():
    """Verify that the network policy allows localhost access to /admin."""
    policy_path = "/home/user/app/network_policy.json"
    assert os.path.isfile(policy_path), f"Network policy file missing at {policy_path}"

    with open(policy_path, "r", encoding="utf-8") as f:
        try:
            policy = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("network_policy.json is not valid JSON.")

    rules = policy.get("firewall_rules", [])
    admin_rule = next((rule for rule in rules if rule.get("route") == "/admin"), None)

    assert admin_rule is not None, "The /admin route rule is missing from network_policy.json."
    assert admin_rule.get("action") == "ALLOW", "The action for the /admin route is not set to ALLOW."
    assert admin_rule.get("source_ip") == "127.0.0.1", "The source_ip for the /admin route is not set to 127.0.0.1."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
