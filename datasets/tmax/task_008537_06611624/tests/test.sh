#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import shutil
import subprocess
import tempfile


def test_script_exists_and_executable():
    script_path = "/home/user/analyze_requests.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_audit_log_exists_and_correct():
    log_path = "/home/user/audit_log.csv"
    assert os.path.isfile(log_path), f"Audit log {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "req1.b64,AUTH_OK,CLEAN",
        "req2.b64,AUTH_FAIL,CLEAN",
        "req3.b64,AUTH_OK,THREAT_DETECTED",
        "req4.b64,AUTH_FAIL,THREAT_DETECTED"
    ]

    # The instructions specify sorting alphabetically by filename
    expected_lines.sort()

    assert lines == expected_lines, f"Audit log content is incorrect. Expected {expected_lines}, but got {lines}."


def test_script_processes_dynamic_requests():
    script_path = "/home/user/analyze_requests.sh"
    incoming = "/home/user/incoming_requests"
    signatures_path = "/home/user/signatures.txt"
    log_path = "/home/user/audit_log.csv"

    nonce = secrets.token_hex(10)
    valid_token = secrets.token_hex(8)
    exact_signature = f"attack-{nonce}"
    regex_like_signature = f"probe[0-9]-{nonce}"
    signatures = [exact_signature, regex_like_signature]

    requests = {
        f"zeta-{nonce}.b64": (
            valid_token,
            '{"message":"ordinary payload"}',
            []
        ),
        f"alpha-{nonce}.b64": (
            valid_token,
            f'{{"message":"contains {exact_signature} here"}}',
            []
        ),
        f"mu-{nonce}.b64": (
            "A" + valid_token[1:],
            f'{{"message":"contains {regex_like_signature}"}}',
            []
        ),
        f"beta-{nonce}.b64": (
            None,
            '{"message":"no authorization header"}',
            []
        ),
        f"kappa-{nonce}.b64": (
            valid_token + "0",
            f'{{"message":"probe5-{nonce}"}}',
            []
        ),
        f"delta-{nonce}.b64": (
            valid_token,
            '{"message":"signature is only in a header"}',
            [f"X-Diagnostic: {exact_signature}"]
        ),
    }

    def make_raw(token, body, extra_headers):
        headers = [
            "POST /dynamic HTTP/1.1",
            "Host: verifier.example",
        ]
        if token is not None:
            headers.append(f"Authorization: Bearer {token}")
        headers.extend(extra_headers)
        headers.append("Content-Type: application/json")
        return "\n".join(headers) + "\n\n" + body + "\n"

    raw_requests = {
        filename: make_raw(token, body, extra_headers)
        for filename, (token, body, extra_headers) in requests.items()
    }

    def derive_expected(filename, raw):
        headers, separator, body = raw.partition("\n\n")
        if not separator:
            body = ""
        match = re.search(r"(?m)^Authorization: Bearer ([^\r\n]*)$", headers)
        token = match.group(1) if match else None
        auth = "AUTH_OK" if token is not None and re.fullmatch(r"[0-9a-f]{16}", token) else "AUTH_FAIL"
        threat = "THREAT_DETECTED" if any(signature in body for signature in signatures) else "CLEAN"
        return f"{filename},{auth},{threat}"

    expected = sorted(
        derive_expected(filename, raw)
        for filename, raw in raw_requests.items()
    )

    with tempfile.TemporaryDirectory() as backup_root:
        incoming_backup = os.path.join(backup_root, "incoming_requests")
        shutil.copytree(incoming, incoming_backup)
        with open(signatures_path, "rb") as f:
            original_signatures = f.read()
        original_log = None
        if os.path.isfile(log_path):
            with open(log_path, "rb") as f:
                original_log = f.read()

        try:
            shutil.rmtree(incoming)
            os.makedirs(incoming)
            with open(signatures_path, "w") as f:
                for signature in signatures:
                    f.write(signature + "\n")

            for filename, raw in raw_requests.items():
                encoded = base64.b64encode(raw.encode("utf-8"))
                with open(os.path.join(incoming, filename), "wb") as f:
                    f.write(encoded)

            if os.path.exists(log_path):
                os.remove(log_path)

            result = subprocess.run(
                [script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"Script failed on dynamic requests with exit code {result.returncode}. "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(log_path), "Script did not generate /home/user/audit_log.csv"

            with open(log_path, "r") as f:
                actual = [line.strip() for line in f if line.strip()]

            assert actual == expected, (
                f"Dynamic audit log is incorrect. Expected {expected}, but got {actual}."
            )
        finally:
            shutil.rmtree(incoming, ignore_errors=True)
            shutil.copytree(incoming_backup, incoming)
            with open(signatures_path, "wb") as f:
                f.write(original_signatures)
            if original_log is None:
                if os.path.exists(log_path):
                    os.remove(log_path)
            else:
                with open(log_path, "wb") as f:
                    f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
