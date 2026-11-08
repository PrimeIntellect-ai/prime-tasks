#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import secrets
import shutil
import stat
import subprocess

import pytest


def run(cmd, timeout=20):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def load_report():
    report_path = "/home/user/audit.json"
    assert os.path.isfile(report_path), f"{report_path} is missing."
    with open(report_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} does not contain valid JSON.")


def test_certs_generated_and_valid():
    crt_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"
    script_path = "/home/user/gen_certs.sh"

    # Preserve the original artifact assertions.
    assert os.path.isfile(crt_path), f"{crt_path} is missing."
    assert os.path.isfile(key_path), f"{key_path} is missing."

    cmd_subject = ["openssl", "x509", "-in", crt_path, "-noout", "-subject"]
    result_subject = run(cmd_subject)
    assert result_subject.returncode == 0, "Failed to read certificate subject."
    assert "CN = policy.local" in result_subject.stdout or "CN=policy.local" in result_subject.stdout, \
        "Certificate Subject CN is not 'policy.local'."

    cmd_key = ["openssl", "rsa", "-in", key_path, "-noout", "-text"]
    result_key = run(cmd_key)
    assert result_key.returncode == 0, "Failed to read private key."
    assert "Private-Key: (2048 bit" in result_key.stdout, "Private key is not RSA 2048-bit."

    # The required generator must exist and recreate the artifacts when executed.
    assert os.path.isfile(script_path), f"{script_path} is missing."
    with open(script_path, "r", errors="replace") as f:
        script_text = f.read()
    assert "openssl" in script_text, "The certificate generator does not invoke openssl."

    os.remove(crt_path)
    os.remove(key_path)
    generated = run(["bash", script_path], timeout=30)
    assert generated.returncode == 0, \
        f"Certificate generator failed:\n{generated.stdout}\n{generated.stderr}"
    assert os.path.isfile(crt_path), f"{crt_path} was not regenerated."
    assert os.path.isfile(key_path), f"{key_path} was not regenerated."

    subject = run(["openssl", "x509", "-in", crt_path, "-noout", "-subject"])
    issuer = run(["openssl", "x509", "-in", crt_path, "-noout", "-issuer"])
    assert subject.returncode == 0 and issuer.returncode == 0, "Generated certificate is unreadable."
    subject_value = subject.stdout.strip().split("=", 1)[-1].strip()
    issuer_value = issuer.stdout.strip().split("=", 1)[-1].strip()
    assert subject_value == issuer_value, "Certificate is not self-signed."
    assert "CN = policy.local" in subject.stdout or "CN=policy.local" in subject.stdout, \
        "Generated certificate CN is not policy.local."

    verified = run(["openssl", "verify", "-CAfile", crt_path, crt_path])
    assert verified.returncode == 0, "Certificate does not verify as self-signed."

    cert_pub = run(["openssl", "x509", "-in", crt_path, "-noout", "-pubkey"])
    key_pub = run(["openssl", "pkey", "-in", key_path, "-pubout"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0, "Unable to extract public keys."
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), \
        "Certificate and private key are not a matching pair."

    key_info = run(["openssl", "rsa", "-in", key_path, "-noout", "-text"])
    assert key_info.returncode == 0
    assert "Private-Key: (2048 bit" in key_info.stdout, "Generated key is not RSA 2048-bit."

    dates = run(["openssl", "x509", "-in", crt_path, "-noout", "-dates"])
    assert dates.returncode == 0, "Unable to read certificate validity dates."
    values = dict(line.split("=", 1) for line in dates.stdout.strip().splitlines())
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt)
    assert not_after - not_before == datetime.timedelta(days=30), \
        "Certificate validity is not exactly 30 days."
    validity = run(["openssl", "x509", "-in", crt_path, "-noout", "-checkend", "0"])
    assert validity.returncode == 0, "Generated certificate is not currently valid."


def test_redaction_log_content():
    clean_log_path = "/home/user/data/transactions_clean.log"
    assert os.path.isfile(clean_log_path), f"{clean_log_path} is missing."

    with open(clean_log_path, "r") as f:
        content = f.read().strip()

    expected_content = "User Alice paid with **************** today. Valid until 12/25. Another user Bob used **************** for his transaction. Order 98765 is complete."
    assert content == expected_content, "Redacted log content is incorrect. 16-digit sequences were not redacted properly."


def test_audit_json_report():
    data = load_report()
    assert "suid_files" in data, "'suid_files' key is missing from JSON report."
    assert "unauthorized_ports" in data, "'unauthorized_ports' key is missing from JSON report."

    expected_suid = [
        "/home/user/jail/bin/backdoor",
        "/home/user/jail/bin/sneaky_suid"
    ]
    expected_ports = [3306, 8080]

    assert data["suid_files"] == expected_suid, f"'suid_files' list is incorrect or not sorted alphabetically. Expected: {expected_suid}"
    assert data["unauthorized_ports"] == expected_ports, f"'unauthorized_ports' list is incorrect or not sorted numerically. Expected: {expected_ports}"


def make_dynamic_fixture(tag):
    log_path = "/home/user/data/transactions.log"
    ports_path = "/home/user/data/open_ports.txt"
    jail = "/home/user/jail/bin"

    d16a = f"{secrets.randbelow(10**16):016d}"
    d16b = f"{secrets.randbelow(10**16):016d}"
    d15 = f"{secrets.randbelow(10**15):015d}"
    d17 = "9" + f"{secrets.randbelow(10**16):016d}"
    source = f"{tag}: exact {d16a}; short {d15}; long {d17}; edge {d16b}\n"
    expected_clean = re.sub(r"(?<!\d)\d{16}(?!\d)", "****************", source)
    with open(log_path, "w") as f:
        f.write(source)

    unauthorized = set()
    while len(unauthorized) < 4:
        port = secrets.randbelow(64000) + 1024
        if port not in (22, 443):
            unauthorized.add(port)
    port_lines = [443, *unauthorized, 22]
    # Deliberately use an order unrelated to the expected sorted result.
    port_lines = sorted(port_lines, key=lambda _: secrets.randbits(64))
    with open(ports_path, "w") as f:
        for port in port_lines:
            f.write(f"{port}\n")

    for entry in os.scandir(jail):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)

    suffix = secrets.token_hex(5)
    suid_names = [f"zeta_{suffix}", f"alpha_{suffix}", f"middle_{suffix}"]
    for name in suid_names:
        path = os.path.join(jail, name)
        with open(path, "wb") as f:
            f.write(b"fixture")
        os.chmod(path, 0o4755)

    normal = os.path.join(jail, f"normal_{suffix}")
    with open(normal, "wb") as f:
        f.write(b"fixture")
    os.chmod(normal, 0o755)

    nested_dir = os.path.join(jail, f"nested_{suffix}")
    os.mkdir(nested_dir)
    nested_suid = os.path.join(nested_dir, "must_not_be_reported")
    with open(nested_suid, "wb") as f:
        f.write(b"fixture")
    os.chmod(nested_suid, 0o4755)

    expected_suid = sorted(os.path.join(jail, name) for name in suid_names)
    return expected_clean, expected_suid, sorted(unauthorized)


def assert_dynamic_outputs(expected_clean, expected_suid, expected_ports):
    with open("/home/user/data/transactions_clean.log", "r") as f:
        assert f.read() == expected_clean, "Auditor did not correctly redact the dynamic log."

    data = load_report()
    expected = {
        "suid_files": expected_suid,
        "unauthorized_ports": expected_ports,
    }
    assert data == expected, "Auditor report is incorrect for the dynamic fixture."


def test_auditor_artifacts_compile_and_function_dynamically():
    source_path = "/home/user/auditor.c"
    binary_path = "/home/user/auditor"
    assert os.path.isfile(source_path), f"{source_path} is missing."
    assert os.path.isfile(binary_path), f"{binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not an ELF executable."

    expected = make_dynamic_fixture("installed-" + secrets.token_hex(6))
    result = run([binary_path])
    assert result.returncode == 0, f"Installed auditor failed:\n{result.stdout}\n{result.stderr}"
    assert_dynamic_outputs(*expected)

    rebuilt_path = "/tmp/auditor_rebuilt"
    compiled = run(["gcc", source_path, "-o", rebuilt_path], timeout=30)
    assert compiled.returncode == 0, f"auditor.c does not compile:\n{compiled.stdout}\n{compiled.stderr}"

    expected = make_dynamic_fixture("rebuilt-" + secrets.token_hex(6))
    result = run([rebuilt_path])
    assert result.returncode == 0, f"Rebuilt auditor failed:\n{result.stdout}\n{result.stderr}"
    assert_dynamic_outputs(*expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
