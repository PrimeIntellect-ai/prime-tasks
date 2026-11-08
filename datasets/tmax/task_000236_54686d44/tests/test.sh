#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import string
import subprocess
import tempfile
import time
import zipfile
from functools import lru_cache
from pathlib import Path, PurePosixPath

OLD_KEY = "compromised_master_key_992!"


def _normalise_archive(entries):
    normalised = {}
    names = []
    for raw_name, data in entries.items():
        name = raw_name.replace("\\", "/")
        while name.startswith("./"):
            name = name[2:]
        path = PurePosixPath(name)
        assert not path.is_absolute() and ".." not in path.parts, f"Unsafe ZIP member: {raw_name}"
        if name and not name.endswith("/"):
            names.append((name, data))

    if names and all(name.startswith("vault/") for name, _ in names):
        names = [(name[len("vault/"):], data) for name, data in names]

    for name, data in names:
        assert name not in normalised, f"Duplicate ZIP member: {name}"
        normalised[name] = data
    return normalised


def _read_zip(path):
    with zipfile.ZipFile(path, "r") as archive:
        bad = archive.testzip()
        assert bad is None, f"Corrupt ZIP member: {bad}"
        entries = {info.filename: archive.read(info) for info in archive.infolist() if not info.is_dir()}
    return _normalise_archive(entries)


@lru_cache(maxsize=1)
def _original_entries():
    encrypted = Path("/home/user/vault.enc")
    assert encrypted.is_file(), "Missing original encrypted vault"
    output = Path("/tmp/verifier_original_vault.zip")
    result = subprocess.run([
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-in", str(encrypted), "-out", str(output), "-pass", f"pass:{OLD_KEY}"
    ], capture_output=True)
    assert result.returncode == 0, f"Original vault is not decryptable with the recovered incident key: {result.stderr.decode(errors='replace')}"
    entries = _read_zip(output)
    assert "payload.elf" in entries, "Original vault does not contain payload.elf"
    assert entries["payload.elf"].startswith(b"\x7fELF"), "Original payload.elf is not an ELF binary"
    return entries


def _payload_signature():
    payload = _original_entries()["payload.elf"]
    marker = b"\xde\xad\xbe\xef"
    positions = [i for i in range(len(payload)) if payload.startswith(marker, i)]
    assert len(positions) == 1, "Expected one unique DE AD BE EF signature marker in the original payload"
    start = positions[0]
    signature = payload[start:start + 12]
    assert len(signature) == 12, "The payload signature is truncated"
    return signature


def test_vault_extracted():
    """Verify that the original vault was decrypted and extracted."""
    payload_path = Path("/home/user/vault/payload.elf")
    assert payload_path.exists(), f"Missing extracted payload: {payload_path}. Did you extract the vault to /home/user/vault/?"
    assert payload_path.is_file(), f"Expected {payload_path} to be a file."
    assert stat.S_ISREG(payload_path.lstat().st_mode), f"Expected {payload_path} to be a regular file."

    expected = _original_entries()
    vault_dir = Path("/home/user/vault")
    for relative_name, expected_data in expected.items():
        extracted = vault_dir / relative_name
        assert extracted.exists(), f"Missing extracted vault member: {relative_name}"
        assert extracted.is_file() and stat.S_ISREG(extracted.lstat().st_mode), f"Extracted member is not a regular file: {relative_name}"
        assert extracted.read_bytes() == expected_data, f"Extracted member does not match the original vault: {relative_name}"


def test_new_key_created_and_permissions():
    """Verify the new key file exists, is 32-char alphanumeric, and has 0400 permissions."""
    key_path = Path("/home/user/new_key.txt")
    assert key_path.exists(), f"Missing new key file: {key_path}"

    with open(key_path, "r") as f:
        key = f.read().strip()

    assert len(key) == 32, f"New key length must be exactly 32 characters, got {len(key)}"
    assert all(c in string.ascii_letters + string.digits for c in key), "New key must be strictly alphanumeric."

    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions of {key_path} must be exactly 0400, got {oct(perms)}"


def test_vault_reencrypted():
    """Verify the vault was re-encrypted with the new key and correct parameters."""
    new_vault_enc = Path("/home/user/vault_new.enc")
    key_path = Path("/home/user/new_key.txt")
    assert new_vault_enc.exists(), f"Missing re-encrypted vault: {new_vault_enc}"

    with open(key_path, "r") as f:
        key = f.read().strip()

    decrypted_zip = "/tmp/test_decrypted.zip"
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-in", str(new_vault_enc),
        "-out", decrypted_zip,
        "-pass", f"pass:{key}"
    ]
    res = subprocess.run(cmd, capture_output=True)
    assert res.returncode == 0, f"Failed to decrypt vault_new.enc with the new key. stderr: {res.stderr.decode()}"
    assert os.path.exists(decrypted_zip), "Decrypted archive was not created."

    actual = _read_zip(decrypted_zip)
    expected = _original_entries()
    for name, expected_data in expected.items():
        assert name in actual, f"Re-encrypted ZIP is missing original vault member: {name}"
        assert actual[name] == expected_data, f"Re-encrypted ZIP member differs from the original vault: {name}"


def test_ids_scanner_performance_and_correctness():
    """Verify the IDS scanner correctly identifies the signature and meets the performance threshold."""
    scanner_path = Path("/home/user/ids_scanner.py")
    input_log = Path("/app/test_logs.txt")
    output_log = Path("/tmp/detected.log")

    assert scanner_path.exists(), f"Missing scanner script: {scanner_path}"
    assert scanner_path.is_file() and stat.S_ISREG(scanner_path.lstat().st_mode), "Scanner must be a regular file"
    assert input_log.exists(), f"Missing input test logs: {input_log}"

    start = time.time()
    res = subprocess.run(["python3", str(scanner_path), str(input_log), str(output_log)], capture_output=True)
    duration = time.time() - start

    assert res.returncode == 0, f"Scanner failed to run. stderr: {res.stderr.decode()}"
    assert output_log.exists(), "Scanner did not create the output log file."

    sig = _payload_signature().hex()
    expected_lines = []
    with open(input_log, "r") as f:
        for line in f:
            if sig in line.replace(" ", "").lower():
                expected_lines.append(line)

    with open(output_log, "r") as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Scanner output has {len(actual_lines)} lines, expected {len(expected_lines)}."
    assert actual_lines == expected_lines, "Output log lines do not match the expected lines containing the signature."

    threshold = 0.75
    assert duration <= threshold, f"Execution time {duration:.3f}s exceeded threshold of {threshold}s"


def test_ids_scanner_on_fresh_logs():
    """Exercise the scanner on verifier-generated logs with varied spacing and case."""
    scanner_path = Path("/home/user/ids_scanner.py")
    signature = _payload_signature()
    rng = random.SystemRandom()

    def render(data, spaced=False, mixed_case=False):
        pieces = []
        for byte in data:
            token = f"{byte:02x}"
            if mixed_case and rng.randrange(2):
                token = token.upper()
            pieces.append(token)
        if spaced:
            return " ".join(pieces)
        return "".join(pieces)

    lines = []
    for i in range(320):
        data = bytearray(os.urandom(72))
        if i < 31:
            offset = rng.randrange(0, len(data) - len(signature) + 1)
            data[offset:offset + len(signature)] = signature
            line = render(data, spaced=(i % 3 != 0), mixed_case=(i % 2 == 0)) + "\n"
        elif i < 50:
            offset = rng.randrange(0, len(data) - len(signature) + 1)
            near_match = bytearray(signature)
            near_match[rng.randrange(len(near_match))] ^= 1
            data[offset:offset + len(signature)] = near_match
            line = render(data, spaced=(i % 2 == 0), mixed_case=True) + "\n"
        else:
            line = render(data, spaced=(i % 4 == 0), mixed_case=(i % 5 == 0)) + "\n"
        lines.append(line)
    rng.shuffle(lines)

    sig_hex = signature.hex().encode()
    input_bytes = "".join(lines).encode()
    expected = b"".join(
        line for line in input_bytes.splitlines(keepends=True)
        if sig_hex in line.replace(b" ", b"").lower()
    )
    assert expected, "Verifier failed to generate positive scanner cases"

    with tempfile.TemporaryDirectory(prefix="ids-heldout-") as directory:
        input_path = Path(directory) / "fresh_input.log"
        output_path = Path(directory) / "fresh_output.log"
        input_path.write_bytes(input_bytes)
        result = subprocess.run(
            ["python3", str(scanner_path), str(input_path), str(output_path)],
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Scanner failed on fresh logs: {result.stderr.decode(errors='replace')}"
        assert output_path.is_file(), "Scanner did not create output for fresh logs"
        assert output_path.read_bytes() == expected, "Scanner output is incorrect on fresh held-out logs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
