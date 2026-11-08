#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/investigate.sh"
REPORT_PATH = "/home/user/summary_report.json"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def load_report():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {REPORT_PATH} as JSON: {e}")


def execute_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} was not created by the script."


def test_investigate_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_script_execution_and_report_generation():
    execute_script()


def test_summary_report_contents():
    report_data = load_report()

    assert "cracked_password" in report_data, "Missing 'cracked_password' key in JSON report."
    assert report_data["cracked_password"] == "supernova_admin", "The cracked password does not match the expected value."

    assert "certificate_valid" in report_data, "Missing 'certificate_valid' key in JSON report."
    assert isinstance(report_data["certificate_valid"], bool), "The 'certificate_valid' value must be a boolean."
    assert report_data["certificate_valid"] is True, "The certificate should be valid."

    assert "script_src_values" in report_data, "Missing 'script_src_values' key in JSON report."
    expected_script_src = ["'self'", "https://scripts.trusted.com", "https://cdn.malicious.local"]
    assert isinstance(report_data["script_src_values"], list), "The 'script_src_values' must be a list."
    assert report_data["script_src_values"] == expected_script_src, (
        f"The script_src_values do not match the expected list. Got: {report_data['script_src_values']}"
    )


def test_pipeline_with_fresh_artifacts():
    password = "incident_" + secrets.token_hex(10)
    expected_hash = hashlib.sha256(password.encode()).hexdigest()
    token = secrets.token_hex(6)
    expected_csp = ["'self'", f"https://assets-{token}.example", f"https://edge-{token}.invalid"]

    with tempfile.TemporaryDirectory(prefix="verifier-fixture-") as tmp:
        cert_dir = os.path.join(tmp, "certificates")
        os.makedirs(cert_dir)

        # Build a fresh ELF whose custom section contains the fresh password hash.
        source = os.path.join(tmp, "daemon.c")
        hash_file = os.path.join(tmp, "key_hash.bin")
        with open(source, "w") as f:
            f.write("int main(void) { return 0; }\n")
        with open(hash_file, "w") as f:
            f.write(expected_hash)
        run(["gcc", source, "-o", "/home/user/intercept_daemon"])
        run(["objcopy", "--add-section", f".key_hash={hash_file}", "/home/user/intercept_daemon"])

        # Put the fresh password among decoys rather than at a fixed line.
        words = ["not_the_password", secrets.token_hex(8), password, "another_decoy", secrets.token_hex(8)]
        with open("/home/user/passwords.txt", "w") as f:
            f.write("\n".join(words) + "\n")

        # Create a server certificate signed by one CA, but expose a different CA
        # as ca.crt so certificate validation must produce false.
        ca1_key = os.path.join(tmp, "ca1.key")
        ca1_crt = os.path.join(tmp, "ca1.crt")
        ca2_key = os.path.join(tmp, "ca2.key")
        server_key = os.path.join(tmp, "server.key")
        server_csr = os.path.join(tmp, "server.csr")
        server_crt = os.path.join(cert_dir, "server.crt")
        run(["openssl", "req", "-x509", "-nodes", "-days", "2", "-newkey", "rsa:2048",
             "-keyout", ca1_key, "-out", ca1_crt, "-subj", f"/CN=Fixture CA One {token}"])
        run(["openssl", "req", "-nodes", "-newkey", "rsa:2048", "-keyout", server_key,
             "-out", server_csr, "-subj", f"/CN=fixture-{token}.local"])
        run(["openssl", "x509", "-req", "-in", server_csr, "-CA", ca1_crt,
             "-CAkey", ca1_key, "-CAcreateserial", "-out", server_crt, "-days", "2"])
        run(["openssl", "req", "-x509", "-nodes", "-days", "2", "-newkey", "rsa:2048",
             "-keyout", ca2_key, "-out", os.path.join(cert_dir, "ca.crt"),
             "-subj", f"/CN=Unrelated Fixture CA {token}"])

        verify_result = subprocess.run(
            ["openssl", "verify", "-CAfile", os.path.join(cert_dir, "ca.crt"), server_crt],
            capture_output=True,
            text=True,
        )
        expected_certificate_valid = verify_result.returncode == 0
        assert expected_certificate_valid is False, "Verifier fixture unexpectedly formed a valid chain"

        plaintext = os.path.join(tmp, "traffic_keys.txt")
        with open(plaintext, "w") as f:
            f.write(cert_dir + "\n")
        run(["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-pass", f"pass:{password}",
             "-in", plaintext, "-out", "/home/user/traffic_keys.enc"])

        with open("/home/user/csp_header.txt", "w") as f:
            f.write(
                "HTTP/1.1 200 OK\n"
                f"X-Fixture: {token}\n"
                "Content-Security-Policy: default-src 'none'; script-src "
                + " ".join(expected_csp)
                + "; object-src 'none'\n"
                "Content-Type: text/html\n"
            )

        execute_script()
        report_data = load_report()

        assert "cracked_password" in report_data, "Missing 'cracked_password' key in JSON report."
        assert report_data["cracked_password"] == password, (
            "The script did not derive the password from the fresh ELF section and wordlist."
        )
        assert "certificate_valid" in report_data, "Missing 'certificate_valid' key in JSON report."
        assert isinstance(report_data["certificate_valid"], bool), "The 'certificate_valid' value must be a boolean."
        assert report_data["certificate_valid"] is expected_certificate_valid, (
            "The certificate validation result is incorrect for the fresh certificate directory."
        )
        assert "script_src_values" in report_data, "Missing 'script_src_values' key in JSON report."
        assert isinstance(report_data["script_src_values"], list), "The 'script_src_values' must be a list."
        assert report_data["script_src_values"] == expected_csp, (
            f"The fresh script-src values were not extracted exactly. Got: {report_data['script_src_values']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
