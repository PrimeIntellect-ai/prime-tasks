#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa


def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token(key, header=None, payload=None):
    header = header or {"alg": "RS256", "typ": "JWT"}
    payload = payload or {"nonce": secrets.token_hex(24)}
    h = b64url(json.dumps(header, separators=(",", ":")))
    p = b64url(json.dumps(payload, separators=(",", ":")))
    message = f"{h}.{p}".encode()
    signature = key.sign(message, padding.PKCS1v15(), hashes.SHA256())
    return f"{h}.{p}.{b64url(signature)}"


def write_token(directory, token):
    path = os.path.join(directory, secrets.token_hex(12))
    with open(path, "w") as f:
        f.write(token)
    return path


def run_validator(path, token_path, expected):
    result = subprocess.run([path, token_path], capture_output=True, timeout=5)
    assert result.returncode == expected, (
        f"{path} returned {result.returncode}, expected {expected}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_file_permissions():
    leaf_cert = "/app/keys/leaf_cert.pem"
    root_ca = "/app/keys/root_ca.pem"

    assert os.path.exists(leaf_cert), f"{leaf_cert} is missing."
    assert os.path.exists(root_ca), f"{root_ca} is missing."

    leaf_mode = stat.S_IMODE(os.stat(leaf_cert).st_mode)
    root_mode = stat.S_IMODE(os.stat(root_ca).st_mode)
    assert leaf_mode == 0o400, f"Expected 0400 permissions for {leaf_cert}, got {oct(leaf_mode)}"
    assert root_mode == 0o400, f"Expected 0400 permissions for {root_ca}, got {oct(root_mode)}"


def test_validator_adversarial_corpus_and_generated_inputs():
    validator_path = "/app/validator"
    source_path = "/app/validator.c"
    assert os.path.isfile(source_path), f"C source {source_path} is missing."
    assert os.path.isfile(validator_path), f"Validator binary {validator_path} is missing."
    assert os.access(validator_path, os.X_OK), f"Validator binary {validator_path} is not executable."

    with open(validator_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled validator must be an ELF executable, not a script."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "validator-from-source")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", rebuilt, "-lssl", "-lcrypto", "-lcjson", "-lm", "-ldl", "-lpthread"],
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, f"validator.c did not compile: {compile_result.stderr}"
        validators = [validator_path, rebuilt]

        clean_dir = "/app/corpus/clean/"
        evil_dir = "/app/corpus/evil/"
        clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
        evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
        assert clean_files, "Clean corpus is empty."
        assert evil_files, "Evil corpus is empty."

        for validator in validators:
            for token_file in clean_files:
                run_validator(validator, token_file, 0)
            for token_file in evil_files:
                run_validator(validator, token_file, 1)
            assert subprocess.run([validator], capture_output=True, timeout=5).returncode == 1
            assert subprocess.run([validator, clean_files[0], evil_files[0]], capture_output=True, timeout=5).returncode == 1

        with open("/app/issuer/leaf_cert.key", "rb") as f:
            signing_key = serialization.load_pem_private_key(f.read(), password=None)

        valid_paths = []
        for _ in range(4):
            valid_paths.append(write_token(td, make_token(signing_key)))

        none_header = b64url(json.dumps({"alg": "none", "typ": "JWT"}))
        none_payload = b64url(json.dumps({"nonce": secrets.token_hex(24)}))
        invalid_paths = [write_token(td, f"{none_header}.{none_payload}.")]

        valid = make_token(signing_key)
        h, p, s = valid.split(".")
        invalid_paths.append(write_token(td, f"{h}.{b64url(json.dumps({'nonce': secrets.token_hex(24)}))}.{s}"))
        invalid_paths.append(write_token(td, f"{h}.{p}.{b64url(os.urandom(256))}"))
        invalid_paths.append(write_token(td, "not.a.valid.token"))

        foreign_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        invalid_paths.append(write_token(td, make_token(foreign_key)))

        for validator in validators:
            for token_file in valid_paths:
                run_validator(validator, token_file, 0)
            for token_file in invalid_paths:
                run_validator(validator, token_file, 1)

        leaf_path = "/app/keys/leaf_cert.pem"
        root_path = "/app/keys/root_ca.pem"
        original_root = open(root_path, "rb").read()
        original_root_mode = stat.S_IMODE(os.stat(root_path).st_mode)

        try:
            os.chmod(leaf_path, 0o444)
            for validator in validators:
                run_validator(validator, valid_paths[0], 1)
        finally:
            os.chmod(leaf_path, 0o400)

        alternate_key = os.path.join(td, "alternate-root.key")
        alternate_cert = os.path.join(td, "alternate-root.pem")
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", alternate_key, "-out", alternate_cert, "-days", "30",
            "-subj", "/CN=VerifierAlternateRoot"
        ], check=True, capture_output=True)

        try:
            with open(alternate_cert, "rb") as src, open(root_path, "wb") as dst:
                dst.write(src.read())
            os.chmod(root_path, 0o400)
            for validator in validators:
                run_validator(validator, valid_paths[0], 1)
        finally:
            with open(root_path, "wb") as f:
                f.write(original_root)
            os.chmod(root_path, original_root_mode)

        for validator in validators:
            run_validator(validator, valid_paths[0], 0)


def stop_services():
    subprocess.run(["pkill", "-f", "/app/backend/server.py"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/issuer/server.py"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["service", "nginx", "stop"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def request(path, token=None):
    req = urllib.request.Request(f"http://127.0.0.1:8080{path}")
    if token is not None:
        req.add_header("Token", token)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode(), response.read().decode().strip()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode().strip()


def wait_for_services():
    last_error = None
    for _ in range(50):
        try:
            status, body = request("/auth")
            if status == 200 and body:
                return body
        except Exception as e:
            last_error = e
        time.sleep(0.2)
    pytest.fail(f"Services did not become ready: {last_error}")


def test_end_to_end_flow_and_backend_validator_invocation():
    stop_services()
    service_process = subprocess.Popen(
        ["bash", "/app/start_services.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    validator = "/app/validator"
    backup = "/app/validator.verifier-backup"
    marker = "verifier-" + secrets.token_hex(24)
    log_path = "/tmp/validator-invocation-" + secrets.token_hex(12)

    try:
        issued_token = wait_for_services()
        status, data = request("/api/data", issued_token)
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert data == "SECURE_DATA_ACCESSED", f"Expected 'SECURE_DATA_ACCESSED', got '{data}'"

        os.replace(validator, backup)
        with open(validator, "w") as f:
            f.write(f"#!/bin/sh\ncat \"$1\" > {log_path}\nexit 0\n")
        os.chmod(validator, 0o755)

        status, data = request("/api/data", marker)
        assert status == 200 and data == "SECURE_DATA_ACCESSED", "Backend did not honor a successful validator exit code."
        assert os.path.exists(log_path), "Backend did not invoke /app/validator."
        assert open(log_path).read() == marker, "Backend did not pass the received token file to the validator."

        with open(validator, "w") as f:
            f.write(f"#!/bin/sh\necho invoked > {log_path}\nexit 1\n")
        os.chmod(validator, 0o755)
        status, _ = request("/api/data", issued_token)
        assert status != 200, "Backend granted access despite a rejecting validator exit code."
    finally:
        if os.path.exists(backup):
            if os.path.exists(validator):
                os.remove(validator)
            os.replace(backup, validator)
        service_process.terminate()
        try:
            service_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            service_process.kill()
        stop_services()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
