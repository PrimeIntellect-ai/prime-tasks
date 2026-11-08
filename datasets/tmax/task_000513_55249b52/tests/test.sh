#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import socket
import ssl
import pytest
import requests
import urllib3

# Suppress insecure request warnings since we are testing a self-signed cert
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

INTEL_FILE = "/home/user/extracted_intel.json"
EXPECTED_PORT = 8443
EXPECTED_TLS_CN = "c2.malicious-domain.local"
EXPECTED_KNOCK_HEX = "a1b2c3d4e5f67890a1b2c3d4e5f67890"
EXPECTED_KNOCK_BYTES = bytes.fromhex(EXPECTED_KNOCK_HEX)

def test_extracted_intel_json():
    assert os.path.exists(INTEL_FILE), f"Expected intel file is missing at {INTEL_FILE}"

    with open(INTEL_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {INTEL_FILE} does not contain valid JSON")

    assert "port" in data, "Missing 'port' in extracted_intel.json"
    assert data["port"] == EXPECTED_PORT, f"Expected port {EXPECTED_PORT}, got {data['port']}"

    assert "tls_cn" in data, "Missing 'tls_cn' in extracted_intel.json"
    assert data["tls_cn"] == EXPECTED_TLS_CN, f"Expected tls_cn '{EXPECTED_TLS_CN}', got '{data['tls_cn']}'"

    assert "knock_payload" in data, "Missing 'knock_payload' in extracted_intel.json"
    assert data["knock_payload"] == EXPECTED_KNOCK_HEX, f"Expected knock_payload '{EXPECTED_KNOCK_HEX}', got '{data['knock_payload']}'"

def test_raw_tcp_knock():
    try:
        with socket.create_connection(("127.0.0.1", EXPECTED_PORT), timeout=5) as sock:
            sock.sendall(EXPECTED_KNOCK_BYTES)
            response = sock.recv(1024)
            assert response.decode('ascii') == "ACK_KNOCK", f"Expected 'ACK_KNOCK', got '{response}'"
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused on port {EXPECTED_PORT}. Is the honeypot running?")
    except socket.timeout:
        pytest.fail("Connection timed out while waiting for knock response.")
    except Exception as e:
        pytest.fail(f"Unexpected error during TCP knock: {e}")

def test_https_request():
    url = f"https://127.0.0.1:{EXPECTED_PORT}/submit_elf"
    try:
        response = requests.get(url, verify=False, timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        assert response.text == "SUBMISSION_ACCEPTED", f"Expected body 'SUBMISSION_ACCEPTED', got '{response.text}'"
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to {url}. Is the HTTPS service running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")
    except Exception as e:
        pytest.fail(f"Unexpected error during HTTPS request: {e}")

def test_tls_certificate_cn():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    try:
        with socket.create_connection(("127.0.0.1", EXPECTED_PORT), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname="127.0.0.1") as ssock:
                cert = ssock.getpeercert(binary_form=True)

                import cryptography.x509
                from cryptography.x509.oid import NameOID
                from cryptography.hazmat.backends import default_backend

                x509_cert = cryptography.x509.load_der_x509_certificate(cert, default_backend())
                common_names = x509_cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)

                assert len(common_names) > 0, "No Common Name found in the certificate"
                cn_value = common_names[0].value
                assert cn_value == EXPECTED_TLS_CN, f"Expected TLS CN '{EXPECTED_TLS_CN}', got '{cn_value}'"
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused on port {EXPECTED_PORT}. Is the honeypot running?")
    except ssl.SSLError as e:
        pytest.fail(f"SSL error during certificate retrieval: {e}")
    except Exception as e:
        pytest.fail(f"Unexpected error during TLS certificate check: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
