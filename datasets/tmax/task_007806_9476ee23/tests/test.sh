#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess


def test_ssh_config_fixed():
    config_path = "/home/user/.ssh/config"
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert not re.search(r'(?i)^\s*PubkeyAuthentication\s+no', content, re.MULTILINE), "SSH config still disables PubkeyAuthentication."
    assert re.search(r'(?i)^\s*IdentityFile\s+/home/user/\.ssh/migration_key', content, re.MULTILINE), "SSH config does not specify IdentityFile /home/user/.ssh/migration_key."

    # Require both settings in the migration-target Host stanza, rather than
    # accepting unrelated directives elsewhere in the file.
    target_stanzas = []
    current = None
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        keyword = parts[0].lower()
        if keyword == "host":
            current = [] if any(p.lower() == "migration-target" for p in parts[1:]) else None
            if current is not None:
                target_stanzas.append(current)
        elif keyword == "match":
            current = None
        elif current is not None:
            current.append(parts)

    assert target_stanzas, "No Host migration-target stanza was found."
    directives = [parts for stanza in target_stanzas for parts in stanza]
    assert any(len(parts) >= 2 and parts[0].lower() == "pubkeyauthentication" and parts[1].lower() == "yes" for parts in directives), \
        "Host migration-target does not explicitly enable PubkeyAuthentication."
    assert any(len(parts) >= 2 and parts[0].lower() == "identityfile" and parts[1] == "/home/user/.ssh/migration_key" for parts in directives), \
        "Host migration-target does not use /home/user/.ssh/migration_key."


def test_python_script_fixed():
    script_path = "/home/user/validate_deployment.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original source assertion; behavioral coverage is below.
    assert "try" in content and "except" in content, "Python script does not contain a try-except block for error handling."


def test_report_json_generated():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"{report_path} was not generated."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} is not valid JSON."

    expected_data = {
        "web": "OK",
        "email": "MISSING_CERT"
    }
    assert report_data == expected_data, f"Report data {report_data} does not match expected {expected_data}."


def test_script_handles_dynamic_existing_and_missing_certificates():
    script_path = "/home/user/validate_deployment.py"
    manifest_path = "/home/user/services.json"
    report_path = "/home/user/report.json"

    token = secrets.token_hex(12)
    service_names = [f"service_{token}_{i}" for i in range(4)]
    cert_paths = [f"/home/user/certs/verifier_{token}_{i}.crt" for i in range(4)]
    existing_indexes = {0, 2}

    manifest = {}
    expected = {}
    for i, service_name in enumerate(service_names):
        manifest[service_name] = {
            "domain": f"{service_name}.invalid",
            "tls_cert": cert_paths[i],
        }
        expected[service_name] = "OK" if i in existing_indexes else "MISSING_CERT"

    with open(manifest_path, "rb") as f:
        original_manifest = f.read()
    original_report_exists = os.path.exists(report_path)
    original_report = None
    if original_report_exists:
        with open(report_path, "rb") as f:
            original_report = f.read()

    try:
        for i, cert_path in enumerate(cert_paths):
            if os.path.lexists(cert_path):
                os.unlink(cert_path)
            if i in existing_indexes:
                with open(cert_path, "w") as f:
                    f.write(f"dynamic certificate contents {secrets.token_hex(16)}\n")

        with open(manifest_path, "w") as f:
            json.dump(manifest, f)
        if os.path.exists(report_path):
            os.unlink(report_path)

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Validation script crashed:\n{result.stderr}"
        assert os.path.isfile(report_path), "Validation script did not generate report.json."

        with open(report_path, "r") as f:
            generated = json.load(f)
        assert generated == expected, f"Dynamic report {generated} does not match expected {expected}."
    finally:
        with open(manifest_path, "wb") as f:
            f.write(original_manifest)
        for cert_path in cert_paths:
            if os.path.lexists(cert_path):
                os.unlink(cert_path)
        if original_report_exists:
            with open(report_path, "wb") as f:
                f.write(original_report)
        elif os.path.exists(report_path):
            os.unlink(report_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
