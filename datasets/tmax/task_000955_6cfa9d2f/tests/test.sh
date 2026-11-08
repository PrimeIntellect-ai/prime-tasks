#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier exercises a fresh instance of the submitted server.
pkill -f '[p]ython.*server.py' 2>/dev/null || true
sleep 0.2
python3 /home/user/app/server.py >/tmp/submitted_server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 2

cat << 'RUNNER_EOF' > /tmp/run_submitted_client.py
import json
import runpy
import requests
import requests.adapters
import urllib3.connection
import urllib3.util.ssl_

# The supplied certificate has only a localhost CN and no SAN. Preserve strict
# CA verification while enabling the standard CN fallback for this fixture.
def enable_cn_fallback(context):
    if hasattr(context, "hostname_checks_common_name"):
        context.hostname_checks_common_name = True
    return context

if hasattr(requests.adapters, "_preloaded_ssl_context"):
    enable_cn_fallback(requests.adapters._preloaded_ssl_context)

_original_create_context = urllib3.util.ssl_.create_urllib3_context
def create_context_with_cn_fallback(*args, **kwargs):
    return enable_cn_fallback(_original_create_context(*args, **kwargs))

urllib3.util.ssl_.create_urllib3_context = create_context_with_cn_fallback
urllib3.connection.create_urllib3_context = create_context_with_cn_fallback
if hasattr(requests.adapters, "create_urllib3_context"):
    requests.adapters.create_urllib3_context = create_context_with_cn_fallback

calls = []
_original_request = requests.sessions.Session.request

def tracked_request(self, method, url, **kwargs):
    calls.append({
        "method": str(method).upper(),
        "url": str(url),
        "verify": kwargs.get("verify"),
    })
    return _original_request(self, method, url, **kwargs)

requests.sessions.Session.request = tracked_request
try:
    runpy.run_path('/home/user/app/client.py', run_name='__main__')
finally:
    with open('/tmp/submitted_client_calls.json', 'w') as f:
        json.dump(calls, f)
RUNNER_EOF

python3 /tmp/run_submitted_client.py >/tmp/submitted_client_output.log 2>/tmp/submitted_client_error.log || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import ast
import ssl
import http.client

EXPECTED_CSP = "default-src 'none'; frame-ancestors 'none';"


def parse_single_json_file(path):
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content, f"{path} is empty."
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{path} does not contain valid JSON.")


def assert_success_output(data, source):
    assert "status_code" in data, f"JSON in {source} is missing 'status_code'."
    assert data["status_code"] == 200, f"Expected status_code 200, got {data['status_code']}."
    assert "headers" in data, f"JSON in {source} is missing 'headers'."
    headers = {k.lower(): v for k, v in data["headers"].items()}
    assert "content-security-policy" in headers, "Content-Security-Policy header is missing in the response."
    assert headers["content-security-policy"] == EXPECTED_CSP, \
        f"Expected CSP '{EXPECTED_CSP}', got '{headers['content-security-policy']}'."


def test_result_log_exists_and_valid():
    """Test that result.log exists and contains the expected JSON structure."""
    log_path = '/home/user/result.log'
    assert os.path.isfile(log_path), f"{log_path} is missing. Did you redirect the output of client.py?"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content, f"{log_path} is empty."

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{log_path} does not contain valid JSON.")

    assert "status_code" in data, "JSON in result.log is missing 'status_code'."
    assert data["status_code"] == 200, f"Expected status_code 200, got {data['status_code']}."

    assert "headers" in data, "JSON in result.log is missing 'headers'."
    headers = {k.lower(): v for k, v in data["headers"].items()}

    expected_csp = "default-src 'none'; frame-ancestors 'none';"
    assert "content-security-policy" in headers, "Content-Security-Policy header is missing in the response."
    assert headers["content-security-policy"] == expected_csp, f"Expected CSP '{expected_csp}', got '{headers['content-security-policy']}'."


def test_server_py_rotated_certs():
    """Test that server.py uses the new certificates."""
    server_path = '/home/user/app/server.py'
    assert os.path.isfile(server_path), f"{server_path} is missing."

    with open(server_path, 'r') as f:
        content = f.read()

    assert 'new_server.crt' in content, "server.py does not appear to use new_server.crt."
    assert 'new_server.key' in content, "server.py does not appear to use new_server.key."
    assert 'old_server.crt' not in content, "server.py is still referencing old_server.crt."
    assert 'old_server.key' not in content, "server.py is still referencing old_server.key."


def test_client_py_validates_chain():
    """Test that client.py uses the new CA bundle to verify the server certificate."""
    client_path = '/home/user/app/client.py'
    assert os.path.isfile(client_path), f"{client_path} is missing."

    with open(client_path, 'r') as f:
        content = f.read()

    assert 'verify=False' not in content.replace(' ', ''), "client.py is still using verify=False."
    assert 'new_ca.pem' in content, "client.py does not appear to use new_ca.pem for verification."

    # Parse AST to be more robust
    try:
        tree = ast.parse(content)
    except SyntaxError:
        pytest.fail("client.py contains invalid Python syntax.")

    found_verify = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr in ('get', 'post', 'request'):
                for kw in node.keywords:
                    if kw.arg == 'verify':
                        if isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                            if 'new_ca.pem' in kw.value.value:
                                found_verify = True
                        elif isinstance(kw.value, ast.Str): # Python < 3.8
                            if 'new_ca.pem' in kw.value.s:
                                found_verify = True

    assert found_verify, "client.py does not pass the correct CA bundle path to the requests call."


def test_fresh_client_execution_made_validated_request():
    """Execute client.py and require its live requests call and live response."""
    with open('/tmp/submitted_client_calls.json', 'r') as f:
        calls = json.load(f)

    matching = [c for c in calls if
                c.get('method') == 'GET' and
                c.get('url') == 'https://localhost:8443/webhook' and
                c.get('verify') == '/home/user/certs/new_ca.pem']
    assert matching, "Executed client.py did not make the required GET using the new CA bundle."

    data = parse_single_json_file('/tmp/submitted_client_output.log')
    assert_success_output(data, 'the freshly executed client.py output')


def test_live_server_certificate_and_response():
    """Independently derive the result from the running HTTPS service."""
    context = ssl.create_default_context(cafile='/home/user/certs/new_ca.pem')
    context.verify_mode = ssl.CERT_REQUIRED
    context.check_hostname = True
    if hasattr(context, 'hostname_checks_common_name'):
        context.hostname_checks_common_name = True

    connection = http.client.HTTPSConnection('localhost', 8443, context=context, timeout=5)
    connection.connect()

    presented_der = connection.sock.getpeercert(binary_form=True)
    with open('/home/user/certs/new_server.crt', 'r') as f:
        expected_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert presented_der == expected_der, "The live server is not presenting new_server.crt."

    connection.request('GET', '/webhook')
    response = connection.getresponse()
    body = response.read()
    assert response.status == 200, f"Live HTTPS request returned {response.status}."
    assert response.getheader('Content-Security-Policy') == EXPECTED_CSP, \
        "The live /webhook response does not contain the exact required CSP."
    try:
        payload = json.loads(body.decode('utf-8'))
    except Exception:
        pytest.fail("The live /webhook response body is not valid JSON.")
    assert payload == {"status": "success", "message": "Webhook received"}
    connection.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
