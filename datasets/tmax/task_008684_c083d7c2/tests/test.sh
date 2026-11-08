#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import tempfile
import pytest

EXPECTED = "socat openssl-listen:8443,reuseaddr,fork,cert=/home/user/certs/cert.pem,key=/home/user/certs/key.pem,verify=0 tcp:127.0.0.1:9090"


def test_qcow2_images():
    base_path = "/home/user/backup/base.qcow2"
    snap_path = "/home/user/backup/snapshot.qcow2"

    assert os.path.isfile(base_path), f"Base image not found at {base_path}"
    assert os.path.isfile(snap_path), f"Snapshot image not found at {snap_path}"

    result = subprocess.run(["qemu-img", "info", "--output=json", base_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run qemu-img on {base_path}"
    base_info = json.loads(result.stdout)
    assert base_info.get("virtual-size") == 50 * 1024 * 1024, "Base image size is not 50M"
    assert base_info.get("format") == "qcow2", "Base image format is not qcow2"

    result = subprocess.run(["qemu-img", "info", "--output=json", snap_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run qemu-img on {snap_path}"
    snap_info = json.loads(result.stdout)
    backing_file = snap_info.get("backing-filename")
    assert backing_file is not None, "Snapshot image does not have a backing file"
    assert "base.qcow2" in backing_file, f"Snapshot backing file is not base.qcow2 (got {backing_file})"
    assert snap_info.get("format") == "qcow2", "Snapshot image format is not qcow2"


def test_tls_certificates():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"

    assert os.path.isfile(cert_path), f"Certificate not found at {cert_path}"
    assert os.path.isfile(key_path), f"Private key not found at {key_path}"

    result = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-subject"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read certificate subject"
    assert "CN = localhost" in result.stdout or "CN=localhost" in result.stdout, "Certificate Common Name (CN) is not localhost"

    result = subprocess.run(["openssl", "rsa", "-in", key_path, "-check", "-noout"], capture_output=True, text=True)
    assert result.returncode == 0, "Private key is invalid or not an unencrypted RSA key"

    result = subprocess.run(["openssl", "rsa", "-in", key_path, "-noout", "-text"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to inspect RSA private key"
    assert "Private-Key: (2048 bit" in result.stdout, "Private key is not 2048-bit RSA"

    cert_pub = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-pubkey"], capture_output=True)
    assert cert_pub.returncode == 0, "Failed to extract certificate public key"
    cert_pub_der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub.stdout, capture_output=True)
    assert cert_pub_der.returncode == 0, "Certificate does not contain a valid public key"

    key_pub_der = subprocess.run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"], capture_output=True)
    assert key_pub_der.returncode == 0, "Failed to derive public key from private key"
    assert cert_pub_der.stdout == key_pub_der.stdout, "Certificate and private key do not match"

    result = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to inspect certificate issuer"
    fields = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            fields[name.strip()] = value.strip()
    assert fields.get("subject") == fields.get("issuer"), "Certificate is not self-issued"

    result = subprocess.run(["openssl", "verify", "-CAfile", cert_path, cert_path], capture_output=True, text=True)
    assert result.returncode == 0, "Certificate signature does not verify as self-signed"


def test_port_manager_source_and_executable():
    source_path = "/home/user/src/port_manager.cpp"
    bin_path = "/home/user/bin/port_manager"

    assert os.path.isfile(source_path), f"C++ source not found at {source_path}"
    assert os.path.isfile(bin_path), f"Compiled binary not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Binary at {bin_path} is not executable"

    with open(bin_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"File at {bin_path} is not an ELF executable"

    submitted = subprocess.run([bin_path], capture_output=True, text=True, timeout=5)
    assert submitted.returncode == 0, "Submitted port_manager executable failed"
    assert submitted.stdout == EXPECTED + "\n", "Submitted port_manager output is incorrect"

    fd, rebuilt_path = tempfile.mkstemp(prefix="port_manager_rebuilt_")
    os.close(fd)
    os.unlink(rebuilt_path)
    try:
        build = subprocess.run(["g++", source_path, "-o", rebuilt_path], capture_output=True, text=True, timeout=30)
        assert build.returncode == 0, f"port_manager.cpp does not compile: {build.stderr}"
        rebuilt = subprocess.run([rebuilt_path], capture_output=True, text=True, timeout=5)
        assert rebuilt.returncode == 0, "Executable rebuilt from port_manager.cpp failed"
        assert rebuilt.stdout == EXPECTED + "\n", "Rebuilt port_manager output is incorrect"
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)


def test_start_proxy_script():
    script_path = "/home/user/start_proxy.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED, f"Script content is incorrect. Expected: {EXPECTED}, Got: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
