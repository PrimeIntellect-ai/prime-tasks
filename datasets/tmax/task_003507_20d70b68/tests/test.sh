#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import posixpath
import secrets
import subprocess
import tarfile

import pytest

ARCHIVE_PATH = "/home/user/docs_backup.tar.gz.enc"
SCRIPT_PATH = "/home/user/verify.sh"
PASSWORD_IMAGE = "/app/password.png"


def extract_password():
    result = subprocess.run(
        ["tesseract", PASSWORD_IMAGE, "stdout"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Could not OCR password image: {result.stderr}"
    password = result.stdout.strip()
    assert password, "OCR returned an empty password"
    return password


def decrypt_archive(path, password):
    with open(path, "rb") as source:
        result = subprocess.run(
            [
                "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
                "-pass", f"pass:{password}",
            ],
            stdin=source,
            capture_output=True,
            timeout=20,
        )
    assert result.returncode == 0, (
        "Archive did not decrypt with openssl enc -aes-256-cbc -pbkdf2 and "
        f"the OCR-derived password. STDERR: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def normalize_member(name):
    name = name.replace("\\", "/").lstrip("/")
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def test_archive_exists_and_size_metric():
    archive_path = ARCHIVE_PATH

    assert os.path.exists(archive_path), f"Archive not found at {archive_path}"
    assert os.path.isfile(archive_path), f"Expected {archive_path} to be a file"

    size = os.path.getsize(archive_path)

    assert size > 100, f"Archive size {size} bytes is too small (<= 100 bytes). Archive might be empty."
    assert size < 2048, f"Archive size metric {size} bytes is outside the threshold (< 2048 bytes). Symlink loop likely followed."


def test_archive_is_encrypted_gzip_tar_with_expected_contents():
    password = extract_password()
    encrypted = open(ARCHIVE_PATH, "rb").read()
    assert not encrypted.startswith(b"\x1f\x8b"), "Archive is a plaintext gzip rather than encrypted"
    assert b"Sample documentation text." not in encrypted
    assert b"More technical details." not in encrypted

    compressed = decrypt_archive(ARCHIVE_PATH, password)
    assert compressed.startswith(b"\x1f\x8b"), "Decrypted archive is not gzip-compressed"

    try:
        tar_bytes = gzip.decompress(compressed)
    except Exception as exc:
        pytest.fail(f"Decrypted stream is not an intact gzip stream: {exc}")

    try:
        with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as archive:
            members = archive.getmembers()
            normalized = [(normalize_member(member.name), member) for member in members]

            regular = [(name, member) for name, member in normalized if member.isfile()]
            links = [(name, member) for name, member in normalized if member.issym()]
            unsupported = [
                name for name, member in normalized
                if name and not (member.isfile() or member.isdir() or member.issym())
            ]
            assert not unsupported, f"Archive contains unsupported entry types: {unsupported}"

            intro_candidates = [(n, m) for n, m in regular if posixpath.basename(n) == "intro.md"]
            details_candidates = [(n, m) for n, m in regular if posixpath.basename(n) == "details.md"]
            shortcut_candidates = [(n, m) for n, m in links if posixpath.basename(n) == "shortcut"]

            assert len(intro_candidates) == 1, "Archive must contain exactly one intro.md regular file"
            assert len(details_candidates) == 1, "Archive must contain exactly one details.md regular file"
            assert len(shortcut_candidates) == 1, "Archive must contain shortcut exactly once as a symlink"

            intro_name, intro_member = intro_candidates[0]
            details_name, details_member = details_candidates[0]
            shortcut_name, shortcut_member = shortcut_candidates[0]
            root = posixpath.dirname(intro_name)
            assert root in ("", "docs", "home/user/docs"), f"Unexpected archive root: {root!r}"
            assert posixpath.dirname(details_name) == root
            assert posixpath.dirname(shortcut_name) == root

            expected_non_dirs = {
                posixpath.join(root, "intro.md") if root else "intro.md",
                posixpath.join(root, "details.md") if root else "details.md",
                posixpath.join(root, "shortcut") if root else "shortcut",
            }
            actual_non_dirs = {name for name, member in normalized if name and not member.isdir()}
            assert actual_non_dirs == expected_non_dirs, (
                f"Archive has missing or unexpected non-directory entries: {actual_non_dirs}"
            )

            allowed_dirs = set()
            current = root
            while current:
                allowed_dirs.add(current)
                current = posixpath.dirname(current)
            actual_dirs = {name for name, member in normalized if name and member.isdir()}
            assert actual_dirs <= allowed_dirs, f"Archive contains unexpected directories: {actual_dirs - allowed_dirs}"

            assert archive.extractfile(intro_member).read() == b"Sample documentation text.\n"
            assert archive.extractfile(details_member).read() == b"More technical details.\n"
            assert shortcut_member.linkname == "/home/user/docs", (
                f"shortcut has wrong symlink target: {shortcut_member.linkname!r}"
            )
    except (tarfile.TarError, EOFError) as exc:
        pytest.fail(f"Decrypted gzip payload is not an intact tar archive: {exc}")


def make_valid_encrypted_archive(path, password):
    token = secrets.token_hex(16)
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w:gz") as archive:
        payload = ("integrity-" + token).encode()
        info = tarfile.TarInfo(name=f"probe-{token}.txt")
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))

    result = subprocess.run(
        [
            "openssl", "enc", "-aes-256-cbc", "-pbkdf2",
            "-pass", f"pass:{password}", "-out", str(path),
        ],
        input=raw.getvalue(),
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def run_verify(*args):
    return subprocess.run(
        ["/bin/bash", SCRIPT_PATH, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_verify_script_exists_and_works():
    script_path = SCRIPT_PATH
    archive_path = ARCHIVE_PATH

    assert os.path.exists(script_path), f"Verification script not found at {script_path}"
    assert os.path.isfile(script_path), f"Expected {script_path} to be a file"

    # Run the verification script
    result = subprocess.run(["/bin/bash", script_path, archive_path], capture_output=True, text=True)

    assert result.returncode == 0, (
        f"verify.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}"
    )


def test_verify_script_validates_independent_inputs(tmp_path):
    password = extract_password()
    valid = tmp_path / f"valid-{secrets.token_hex(8)}.enc"
    make_valid_encrypted_archive(valid, password)

    accepted = run_verify(valid)
    assert accepted.returncode == 0, (
        "verify.sh rejected an independently generated intact encrypted tar.gz: "
        f"{accepted.stderr}"
    )

    malformed_plaintext = tmp_path / f"not-a-tar-{secrets.token_hex(8)}.enc"
    result = subprocess.run(
        [
            "openssl", "enc", "-aes-256-cbc", "-pbkdf2",
            "-pass", f"pass:{password}", "-out", str(malformed_plaintext),
        ],
        input=b"this decrypts correctly but is not a gzip tar archive",
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0
    assert run_verify(malformed_plaintext).returncode != 0, (
        "verify.sh accepted decrypted data that is not a gzip tar archive"
    )

    truncated = tmp_path / f"truncated-{secrets.token_hex(8)}.enc"
    valid_data = valid.read_bytes()
    truncated.write_bytes(valid_data[:-1])
    assert run_verify(truncated).returncode != 0, "verify.sh accepted a truncated encrypted archive"

    assert run_verify().returncode != 0, "verify.sh must reject zero arguments"
    assert run_verify(valid, valid).returncode != 0, "verify.sh must reject more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
