#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import shutil
import subprocess
import tempfile

import jwt
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

SCRIPT = "/home/user/check_binary.py"
TARGET = "/home/user/target_binary.elf"
RESULT = "/home/user/result.json"


def extract_section(binary, section, output):
    subprocess.run(
        ["objcopy", "-O", "binary", f"--only-section={section}", binary, output],
        check=True,
        capture_output=True,
    )


def inspect_reference(tmpdir):
    chain_path = os.path.join(tmpdir, "chain.pem")
    token_path = os.path.join(tmpdir, "token.txt")
    extract_section(TARGET, ".cert_chain", chain_path)
    extract_section(TARGET, ".auth_token", token_path)

    chain_data = open(chain_path, "rb").read()
    blocks = re.findall(
        rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        chain_data,
        flags=re.DOTALL,
    )
    assert len(blocks) == 2, "The supplied test ELF must contain exactly two certificates."
    leaf = x509.load_pem_x509_certificate(blocks[0])
    root = x509.load_pem_x509_certificate(blocks[1])

    root.public_key().verify(
        root.signature,
        root.tbs_certificate_bytes,
        padding.PKCS1v15(),
        root.signature_hash_algorithm,
    )
    root.public_key().verify(
        leaf.signature,
        leaf.tbs_certificate_bytes,
        padding.PKCS1v15(),
        leaf.signature_hash_algorithm,
    )

    token = open(token_path, "r", encoding="utf-8").read().strip()
    payload = jwt.decode(token, leaf.public_key(), algorithms=["RS256"])
    assert isinstance(payload.get("sub"), str)
    return leaf, root, token, payload["sub"]


def replace_section(source, destination, section, contents_path):
    subprocess.run(
        ["objcopy", f"--update-section", f"{section}={contents_path}", source, destination],
        check=True,
        capture_output=True,
    )


def run_submission(binary):
    if os.path.lexists(RESULT):
        if os.path.isdir(RESULT) and not os.path.islink(RESULT):
            shutil.rmtree(RESULT)
        else:
            os.unlink(RESULT)

    completed = subprocess.run(
        ["python3", SCRIPT, binary],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"check_binary.py exited with {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.exists(RESULT), f"The output file {RESULT} is missing."
    assert os.path.isfile(RESULT), f"{RESULT} is not a regular file."
    try:
        with open(RESULT, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{RESULT} does not contain valid JSON: {exc}")
    assert set(data) == {"elf_valid", "chain_valid", "jwt_valid", "jwt_subject"}, (
        "result.json does not have the precise required schema."
    )
    return data


def test_submission_executes_and_performs_cryptographic_checks():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."

    with tempfile.TemporaryDirectory(prefix="binary-policy-") as tmpdir:
        leaf, root, token, expected_sub = inspect_reference(tmpdir)

        # Preserve the original valid-artifact assertions, but obtain the result
        # by actually executing the submitted program.
        data = run_submission(TARGET)
        assert data.get("elf_valid") is True, "elf_valid is not true for the valid ELF."
        assert data.get("chain_valid") is True, "chain_valid is not true for the valid chain."
        assert data.get("jwt_valid") is True, "jwt_valid is not true for the valid JWT."
        assert data.get("jwt_subject") == expected_sub, (
            f"jwt_subject is incorrect. Expected {expected_sub!r}, got {data.get('jwt_subject')!r}."
        )

        # Corrupt only the JWT signature. Its unverified payload and subject are
        # unchanged, so this distinguishes signature verification from decoding.
        header, payload, signature = token.split(".")
        raw_signature = bytearray(base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4)))
        raw_signature[len(raw_signature) // 2] ^= 1
        bad_signature = base64.urlsafe_b64encode(bytes(raw_signature)).rstrip(b"=").decode("ascii")
        bad_token_path = os.path.join(tmpdir, "bad-token.txt")
        with open(bad_token_path, "w", encoding="utf-8") as handle:
            handle.write(f"{header}.{payload}.{bad_signature}")
        bad_token_elf = os.path.join(tmpdir, "bad-token.elf")
        replace_section(TARGET, bad_token_elf, ".auth_token", bad_token_path)

        data = run_submission(bad_token_elf)
        assert data.get("elf_valid") is True
        assert data.get("chain_valid") is True
        assert data.get("jwt_valid") is False, "A JWT with a corrupted signature was accepted."
        assert data.get("jwt_subject") is None, "Subject must be null when JWT verification fails."

        # Corrupt the leaf certificate's signature while retaining its public key
        # and a parseable two-certificate PEM chain.
        leaf_der = bytearray(leaf.public_bytes(serialization.Encoding.DER))
        leaf_der[-1] ^= 1
        bad_leaf = x509.load_der_x509_certificate(bytes(leaf_der))
        with pytest.raises(Exception):
            root.public_key().verify(
                bad_leaf.signature,
                bad_leaf.tbs_certificate_bytes,
                padding.PKCS1v15(),
                bad_leaf.signature_hash_algorithm,
            )
        bad_chain_path = os.path.join(tmpdir, "bad-chain.pem")
        with open(bad_chain_path, "wb") as handle:
            handle.write(bad_leaf.public_bytes(serialization.Encoding.PEM))
            handle.write(root.public_bytes(serialization.Encoding.PEM))
        bad_chain_elf = os.path.join(tmpdir, "bad-chain.elf")
        replace_section(TARGET, bad_chain_elf, ".cert_chain", bad_chain_path)

        data = run_submission(bad_chain_elf)
        assert data.get("elf_valid") is True
        assert data.get("chain_valid") is False, "A leaf with an invalid CA signature was accepted."
        assert data.get("jwt_subject") is None, "Subject must be null when chain validation fails."

        # A non-ELF input must not be reported as a valid binary.
        non_elf = os.path.join(tmpdir, "not-an-elf.bin")
        with open(non_elf, "wb") as handle:
            handle.write(os.urandom(97))
        data = run_submission(non_elf)
        assert data.get("elf_valid") is False, "A non-ELF file was accepted as a valid ELF."
        assert data.get("jwt_subject") is None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
