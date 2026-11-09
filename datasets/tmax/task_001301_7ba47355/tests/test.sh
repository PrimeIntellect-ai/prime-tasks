#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

SCRIPT_PATH = "/home/user/audit_filter.py"
VENDORED_PATH = "/app/PyJWT-2.6.0"
ALGORITHMS_PATH = "/app/PyJWT-2.6.0/jwt/algorithms.py"
CA_PATH = "/app/certs/ca.crt"
LEAF_CERT_PATH = "/app/certs/leaf.crt"
LEAF_KEY_PATH = "/app/certs/leaf.key"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(private_key, payload=None):
    if payload is None:
        payload = {"sub": str(uuid.uuid4()), "nonce": os.urandom(24).hex()}
    header = {"alg": "RS256", "typ": "JWT"}
    encoded_header = b64url(json.dumps(header, separators=(",", ":"), sort_keys=True).encode())
    encoded_payload = b64url(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    signing_input = (encoded_header + "." + encoded_payload).encode("ascii")
    signature = private_key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    return encoded_header + "." + encoded_payload + "." + b64url(signature)


def run_detector(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_audit_filter_script_exists():
    script_path = "/home/user/audit_filter.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_adversarial_corpus():
    script_path = "/home/user/audit_filter.py"
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = sorted([f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))])
    clean_files = sorted([f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))])

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        file_path = os.path.join(evil_dir, ef)
        result = subprocess.run(
            ["python3", script_path, file_path],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if result.returncode != 0 or output != "LEAK":
            evil_bypassed.append((ef, output, result.stderr))

    for cf in clean_files:
        file_path = os.path.join(clean_dir, cf)
        result = subprocess.run(
            ["python3", script_path, file_path],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            clean_modified.append((cf, output, result.stderr))

    error_messages = []
    if evil_bypassed:
        basenames = [item[0] for item in evil_bypassed]
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(basenames)}")

    if clean_modified:
        basenames = [item[0] for item in clean_modified]
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (failed to output CLEAN): {', '.join(basenames)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_randomized_neutral_path_inputs():
    with open(LEAF_KEY_PATH, "rb") as f:
        leaf_key = serialization.load_pem_private_key(f.read(), password=None)
    unrelated_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    valid_one = make_token(leaf_key)
    valid_two = make_token(leaf_key)
    invalid_one = make_token(unrelated_key)
    invalid_two = make_token(unrelated_key)

    cases = [
        (b"worker\0--credential\0" + valid_one.encode() + b"\0", "LEAK"),
        (b"worker\0--other\0x\0--credential\0" + valid_two.encode() + b"\0", "LEAK"),
        (b"worker\0--credential\0" + invalid_one.encode() + b"\0", "CLEAN"),
        (b"worker\0--credential\0" + invalid_two.encode() + b"\0", "CLEAN"),
        (b"worker\0--verbose\0", "CLEAN"),
        (b"worker\0--credential\0abc.def.ghi\0", "CLEAN"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="audit-inputs-") as directory:
        for contents, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".bin")
            with open(path, "wb") as f:
                f.write(contents)
            result = run_detector(path)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected, (
                f"Expected {expected} for randomized input; got {result.stdout!r}. "
                f"stderr={result.stderr!r}"
            )


def test_certificate_chain_is_required():
    with open(LEAF_KEY_PATH, "rb") as f:
        leaf_key = serialization.load_pem_private_key(f.read(), password=None)
    token = make_token(leaf_key)

    with tempfile.TemporaryDirectory(prefix="audit-chain-") as directory:
        input_path = os.path.join(directory, uuid.uuid4().hex)
        with open(input_path, "wb") as f:
            f.write(b"service\0--token\0" + token.encode() + b"\0")

        with open(CA_PATH, "rb") as f:
            original_ca = f.read()
        with open(LEAF_CERT_PATH, "rb") as f:
            untrusted_ca = f.read()

        try:
            with open(CA_PATH, "wb") as f:
                f.write(untrusted_ca)
            result = run_detector(input_path)
        finally:
            with open(CA_PATH, "wb") as f:
                f.write(original_ca)

        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "CLEAN", "A valid JWT was trusted despite an invalid certificate chain"


def test_vendored_library_is_used_and_rsa_verification_is_repaired():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script_source = f.read()
    assert VENDORED_PATH in script_source, "Detector does not explicitly select the vendored PyJWT package"
    assert re.search(r"(^|\n)\s*(import jwt|from jwt\s+import)", script_source), "Detector does not import PyJWT"

    with open(ALGORITHMS_PATH, "r", encoding="utf-8") as f:
        algorithms_source = f.read()
    assert "VENDORED_CORRUPTION" not in algorithms_source
    assert "public_key.verify(signature, msg, padding.PKCS1v15(), self.hash_alg())" in algorithms_source

    with open(LEAF_KEY_PATH, "rb") as f:
        leaf_key = serialization.load_pem_private_key(f.read(), password=None)
    valid_token = make_token(leaf_key)
    invalid_token = make_token(rsa.generate_private_key(public_exponent=65537, key_size=2048))

    helper = r'''
import sys
import jwt
with open(sys.argv[2], "rb") as f:
    key = f.read()
print(jwt.__file__)
jwt.decode(sys.argv[1], key, algorithms=["RS256"])
print("OK")
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = VENDORED_PATH

    valid = subprocess.run(
        ["python3", "-c", helper, valid_token, LEAF_CERT_PATH],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )
    assert valid.returncode == 0, valid.stderr
    assert VENDORED_PATH in valid.stdout
    assert valid.stdout.strip().endswith("OK")

    invalid = subprocess.run(
        ["python3", "-c", helper, invalid_token, LEAF_CERT_PATH],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )
    assert invalid.returncode != 0, "Vendored RS256 verification accepted a token signed by an unrelated key"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
