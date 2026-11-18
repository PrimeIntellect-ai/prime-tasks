#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import stat
import subprocess

import pytest

HOME = "/home/user"
LOG_PATH = os.path.join(HOME, "gateway_logs.json")
CA_PATH = os.path.join(HOME, "ca-chain.pem")
CERTS_DIR = os.path.join(HOME, "certs")
SCRIPT_PATH = os.path.join(HOME, "analyze.py")
OUTPUT_PATH = os.path.join(HOME, "compromised_sessions.txt")


def run_checked(command):
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def make_ca(workdir, prefix):
    key = os.path.join(workdir, prefix + "_key.pem")
    cert = os.path.join(workdir, prefix + "_ca.pem")
    run_checked([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key, "-out", cert, "-days", "2", "-nodes",
        "-subj", "/CN=" + prefix,
    ])
    return key, cert


def make_cert(workdir, name, ca_key, ca_cert, serial):
    key = os.path.join(workdir, name + "_key.pem")
    csr = os.path.join(workdir, name + ".csr")
    cert = os.path.join(workdir, name + ".pem")
    run_checked([
        "openssl", "req", "-newkey", "rsa:2048", "-keyout", key,
        "-out", csr, "-nodes", "-subj", "/CN=" + name,
    ])
    run_checked([
        "openssl", "x509", "-req", "-in", csr, "-CA", ca_cert,
        "-CAkey", ca_key, "-set_serial", str(serial), "-out", cert,
        "-days", "2",
    ])
    return cert


def get_expected_compromised_sessions():
    """Derive expected sessions from the verifier-installed log and certificates."""
    assert os.path.exists(LOG_PATH), f"Gateway logs file missing: {LOG_PATH}"

    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        try:
            logs = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"Gateway logs file does not contain valid JSON: {LOG_PATH}")

    compromised_ids = []
    for entry in logs:
        req_id = entry.get("req_id")
        client_cert_file = entry.get("client_cert_file")
        payload = entry.get("payload", "")
        response_code = entry.get("response_code")

        if response_code != 200:
            continue
        if "<script>" not in payload and "' OR " not in payload:
            continue

        cert_path = os.path.join(CERTS_DIR, client_cert_file)
        if not os.path.exists(cert_path):
            continue

        result = subprocess.run(
            ["openssl", "verify", "-CAfile", CA_PATH, cert_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        if result.returncode == 0:
            compromised_ids.append(req_id)

    return sorted(compromised_ids)


@pytest.fixture(scope="session", autouse=True)
def execute_submission(tmp_path_factory):
    assert os.path.exists(SCRIPT_PATH), f"Required analysis script missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "analyze.py must be a regular file, not a symlink"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "analyze.py is not a regular file"

    workdir = str(tmp_path_factory.mktemp("fresh_inputs"))
    trusted_key, trusted_ca = make_ca(workdir, "trusted_" + secrets.token_hex(4))
    rogue_key, rogue_ca = make_ca(workdir, "rogue_" + secrets.token_hex(4))

    token = secrets.token_hex(5)
    valid_a_name = "valid_a_" + token
    valid_b_name = "valid_b_" + token
    rogue_name = "rogue_" + token
    valid_a = make_cert(workdir, valid_a_name, trusted_key, trusted_ca, 101)
    valid_b = make_cert(workdir, valid_b_name, trusted_key, trusted_ca, 102)
    rogue = make_cert(workdir, rogue_name, rogue_key, rogue_ca, 103)

    remove_path(CERTS_DIR)
    os.makedirs(CERTS_DIR, mode=0o755)
    shutil.copyfile(valid_a, os.path.join(CERTS_DIR, valid_a_name + ".pem"))
    shutil.copyfile(valid_b, os.path.join(CERTS_DIR, valid_b_name + ".pem"))
    shutil.copyfile(rogue, os.path.join(CERTS_DIR, rogue_name + ".pem"))

    remove_path(CA_PATH)
    shutil.copyfile(trusted_ca, CA_PATH)

    ids = random.sample(range(10000, 90000), 8)
    logs = [
        {"req_id": ids[0], "client_cert_file": valid_a_name + ".pem", "payload": "{\\"u\\":\\"x<script>alert(1)</script>\\"}", "response_code": 200},
        {"req_id": ids[1], "client_cert_file": valid_b_name + ".pem", "payload": "{\\"u\\":\\"admin' OR 1=1--\\"}", "response_code": 200},
        {"req_id": ids[2], "client_cert_file": rogue_name + ".pem", "payload": "<script>rogue", "response_code": 200},
        {"req_id": ids[3], "client_cert_file": valid_a_name + ".pem", "payload": "admin' OR 1=1", "response_code": 403},
        {"req_id": ids[4], "client_cert_file": valid_b_name + ".pem", "payload": "ordinary credentials", "response_code": 200},
        {"req_id": ids[5], "client_cert_file": valid_a_name + ".pem", "payload": "<SCRIPT>wrong case</SCRIPT>", "response_code": 200},
        {"req_id": ids[6], "client_cert_file": valid_b_name + ".pem", "payload": "admin' or 1=1", "response_code": 200},
        {"req_id": ids[7], "client_cert_file": "missing_" + token + ".pem", "payload": "<script>x</script>", "response_code": 200},
    ]
    random.shuffle(logs)
    remove_path(LOG_PATH)
    with open(LOG_PATH, "w", encoding="utf-8") as handle:
        json.dump(logs, handle)

    expected = get_expected_compromised_sessions()
    assert expected == sorted([ids[0], ids[1]])

    remove_path(OUTPUT_PATH)
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.py did not finish within 30 seconds")

    assert result.returncode == 0, (
        f"analyze.py exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return expected


def test_compromised_sessions_file_exists(execute_submission):
    assert os.path.exists(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Path exists but is not a file: {OUTPUT_PATH}"
    assert not os.path.islink(OUTPUT_PATH), "Output path must be a regular file, not a symlink"


def test_compromised_sessions_content(execute_submission):
    assert os.path.exists(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"
    expected_ids = execute_submission

    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    actual_ids = []
    for line in lines:
        stripped = line.strip()
        if stripped:
            try:
                actual_ids.append(int(stripped))
            except ValueError:
                pytest.fail(f"Output file contains non-integer value: '{stripped}'")

    assert actual_ids == expected_ids, (
        "Output file contents do not match expected compromised req_ids.\n"
        f"Expected: {expected_ids}\nActual:   {actual_ids}"
    )
    assert lines == [str(req_id) for req_id in expected_ids], (
        "Output must contain exactly one req_id per line with no blank lines or extra text"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
