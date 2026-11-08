#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess

HOME_DIR = "/home/user"


def test_recovered_key():
    token_path = os.path.join(HOME_DIR, "legacy_token.bin")
    recovered_key_path = os.path.join(HOME_DIR, "recovered_key.txt")

    assert os.path.isfile(token_path), f"Legacy token file missing at {token_path}"
    assert os.path.isfile(recovered_key_path), f"Recovered key file missing at {recovered_key_path}"

    # Derive the expected key dynamically
    known_plaintext = b'{"user":"admin","action":"rotate"}'
    with open(token_path, "rb") as f:
        ciphertext = f.read()

    assert len(ciphertext) >= 4, "Ciphertext is too short"

    # XOR first 4 bytes to find the key
    expected_key_bytes = bytes([ciphertext[i] ^ known_plaintext[i] for i in range(4)])
    expected_key_hex = expected_key_bytes.hex().lower()

    with open(recovered_key_path, "r") as f:
        actual_key_hex = f.read().strip().lower()

    assert actual_key_hex == expected_key_hex, f"Recovered key is incorrect. Expected {expected_key_hex}, got {actual_key_hex}"


def test_privilege_escalation_audit():
    vuln_file_path = os.path.join(HOME_DIR, "vuln_file.txt")
    script_path = os.path.join(HOME_DIR, "rotation_scripts", "rotate_keys.py")

    assert os.path.isfile(vuln_file_path), f"Vulnerable file record missing at {vuln_file_path}"

    with open(vuln_file_path, "r") as f:
        vuln_filename = f.read().strip()

    assert vuln_filename == "rotate_keys.py", f"Incorrect vulnerable file identified: {vuln_filename}"
    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    mode = os.stat(script_path).st_mode
    is_world_writable = bool(mode & stat.S_IWOTH)
    assert not is_world_writable, f"File {script_path} is still world-writable"
    assert stat.S_IMODE(mode) == 0o755, f"Permissions on {script_path} should be exactly 755, but got {oct(stat.S_IMODE(mode))}"


def test_certificate_validation():
    script_path = os.path.join(HOME_DIR, "check_certs.py")
    chain_status_path = os.path.join(HOME_DIR, "chain_status.txt")
    cert_dir = os.path.join(HOME_DIR, "certs")
    ca_path = os.path.join(cert_dir, "ca.crt")
    intermediate_path = os.path.join(cert_dir, "intermediate.crt")
    server_path = os.path.join(cert_dir, "server.crt")

    assert os.path.isfile(script_path), f"Certificate validation script missing at {script_path}"
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"Certificate validation script is not a regular file: {script_path}"
    for cert_path in (ca_path, intermediate_path, server_path):
        assert os.path.isfile(cert_path), f"Certificate missing at {cert_path}"

    # Exercise the submitted validator against a deliberately broken chain.
    # Substituting the leaf for the intermediate preserves valid PEM input but
    # makes the required server -> intermediate -> root chain invalid.
    with open(ca_path, "rb") as f:
        original_ca = f.read()
    with open(intermediate_path, "rb") as f:
        original_intermediate = f.read()
    with open(server_path, "rb") as f:
        original_server = f.read()

    try:
        with open(intermediate_path, "wb") as f:
            f.write(original_server)
        if os.path.lexists(chain_status_path):
            os.remove(chain_status_path)
        subprocess.run(
            ["python3", script_path],
            cwd=HOME_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        if os.path.isfile(chain_status_path):
            with open(chain_status_path, "r") as f:
                invalid_status = f.read().strip()
            assert invalid_status != "CHAIN_OK", "Validator reported CHAIN_OK for an invalid certificate chain"
    finally:
        with open(ca_path, "wb") as f:
            f.write(original_ca)
        with open(intermediate_path, "wb") as f:
            f.write(original_intermediate)
        with open(server_path, "wb") as f:
            f.write(original_server)

    # Run the submitted script on the real chain and require it to produce the
    # requested status from a clean state.
    if os.path.lexists(chain_status_path):
        os.remove(chain_status_path)
    subprocess.run(
        ["python3", script_path],
        cwd=HOME_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )

    assert os.path.isfile(chain_status_path), f"Chain status file missing at {chain_status_path}"
    with open(chain_status_path, "r") as f:
        status = f.read().strip()
    assert status == "CHAIN_OK", f"Incorrect chain status: {status}. Expected 'CHAIN_OK'"

    # Independently confirm that the certificates currently form the required
    # chain rather than trusting the script's self-reported result.
    verification = subprocess.run(
        ["openssl", "verify", "-CAfile", ca_path, "-untrusted", intermediate_path, server_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert verification.returncode == 0, (
        "Independent certificate-chain verification failed: "
        + verification.stdout
        + verification.stderr
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
