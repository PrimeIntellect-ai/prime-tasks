#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import subprocess
import tarfile
import tempfile

LEGITIMATE_KEYS = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGoXabc1234567890defghijklmnopqrstuvwxyz12345 admin@corp.local",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbCdEfGhIjKlMnOpQrStUvWxYz01234567890abcdef admin@corp.local",
]
ROGUE_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILmNopqrstuvwxyz0987654321abcdefghijklmnopqr attacker@evil.com"
EXPECTED_EVIDENCE = b"CONFIDENTIAL: Project X Source Code - TOP SECRET\n"


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_phase1_authorized_keys_cleaned():
    """Verify that only the original legitimate keys remain."""
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"File missing: {auth_keys_path}"

    lines = nonempty_lines(auth_keys_path)
    assert len(lines) == 2, f"Expected exactly 2 keys in {auth_keys_path}, found {len(lines)}"
    for line in lines:
        assert line.endswith("admin@corp.local"), f"Found a key not ending with admin@corp.local: {line}"
    assert lines == LEGITIMATE_KEYS, f"The legitimate authorized key lines were altered: {lines}"


def test_phase1_rogue_keys_saved():
    """Verify that the complete removed rogue key line was saved."""
    rogue_keys_path = "/home/user/rogue_keys.txt"
    assert os.path.isfile(rogue_keys_path), f"File missing: {rogue_keys_path}"

    lines = nonempty_lines(rogue_keys_path)
    assert len(lines) == 1, f"Expected exactly 1 key in {rogue_keys_path}, found {len(lines)}"
    assert lines[0].endswith("attacker@evil.com"), f"Expected attacker key in {rogue_keys_path}, got: {lines[0]}"
    assert lines[0] == ROGUE_KEY, f"Expected the complete removed rogue key line, got: {lines[0]}"


def test_phase2_rogue_suid_identified():
    """Verify that the rogue SUID binary path is correctly identified."""
    rogue_suid_path = "/home/user/rogue_suid.txt"
    assert os.path.isfile(rogue_suid_path), f"File missing: {rogue_suid_path}"

    with open(rogue_suid_path, "r") as f:
        content = f.read().strip()

    expected_path = "/home/user/system_backup/kworker"
    assert content == expected_path, f"Expected '{expected_path}' in {rogue_suid_path}, got '{content}'"


def test_phase3_encrypted_evidence_assembled_and_verified():
    """Verify exact alphabetical assembly, supplied checksum, and decryptability."""
    parts_dir = "/home/user/exfil_parts"
    encrypted_path = "/home/user/encrypted_evidence.bin"
    hash_path = "/home/user/exfil_hash.txt"

    assert os.path.isdir(parts_dir), f"Directory missing: {parts_dir}"
    assert os.path.isfile(encrypted_path), f"File missing: {encrypted_path}"
    assert os.path.isfile(hash_path), f"File missing: {hash_path}"

    part_paths = [
        os.path.join(parts_dir, name)
        for name in sorted(os.listdir(parts_dir))
        if os.path.isfile(os.path.join(parts_dir, name))
    ]
    assert part_paths, f"No evidence chunks found in {parts_dir}"

    expected_bytes = b"".join(open(path, "rb").read() for path in part_paths)
    with open(encrypted_path, "rb") as f:
        encrypted_bytes = f.read()
    assert encrypted_bytes == expected_bytes, "encrypted_evidence.bin is not the chunks concatenated in alphabetical order"

    with open(hash_path, "r") as f:
        hash_fields = f.read().split()
    assert len(hash_fields) == 1, f"Expected one SHA256 value in {hash_path}"
    supplied_hash = hash_fields[0].lower()
    actual_hash = hashlib.sha256(encrypted_bytes).hexdigest()
    assert actual_hash == supplied_hash, f"Encrypted evidence checksum mismatch: expected {supplied_hash}, got {actual_hash}"

    with open("/home/user/rogue_suid.txt", "r") as f:
        password = os.path.basename(f.read().strip())

    with tempfile.TemporaryDirectory() as tmpdir:
        decrypted_path = os.path.join(tmpdir, "evidence.tar.gz")
        result = subprocess.run(
            ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-in", encrypted_path,
             "-out", decrypted_path, "-pass", f"pass:{password}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"Encrypted evidence could not be decrypted: {result.stderr}"
        try:
            with tarfile.open(decrypted_path, "r:gz") as archive:
                member = archive.extractfile("project_x_intel.txt")
                assert member is not None, "project_x_intel.txt is absent from the decrypted archive"
                assert member.read() == EXPECTED_EVIDENCE, "Decrypted archive contains incorrect evidence"
        except (tarfile.TarError, KeyError) as exc:
            raise AssertionError(f"Decrypted output is not the required evidence archive: {exc}")


def test_phase3_recovered_data():
    """Verify that the evidence was correctly decrypted and extracted."""
    recovered_file_path = "/home/user/recovered_data/project_x_intel.txt"
    assert os.path.isfile(recovered_file_path), f"File missing: {recovered_file_path}"

    with open(recovered_file_path, "r") as f:
        content = f.read().strip()

    expected_content = "CONFIDENTIAL: Project X Source Code - TOP SECRET"
    assert content == expected_content, f"Recovered data content mismatch. Expected '{expected_content}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
