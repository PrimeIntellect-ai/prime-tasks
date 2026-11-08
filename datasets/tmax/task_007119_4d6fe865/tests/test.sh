#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

DEPLOY_DIR = "/home/user/deploy_artifact"
SCRIPT_FILE = "/home/user/audit_trail.py"
REPORT_FILE = "/home/user/audit_report.json"
EXPECTED_KEYS = {
    "integrity_failures",
    "certificate_valid",
    "vulnerable_files",
    "world_writable_files",
}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def make_valid_certificates():
    with tempfile.TemporaryDirectory() as td:
        ca_key = os.path.join(td, "ca.key")
        ca_crt = os.path.join(td, "ca.crt")
        server_key = os.path.join(td, "server.key")
        server_csr = os.path.join(td, "server.csr")
        server_crt = os.path.join(td, "server.crt")

        subprocess.run([
            "openssl", "req", "-x509", "-sha256", "-nodes", "-days", "365",
            "-newkey", "rsa:2048", "-keyout", ca_key, "-out", ca_crt,
            "-subj", "/C=US/ST=Test/L=Test/O=Test CA/CN=Test Root CA",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([
            "openssl", "req", "-new", "-nodes", "-newkey", "rsa:2048",
            "-keyout", server_key, "-out", server_csr,
            "-subj", "/C=US/ST=Test/L=Test/O=Test Server/CN=localhost",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([
            "openssl", "x509", "-req", "-in", server_csr,
            "-CA", ca_crt, "-CAkey", ca_key, "-CAcreateserial",
            "-out", server_crt, "-days", "365", "-sha256",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        shutil.copyfile(ca_crt, os.path.join(DEPLOY_DIR, "ca.crt"))
        shutil.copyfile(server_crt, os.path.join(DEPLOY_DIR, "server.crt"))


def prepare_canonical_artifact():
    shutil.rmtree(DEPLOY_DIR, ignore_errors=True)
    os.makedirs(DEPLOY_DIR)

    with open(os.path.join(DEPLOY_DIR, "app.py"), "w") as f:
        f.write('''import os\nfrom flask import Flask, request\napp = Flask(__name__)\n\n@app.route('/ping')\ndef ping():\n    ip = request.args.get('ip', '127.0.0.1')\n    return os.popen(f"ping -c 1 {ip}").read()\n''')
    with open(os.path.join(DEPLOY_DIR, "config.yaml"), "w") as f:
        f.write("debug: true\nport: 8080\n")

    make_valid_certificates()

    with open(os.path.join(DEPLOY_DIR, "manifest.txt"), "w") as f:
        f.write("a" * 64 + " app.py\n")
        for name in ("config.yaml", "server.crt", "ca.crt"):
            f.write(f"{sha256(os.path.join(DEPLOY_DIR, name))} {name}\n")

    # Reproduce the permissions present after the supplied setup script.
    for name in os.listdir(DEPLOY_DIR):
        os.chmod(os.path.join(DEPLOY_DIR, name), 0o777)


def prepare_changed_artifact():
    prepare_canonical_artifact()

    with open(os.path.join(DEPLOY_DIR, "app.py"), "w") as f:
        f.write("print('safe')\n")
    with open(os.path.join(DEPLOY_DIR, "danger.py"), "w") as f:
        f.write("import os\nresult = os.popen('id').read()\n")
    with open(os.path.join(DEPLOY_DIR, "server.crt"), "w") as f:
        f.write("this is not a certificate\n")

    manifest_names = ("app.py", "config.yaml", "server.crt", "ca.crt", "danger.py")
    with open(os.path.join(DEPLOY_DIR, "manifest.txt"), "w") as f:
        for name in manifest_names:
            f.write(f"{sha256(os.path.join(DEPLOY_DIR, name))} {name}\n")

    for name in os.listdir(DEPLOY_DIR):
        os.chmod(os.path.join(DEPLOY_DIR, name), 0o644)
    os.chmod(os.path.join(DEPLOY_DIR, "danger.py"), 0o666)


def get_expected_integrity_failures():
    manifest_path = os.path.join(DEPLOY_DIR, "manifest.txt")
    failures = []
    if not os.path.exists(manifest_path):
        return failures
    with open(manifest_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                expected_hash, filename = parts
                file_path = os.path.join(DEPLOY_DIR, filename)
                if not os.path.exists(file_path):
                    failures.append(filename)
                    continue
                with open(file_path, "rb") as tf:
                    actual_hash = hashlib.sha256(tf.read()).hexdigest()
                if actual_hash != expected_hash:
                    failures.append(filename)
    return sorted(failures)


def get_expected_certificate_valid():
    ca_crt = os.path.join(DEPLOY_DIR, "ca.crt")
    server_crt = os.path.join(DEPLOY_DIR, "server.crt")
    if not os.path.exists(ca_crt) or not os.path.exists(server_crt):
        return False
    result = subprocess.run(
        ["openssl", "verify", "-CAfile", ca_crt, server_crt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.returncode == 0


def get_expected_vulnerable_files():
    vulnerable = []
    if not os.path.exists(DEPLOY_DIR):
        return vulnerable
    for filename in os.listdir(DEPLOY_DIR):
        if filename.endswith(".py"):
            file_path = os.path.join(DEPLOY_DIR, filename)
            if os.path.isfile(file_path):
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    if "os.popen(" in f.read():
                        vulnerable.append(filename)
    return sorted(vulnerable)


def get_expected_world_writable_files():
    world_writable = []
    if not os.path.exists(DEPLOY_DIR):
        return world_writable
    for filename in os.listdir(DEPLOY_DIR):
        file_path = os.path.join(DEPLOY_DIR, filename)
        if os.path.isfile(file_path):
            if os.stat(file_path).st_mode & 0o002:
                world_writable.append(filename)
    return sorted(world_writable)


def expected_report():
    return {
        "integrity_failures": get_expected_integrity_failures(),
        "certificate_valid": get_expected_certificate_valid(),
        "vulnerable_files": get_expected_vulnerable_files(),
        "world_writable_files": get_expected_world_writable_files(),
    }


def run_submission():
    assert os.path.lexists(SCRIPT_FILE), f"Audit script {SCRIPT_FILE} does not exist."
    mode = os.lstat(SCRIPT_FILE).st_mode
    assert stat.S_ISREG(mode), f"Audit script {SCRIPT_FILE} is not a regular file."

    if os.path.lexists(REPORT_FILE):
        os.remove(REPORT_FILE)
    result = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Audit script exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_FILE), f"Audit report file {REPORT_FILE} does not exist."
    try:
        with open(REPORT_FILE, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_FILE} is not valid JSON: {exc}")


def assert_strict_structure(data):
    assert isinstance(data, dict), "Audit report must be a JSON object."
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"Report keys must be exactly {EXPECTED_KEYS}; found {set(data.keys())}"
    )
    assert isinstance(data["integrity_failures"], list)
    assert type(data["certificate_valid"]) is bool
    assert isinstance(data["vulnerable_files"], list)
    assert isinstance(data["world_writable_files"], list)
    for key in ("integrity_failures", "vulnerable_files", "world_writable_files"):
        assert all(isinstance(value, str) for value in data[key])
        assert all(os.path.basename(value) == value for value in data[key])


@pytest.fixture(scope="module")
def canonical_result():
    prepare_canonical_artifact()
    expected = expected_report()
    actual = run_submission()
    return actual, expected


def test_report_structure(canonical_result):
    actual, _ = canonical_result
    assert_strict_structure(actual)


def test_integrity_failures(canonical_result):
    actual, expected = canonical_result
    assert sorted(actual["integrity_failures"]) == expected["integrity_failures"]


def test_certificate_valid(canonical_result):
    actual, expected = canonical_result
    assert actual["certificate_valid"] is expected["certificate_valid"]


def test_vulnerable_files(canonical_result):
    actual, expected = canonical_result
    assert sorted(actual["vulnerable_files"]) == expected["vulnerable_files"]


def test_world_writable_files(canonical_result):
    actual, expected = canonical_result
    assert sorted(actual["world_writable_files"]) == expected["world_writable_files"]


def test_script_handles_changed_artifact(canonical_result):
    # Exercise the submitted script on a second independently derived state so a
    # prewritten report for the staging artifact cannot pass.
    prepare_changed_artifact()
    expected = expected_report()
    actual = run_submission()
    assert_strict_structure(actual)
    assert sorted(actual["integrity_failures"]) == expected["integrity_failures"]
    assert actual["certificate_valid"] is expected["certificate_valid"]
    assert sorted(actual["vulnerable_files"]) == expected["vulnerable_files"]
    assert sorted(actual["world_writable_files"]) == expected["world_writable_files"]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
