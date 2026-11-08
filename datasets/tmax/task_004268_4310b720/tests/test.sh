#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest

APP_BINARY = "/home/user/app_binary"
CERT_PEM = "/home/user/cert.pem"
REPORT = "/home/user/audit_report.json"
PROJECT = "/home/user/elf_auditor"


def get_entry_point(binary_path):
    try:
        output = subprocess.check_output(
            ['readelf', '-h', binary_path], text=True
        )
        for line in output.splitlines():
            if "Entry point address:" in line:
                return line.strip().split()[-1].lower()
    except Exception:
        pass
    return None


def get_policy(binary_path):
    with tempfile.TemporaryDirectory() as td:
        section_path = os.path.join(td, "policy.bin")
        subprocess.run(
            ['objcopy', f'--dump-section', f'.audit_policy={section_path}', binary_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        with open(section_path, 'rb') as f:
            return f.read().decode('utf-8')


def get_cert_cn(cert_path):
    output = subprocess.check_output(
        ['openssl', 'x509', '-in', cert_path, '-noout', '-subject', '-nameopt', 'RFC2253'],
        text=True,
    ).strip()
    subject = output.split('=', 1)[1] if '=' in output else output
    match = re.search(r'(?:^|,)CN=([^,]+)', subject)
    assert match, f"Could not determine certificate CN from: {output}"
    return match.group(1)


def run_auditor():
    subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', os.path.join(PROJECT, 'Cargo.toml')],
        cwd=PROJECT,
        check=True,
        timeout=300,
    )


def load_report():
    assert os.path.exists(REPORT), f"Missing required file: {REPORT}"
    with open(REPORT, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT} is not a valid JSON file")


def test_audit_report_json():
    data = load_report()

    assert "entry_point" in data, "Missing 'entry_point' in JSON report"
    assert "policy" in data, "Missing 'policy' in JSON report"
    assert "cert_cn" in data, "Missing 'cert_cn' in JSON report"
    assert set(data) == {"entry_point", "policy", "cert_cn"}, "JSON report must contain exactly the required keys"

    expected_entry_point = get_entry_point(APP_BINARY)
    assert expected_entry_point is not None, "Could not determine entry point of app_binary"

    actual_ep = data["entry_point"].lower()
    assert actual_ep == expected_entry_point or actual_ep == hex(int(expected_entry_point, 16)), \
        f"Expected entry_point to be {expected_entry_point}, got {data['entry_point']}"

    assert data["policy"] == "PORT=8443", f"Expected policy to be 'PORT=8443', got {data['policy']}"
    assert data["cert_cn"] == "SecureCorpApp", f"Expected cert_cn to be 'SecureCorpApp', got {data['cert_cn']}"


def test_fw_config_sh():
    script_path = "/home/user/fw_config.sh"
    assert os.path.exists(script_path), f"Missing required file: {script_path}"

    with open(script_path, 'r') as f:
        content = f.read()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith('#')]
    assert len(lines) >= 2, "fw_config.sh must contain at least two iptables commands"
    assert len(lines) == 2, "fw_config.sh must contain exactly two iptables commands"

    accept_pattern = re.compile(r'iptables\s+.*-p\s+tcp\s+.*--dport\s+8443\s+.*-s\s+192\.168\.1\.100\s+.*-j\s+ACCEPT')
    drop_pattern = re.compile(r'iptables\s+.*-p\s+tcp\s+.*--dport\s+8443\s+.*-j\s+DROP')

    accept_found = any(accept_pattern.search(line) for line in lines)
    drop_found = any(drop_pattern.search(line) for line in lines)

    assert accept_found, "fw_config.sh missing correct ACCEPT rule for port 8443 and IP 192.168.1.100"
    assert drop_found, "fw_config.sh missing correct DROP rule for port 8443"


def test_rust_project_exists_and_runs_on_derived_inputs():
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Missing Rust project file: {cargo_toml}"

    subprocess.run(
        ['cargo', 'build', '--manifest-path', cargo_toml],
        cwd=PROJECT,
        check=True,
        timeout=300,
    )

    with tempfile.TemporaryDirectory() as td:
        saved_binary = os.path.join(td, "saved_app_binary")
        saved_cert = os.path.join(td, "saved_cert.pem")
        shutil.copy2(APP_BINARY, saved_binary)
        shutil.copy2(CERT_PEM, saved_cert)

        token = uuid.uuid4().hex[:12]
        challenge_port = random.SystemRandom().randint(20000, 60000)
        challenge_policy = f"PORT={challenge_port}"
        challenge_cn = f"AuditChallenge{token}"

        source = os.path.join(td, "challenge.c")
        base_binary = os.path.join(td, "challenge_base")
        policy_file = os.path.join(td, "policy.txt")
        challenge_binary = os.path.join(td, "challenge_binary")
        challenge_cert = os.path.join(td, "challenge_cert.pem")
        challenge_key = os.path.join(td, "challenge_key.pem")

        with open(source, 'w') as f:
            f.write(f'int audit_value_{token}(void) {{ return {challenge_port}; }}\nint main(void) {{ return audit_value_{token}() == 0; }}\n')
        with open(policy_file, 'wb') as f:
            f.write(challenge_policy.encode('utf-8'))

        subprocess.run(['gcc', source, '-o', base_binary], check=True)
        subprocess.run(
            ['objcopy', '--add-section', f'.audit_policy={policy_file}',
             '--set-section-flags', '.audit_policy=noload,readonly',
             base_binary, challenge_binary],
            check=True,
        )
        subprocess.run(
            ['openssl', 'req', '-x509', '-newkey', 'rsa:2048',
             '-keyout', challenge_key, '-out', challenge_cert,
             '-days', '1', '-nodes', '-subj', f'/CN={challenge_cn}'],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        try:
            shutil.copy2(challenge_binary, APP_BINARY)
            shutil.copy2(challenge_cert, CERT_PEM)
            if os.path.exists(REPORT):
                os.unlink(REPORT)

            expected_entry = get_entry_point(APP_BINARY)
            expected_policy = get_policy(APP_BINARY)
            expected_cn = get_cert_cn(CERT_PEM)
            assert expected_entry is not None

            run_auditor()
            data = load_report()
            assert set(data) == {"entry_point", "policy", "cert_cn"}, "JSON report must contain exactly the required keys"
            actual_ep = data["entry_point"].lower()
            assert actual_ep == expected_entry or actual_ep == hex(int(expected_entry, 16)), \
                f"Auditor did not extract challenge entry point: expected {expected_entry}, got {data['entry_point']}"
            assert data["policy"] == expected_policy, \
                f"Auditor did not extract challenge policy: expected {expected_policy}, got {data['policy']}"
            assert data["cert_cn"] == expected_cn, \
                f"Auditor did not extract challenge CN: expected {expected_cn}, got {data['cert_cn']}"
        finally:
            shutil.copy2(saved_binary, APP_BINARY)
            shutil.copy2(saved_cert, CERT_PEM)
            if os.path.exists(REPORT):
                os.unlink(REPORT)
            try:
                run_auditor()
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
