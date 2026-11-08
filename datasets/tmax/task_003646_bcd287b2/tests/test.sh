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
import re
import secrets
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
TOKEN_HEADER = {"Authorization": "Bearer AUDITOR-TOKEN-992"}
CARD_RE = re.compile(r"(?<!\d)(?:\d{4}-?){3}\d{4}(?!\d)")


@pytest.fixture(scope="module", autouse=True)
def wait_for_server():
    """Wait for the server to become available before running tests."""
    max_retries = 10
    for _ in range(max_retries):
        try:
            requests.get(f"{BASE_URL}/receipt", timeout=1)
            return
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
    pytest.fail("Server did not start on 127.0.0.1:8080")


def test_auth_required():
    """Test that requests without the correct token return 401."""
    response = requests.get(f"{BASE_URL}/receipt")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_get_receipt_with_token():
    """Test GET /receipt with valid token and compare it to freshly derived OCR text."""
    response = requests.get(f"{BASE_URL}/receipt", headers=TOKEN_HEADER)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Security-Policy") == "default-src 'self'", "Missing or incorrect Content-Security-Policy header"

    text = response.text
    assert "XXXX-XXXX-XXXX-XXXX" in text, "Expected redacted credit card in response"
    assert "4128-9999-1234-5678" not in text, "Expected original credit card to be redacted"

    ocr_text = subprocess.run(
        ["tesseract", "/app/secret_receipt.png", "stdout"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert CARD_RE.search(ocr_text), "OCR did not find the expected 16-digit card number"
    expected = CARD_RE.sub("XXXX-XXXX-XXXX-XXXX", ocr_text)
    assert text.strip() == expected.strip(), "GET /receipt did not return the complete OCR-extracted and redacted receipt text"


def test_post_redact_valid():
    """Test POST /redact with valid text."""
    payload = "My card is 1111-2222-3333-4444!"
    response = requests.post(f"{BASE_URL}/redact", headers=TOKEN_HEADER, data=payload)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Security-Policy") == "default-src 'self'", "Missing or incorrect Content-Security-Policy header"
    assert response.text == "My card is XXXX-XXXX-XXXX-XXXX!", f"Unexpected redacted text: {response.text}"


def test_post_redact_random_cards():
    """Exercise general redaction with unpredictable dashed and undashed cards."""
    first_digits = "53" + "".join(secrets.choice("0123456789") for _ in range(14))
    second_digits = "40" + "".join(secrets.choice("0123456789") for _ in range(14))
    dashed = "-".join(first_digits[i:i + 4] for i in range(0, 16, 4))
    payload = f"invoice={secrets.token_hex(6)}; primary {dashed}; backup {second_digits}; end"
    expected = CARD_RE.sub("XXXX-XXXX-XXXX-XXXX", payload)

    response = requests.post(f"{BASE_URL}/redact", headers=TOKEN_HEADER, data=payload)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Security-Policy") == "default-src 'self'", "Missing or incorrect Content-Security-Policy header"
    assert response.text == expected, f"Unexpected redacted text: {response.text}"


def test_post_redact_waf_script():
    """Test POST /redact with <script> payload triggers WAF."""
    payload = "<script>alert(1)</script>"
    response = requests.post(f"{BASE_URL}/redact", headers=TOKEN_HEADER, data=payload)
    assert response.status_code == 403, f"Expected 403 Forbidden for <script> payload, got {response.status_code}"


def test_post_redact_waf_sql():
    """Test POST /redact with UNION SELECT payload triggers WAF."""
    payload = "id=1 UNION SELECT password FROM users"
    response = requests.post(f"{BASE_URL}/redact", headers=TOKEN_HEADER, data=payload)
    assert response.status_code == 403, f"Expected 403 Forbidden for UNION SELECT payload, got {response.status_code}"


def test_post_redact_waf_randomized_contexts():
    """Ensure WAF behavior is based on the required substrings, not fixed payloads."""
    nonce = secrets.token_hex(12)
    payloads = [
        f"prefix-{nonce}-<script>-suffix-{secrets.token_hex(5)}",
        f"query-{nonce} UNION SELECT {secrets.token_hex(7)} FROM records",
    ]
    for payload in payloads:
        response = requests.post(f"{BASE_URL}/redact", headers=TOKEN_HEADER, data=payload)
        assert response.status_code == 403, f"Expected 403 Forbidden for randomized WAF payload, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
