#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import struct
import subprocess
import tempfile
import pytest

ORACLE_BIN = "/opt/legacy/validator"
AGENT_BIN = "/home/user/new_validator"
CERTS_DIR = "/home/user/certs"
KEYSTORE = "/app/legacy_keystore.p12"
KEYSTORE_PASSWORD = "AlphaTangoNiner2023"


def certificate_der_from_bytes(data):
    result = subprocess.run(
        ["openssl", "x509", "-outform", "DER"],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def test_certs_extracted():
    """Verify that the certificates were extracted to the correct directory."""
    assert os.path.exists(CERTS_DIR), f"Directory {CERTS_DIR} does not exist."
    assert os.path.isdir(CERTS_DIR), f"{CERTS_DIR} is not a directory."
    files = os.listdir(CERTS_DIR)
    assert len(files) > 0, f"No certificates found in {CERTS_DIR}."

    extracted = subprocess.run(
        [
            "openssl", "pkcs12", "-in", KEYSTORE,
            "-clcerts", "-nokeys",
            "-passin", f"pass:{KEYSTORE_PASSWORD}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert extracted.returncode == 0, "Could not inspect the legacy keystore."
    expected_der = certificate_der_from_bytes(extracted.stdout)
    assert expected_der is not None, "The legacy keystore contained no readable certificate."
    expected_digest = hashlib.sha256(expected_der).digest()

    matching_certificate = False
    for name in files:
        path = os.path.join(CERTS_DIR, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as f:
                candidate_der = certificate_der_from_bytes(f.read())
        except OSError:
            continue
        if candidate_der is not None and hashlib.sha256(candidate_der).digest() == expected_digest:
            matching_certificate = True
            break

    assert matching_certificate, (
        f"No file in {CERTS_DIR} is the certificate from the legacy keystore."
    )


def test_agent_binary_exists():
    """Verify that the new validator binary exists and is executable."""
    assert os.path.exists(AGENT_BIN), f"Agent binary {AGENT_BIN} does not exist."
    assert os.path.isfile(AGENT_BIN), f"{AGENT_BIN} is not a file."
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."

    with open(ORACLE_BIN, "rb") as f:
        oracle_digest = hashlib.sha256(f.read()).digest()
    with open(AGENT_BIN, "rb") as f:
        agent_digest = hashlib.sha256(f.read()).digest()
    assert agent_digest != oracle_digest, "The replacement must not be a byte-identical copy of the oracle."


def generate_fuzz_input(rng):
    """Generate a random fuzz input based on the truth distribution."""
    length = rng.randint(10, 500)
    data = bytearray(rng.getrandbits(8) for _ in range(length))

    # 10% chance to include the magic bytes 'CERT'
    if rng.random() < 0.10:
        magic = b"CERT"
        for i in range(min(4, length)):
            data[i] = magic[i]

    return bytes(data)


def run_program(executable, input_path):
    """Run a program with the given input file and return its output and exit code."""
    try:
        result = subprocess.run(
            [executable, input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=1.0,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, b"", b"Timeout"
    except Exception as e:
        return -2, b"", str(e).encode()


def assert_equivalent(data, label, expected_oracle=None):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(data)
        tmp_path = tmp.name
    try:
        oracle = run_program(ORACLE_BIN, tmp_path)
        agent = run_program(AGENT_BIN, tmp_path)
        if expected_oracle is not None:
            assert oracle == expected_oracle, f"Oracle did not produce the expected result for {label}: {oracle!r}"
        assert agent == oracle, (
            f"Mismatch for {label}!\n"
            f"Input length: {len(data)} bytes\n"
            f"Input hex (first 64 bytes): {data[:64].hex()}\n"
            f"Oracle: exit={oracle[0]}, stdout={oracle[1]!r}, stderr={oracle[2]!r}\n"
            f"Agent:  exit={agent[0]}, stdout={agent[1]!r}, stderr={agent[2]!r}"
        )
    finally:
        os.remove(tmp_path)


def make_valid(payload, trailing=b""):
    return b"CERT" + struct.pack("<H", len(payload)) + payload + struct.pack("<I", sum(payload)) + trailing


def test_structured_equivalence():
    """Exercise valid chains and targeted malformed variants, not merely random invalid files."""
    payloads = [
        b"",
        b"\x00",
        b"\xff",
        bytes(range(256)),
        bytes((i * 73 + 19) & 0xff for i in range(500)),
        bytes((i * 29 + 7) & 0xff for i in range(4096)),
        bytes((i * 17 + 3) & 0xff for i in range(65535)),
    ]

    for i, payload in enumerate(payloads):
        assert_equivalent(make_valid(payload), f"valid payload {i}", (0, b"VALID\n", b""))

    assert_equivalent(
        make_valid(b"targeted payload", b"ignored trailing bytes\x00\xff"),
        "valid chain with trailing bytes",
        (0, b"VALID\n", b""),
    )

    malformed = [
        b"",
        b"C",
        b"CER",
        b"NOPE" + b"\x00" * 8,
        b"CERT",
        b"CERT\x01",
        b"CERT" + struct.pack("<H", 10) + b"short",
        make_valid(b"checksum mismatch")[:-4] + struct.pack("<I", 1),
        b"CERT" + struct.pack("<H", 0) + b"\x01\x00\x00",
    ]
    for i, data in enumerate(malformed):
        assert_equivalent(data, f"targeted malformed input {i}", (1, b"INVALID\n", b""))


def test_fuzz_equivalence():
    """Fuzz the agent's binary against the oracle to ensure identical behavior."""
    assert os.path.exists(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} missing."
    assert os.path.exists(AGENT_BIN), f"Agent binary {AGENT_BIN} missing."

    rng = random.Random(42)
    N = 10000

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp_path = tmp.name

    try:
        for i in range(N):
            fuzz_data = generate_fuzz_input(rng)

            with open(tmp_path, "wb") as f:
                f.write(fuzz_data)

            oracle_code, oracle_out, oracle_err = run_program(ORACLE_BIN, tmp_path)
            agent_code, agent_out, agent_err = run_program(AGENT_BIN, tmp_path)

            if oracle_code != agent_code or oracle_out != agent_out or oracle_err != agent_err:
                error_msg = (
                    f"Mismatch on fuzz iteration {i}!\n"
                    f"Input length: {len(fuzz_data)} bytes\n"
                    f"Input hex (first 32 bytes): {fuzz_data[:32].hex()}\n"
                    f"Oracle: exit={oracle_code}, stdout={oracle_out!r}, stderr={oracle_err!r}\n"
                    f"Agent:  exit={agent_code}, stdout={agent_out!r}, stderr={agent_err!r}"
                )
                pytest.fail(error_msg)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
