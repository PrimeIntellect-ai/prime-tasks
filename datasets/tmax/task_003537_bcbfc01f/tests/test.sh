#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import shutil
import subprocess
import tempfile

HOME = "/home/user"
CPP_PATH = os.path.join(HOME, "evader.cpp")
BIN_PATH = os.path.join(HOME, "evader")
CA_PATH = os.path.join(HOME, "ca.crt")
SERVER_PATH = os.path.join(HOME, "server.crt")
PAYLOAD_PATH = os.path.join(HOME, "payload.enc")
DECODED_PATH = os.path.join(HOME, "decoded.bin")
EXPECTED = b"RED_TEAM_STRIKES_AGAIN_WITH_C++!"
EXPECTED_HASH = "9bd7ed16ce3496030c6aeb8ea1701386ab7143e1fb86c7d1e847c21f7e076df3"


def test_decoded_bin_exists_and_correct():
    """Verify that decoded.bin exists and contains the correct decrypted payload."""
    assert os.path.isfile(DECODED_PATH), f"File {DECODED_PATH} is missing. The payload was not dropped."
    with open(DECODED_PATH, "r", encoding="utf-8") as f:
        contents = f.read()
    expected_contents = "RED_TEAM_STRIKES_AGAIN_WITH_C++!"
    assert contents == expected_contents, f"Contents of {DECODED_PATH} are incorrect. Got {contents!r}, expected {expected_contents!r}."


def test_evader_cpp_exists_and_uses_openssl():
    """Verify that evader.cpp exists and uses the OpenSSL certificate verification API."""
    assert os.path.isfile(CPP_PATH), f"Source file {CPP_PATH} is missing."
    with open(CPP_PATH, "r", encoding="utf-8", errors="ignore") as f:
        code = f.read()
    assert "X509_verify_cert" in code, f"Source file {CPP_PATH} does not appear to use X509_verify_cert."


def test_evader_binary_exists():
    """Verify that the compiled evader binary exists and is executable."""
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} is missing."
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BIN_PATH} is not a compiled ELF executable."


def _openssl(*args):
    subprocess.run(
        ["openssl", *args],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _make_valid_chain(directory):
    ca_key = os.path.join(directory, "ca.key")
    ca_crt = os.path.join(directory, "ca.crt")
    server_key = os.path.join(directory, "server.key")
    server_csr = os.path.join(directory, "server.csr")
    server_crt = os.path.join(directory, "server.crt")
    serial = os.path.join(directory, "ca.srl")

    _openssl("req", "-x509", "-sha256", "-days", "30", "-nodes",
             "-newkey", "rsa:2048", "-subj", "/CN=VerifierTestCA",
             "-keyout", ca_key, "-out", ca_crt)
    _openssl("req", "-new", "-newkey", "rsa:2048", "-nodes",
             "-keyout", server_key, "-out", server_csr,
             "-subj", "/CN=VerifierTestServer")
    _openssl("x509", "-req", "-in", server_csr, "-CA", ca_crt,
             "-CAkey", ca_key, "-CAserial", serial, "-CAcreateserial",
             "-out", server_crt, "-days", "30", "-sha256")
    return open(ca_crt, "rb").read(), open(server_crt, "rb").read()


def _run(path, timeout=6):
    return subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, check=False
    )


def _remove_decoded():
    try:
        os.unlink(DECODED_PATH)
    except FileNotFoundError:
        pass


def _assert_no_drop():
    assert not os.path.exists(DECODED_PATH), "Payload was dropped despite a required failure."


def test_source_and_submitted_binary_behavior():
    original_ca = open(CA_PATH, "rb").read()
    original_server = open(SERVER_PATH, "rb").read()
    original_payload = open(PAYLOAD_PATH, "rb").read()

    decoded_expected = bytes(b ^ 0x42 for b in base64.b64decode(original_payload, validate=True))
    assert decoded_expected == EXPECTED
    assert hashlib.sha256(decoded_expected).hexdigest() == EXPECTED_HASH

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "evader-from-source")
        compile_result = subprocess.run(
            ["g++", CPP_PATH, "-o", rebuilt, "-lssl", "-lcrypto"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=30, check=False
        )
        assert compile_result.returncode == 0, "evader.cpp did not compile:\n" + compile_result.stderr

        alternate_ca, alternate_server = _make_valid_chain(td)

        try:
            for executable in (BIN_PATH, rebuilt):
                # A different but valid CA/server chain must be verified through X509,
                # not accepted or rejected using hard-coded certificate bytes.
                open(CA_PATH, "wb").write(alternate_ca)
                open(SERVER_PATH, "wb").write(alternate_server)
                open(PAYLOAD_PATH, "wb").write(original_payload)
                _remove_decoded()
                result = _run(executable)
                assert result.returncode == 0, (
                    f"{executable} rejected a valid certificate chain or valid payload; "
                    f"exit={result.returncode}, stderr={result.stderr!r}"
                )
                assert os.path.isfile(DECODED_PATH)
                assert open(DECODED_PATH, "rb").read() == decoded_expected

                # With an invalid chain, payload.enc is a FIFO with no writer. Correct
                # ordering exits for certificate failure without ever opening/reading it.
                open(CA_PATH, "wb").write(alternate_ca)
                open(SERVER_PATH, "wb").write(original_server)
                os.unlink(PAYLOAD_PATH)
                os.mkfifo(PAYLOAD_PATH, 0o666)
                _remove_decoded()
                try:
                    result = _run(executable, timeout=4)
                except subprocess.TimeoutExpired:
                    raise AssertionError(
                        f"{executable} accessed payload.enc before rejecting the invalid certificate chain"
                    )
                finally:
                    if os.path.exists(PAYLOAD_PATH):
                        os.unlink(PAYLOAD_PATH)
                    open(PAYLOAD_PATH, "wb").write(original_payload)
                assert result.returncode == 1, (
                    f"Certificate verification failure must exit 1, got {result.returncode}"
                )
                _assert_no_drop()

                # A valid chain with a freshly generated, correctly Base64/XOR-encoded
                # payload whose SHA-256 is wrong must exit 2 and must not drop a file.
                bad_plaintext = os.urandom(73)
                while hashlib.sha256(bad_plaintext).hexdigest() == EXPECTED_HASH:
                    bad_plaintext = os.urandom(73)
                bad_encoded = base64.b64encode(bytes(b ^ 0x42 for b in bad_plaintext))
                open(CA_PATH, "wb").write(alternate_ca)
                open(SERVER_PATH, "wb").write(alternate_server)
                open(PAYLOAD_PATH, "wb").write(bad_encoded)
                _remove_decoded()
                result = _run(executable)
                assert result.returncode == 2, (
                    f"Checksum mismatch must exit 2, got {result.returncode}; stderr={result.stderr!r}"
                )
                _assert_no_drop()
        finally:
            if os.path.exists(PAYLOAD_PATH):
                os.unlink(PAYLOAD_PATH)
            open(CA_PATH, "wb").write(original_ca)
            open(SERVER_PATH, "wb").write(original_server)
            open(PAYLOAD_PATH, "wb").write(original_payload)

    # Execute the submitted artifact in the original environment and leave the
    # requested final dropped payload in place.
    _remove_decoded()
    result = _run(BIN_PATH)
    assert result.returncode == 0, f"Submitted evader failed in the target environment: {result.stderr!r}"
    assert os.path.isfile(DECODED_PATH)
    assert open(DECODED_PATH, "rb").read() == EXPECTED
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
