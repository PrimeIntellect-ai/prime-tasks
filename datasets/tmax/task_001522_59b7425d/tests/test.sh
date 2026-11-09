#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import shutil
import stat
import zipfile

import pytesseract
import pytest
import requests
from PIL import Image

VAULT = "/home/user/backup_vault"
URL = "http://127.0.0.1:9000/upload"


def read_policy_prefix():
    text = pytesseract.image_to_string(Image.open("/app/backup_policy.png"), config="--psm 6")
    match = re.search(r"POLICY_ID\s*:\s*(\S+)", text)
    assert match, f"Could not OCR POLICY_ID from policy image; OCR output was {text!r}"
    return match.group(1)


def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def reset_vault():
    remove_path(VAULT)


def upload(entries, filename):
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w") as zf:
        for name, content in entries:
            zf.writestr(name, content)
    zip_buffer.seek(0)
    try:
        return requests.post(
            URL,
            files={"archive": (filename, zip_buffer, "application/zip")},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to or receive response from the server at {URL}: {exc}")


def test_original_archive_and_assertions():
    reset_vault()
    remove_path("/home/user/evil.sh")
    remove_path("/home/home/user/evil.sh")

    upload([
        ("docs/readme.txt", b"Hello World"),
        ("docs/copy.txt", b"Hello World"),
        ("images/logo.png", b"Fake PNG bytes"),
        ("../../home/user/evil.sh", b"echo Pwned"),
    ], "test.zip")

    evil_path = "/home/user/evil.sh"
    assert not os.path.exists(evil_path), f"Zip slip prevention failed: {evil_path} should not exist."
    assert not os.path.exists("/home/home/user/evil.sh"), "Zip slip traversal entry was extracted outside the vault."

    readme_path = "/home/user/backup_vault/docs/VAULTX_readme.txt"
    copy_path = "/home/user/backup_vault/docs/VAULTX_copy.txt"
    logo_path = "/home/user/backup_vault/images/VAULTX_logo.png"

    assert os.path.isfile(readme_path), f"Expected extracted file not found: {readme_path}"
    with open(readme_path, "r") as f:
        assert f.read() == "Hello World", f"Content mismatch in {readme_path}"

    assert os.path.isfile(copy_path), f"Expected extracted file not found: {copy_path}"
    with open(copy_path, "r") as f:
        assert f.read() == "Hello World", f"Content mismatch in {copy_path}"

    assert os.path.isfile(logo_path), f"Expected extracted file not found: {logo_path}"
    with open(logo_path, "r") as f:
        assert f.read() == "Fake PNG bytes", f"Content mismatch in {logo_path}"

    stat_readme = os.stat(readme_path)
    stat_copy = os.stat(copy_path)
    assert stat_readme.st_ino == stat_copy.st_ino, "Deduplication failed: copy.txt is not a hard link to readme.txt (inodes differ)."


def run_random_archive_case(prefix, case_number):
    reset_vault()
    token = secrets.token_hex(8)
    duplicate_content = secrets.token_bytes(73)
    unique_one = secrets.token_bytes(91)
    unique_two = secrets.token_bytes(117)

    source_files = [
        (f"reports_{token}/daily_{token}.txt", duplicate_content),
        (f"reports_{token}/copies/mirror_{token}.dat", duplicate_content),
        (f"other_{token}/third_{token}.bin", duplicate_content),
        (f"deep_{token}/level/multi.part.{token}.log", unique_one),
        (f"root_{token}", unique_two),
    ]

    outside_home = f"zip_slip_home_{token}"
    outside_tmp = f"zip_slip_tmp_{token}"
    absolute_tmp = f"zip_slip_abs_{token}"
    forbidden_paths = [
        f"/home/user/{outside_home}",
        f"/tmp/{outside_tmp}",
        f"/tmp/{absolute_tmp}",
    ]
    for path in forbidden_paths:
        remove_path(path)

    malicious = [
        (f"../{outside_home}", secrets.token_bytes(31)),
        (f"../../../tmp/{outside_tmp}", secrets.token_bytes(37)),
        (f"/tmp/{absolute_tmp}", secrets.token_bytes(41)),
    ]
    upload(source_files + malicious, f"random-{case_number}-{token}.zip")

    for path in forbidden_paths:
        assert not os.path.lexists(path), f"Zip Slip prevention failed; archive created {path}"

    expected = {}
    duplicate_outputs = []
    for archived_name, content in source_files:
        directory, basename = os.path.split(archived_name)
        relative_output = os.path.join(directory, prefix + basename)
        expected[relative_output] = content
        if content == duplicate_content:
            duplicate_outputs.append(os.path.join(VAULT, relative_output))

    assert os.path.isdir(VAULT), "The backup vault was not created"
    actual_files = set()
    for root, dirs, files in os.walk(VAULT, followlinks=False):
        for name in files:
            actual_files.add(os.path.relpath(os.path.join(root, name), VAULT))

    assert actual_files == set(expected), (
        f"Unexpected extracted file set. Expected {set(expected)!r}, got {actual_files!r}"
    )

    for relative_path, expected_content in expected.items():
        output_path = os.path.join(VAULT, relative_path)
        assert os.path.isfile(output_path), f"Expected extracted file not found: {output_path}"
        assert not os.path.islink(output_path), f"Extracted file must not be a symbolic link: {output_path}"
        with open(output_path, "rb") as f:
            assert f.read() == expected_content, f"Content mismatch in {output_path}"

    duplicate_stats = [os.stat(path) for path in duplicate_outputs]
    assert all(stat.S_ISREG(item.st_mode) for item in duplicate_stats)
    assert len({(item.st_dev, item.st_ino) for item in duplicate_stats}) == 1, (
        "Files with identical randomized contents were not deduplicated using hard links"
    )

    unique_paths = [
        os.path.join(VAULT, rel)
        for rel, content in expected.items()
        if content != duplicate_content
    ]
    duplicate_inode = (duplicate_stats[0].st_dev, duplicate_stats[0].st_ino)
    assert all((os.stat(path).st_dev, os.stat(path).st_ino) != duplicate_inode for path in unique_paths), (
        "Files with different contents incorrectly share the duplicate inode"
    )


def test_randomized_archives_are_actually_processed():
    prefix = read_policy_prefix()
    for case_number in range(2):
        run_random_archive_case(prefix, case_number)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
