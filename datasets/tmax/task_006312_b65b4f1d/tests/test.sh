#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import stat
import shutil
import subprocess
import tempfile
import zipfile

def test_redirects_decoded():
    file_path = "/home/user/redirects_decoded.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "http://attacker.site/creds",
        "https://evil-corp.com/steal"
    ]

    assert lines == expected_lines, f"Contents of {file_path} do not match the expected sorted decoded URLs. Got: {lines}"

def test_payload_decrypted():
    file_path = "/home/user/payload_decrypted.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "FLAG{0p3n_r3dir3ct_r3s0lv3d}"
    assert content == expected_content, f"Contents of {file_path} do not match the expected decrypted payload."

def test_fix_perms_script_exists():
    script_path = "/home/user/fix_perms.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

def test_webroot_permissions():
    webroot = "/home/user/webroot"
    assert os.path.isdir(webroot), f"Directory {webroot} is missing."

    expected_dir_perm = 0o755
    expected_file_perm = 0o644

    for root, dirs, files in os.walk(webroot):
        # Check directory permissions
        root_stat = os.stat(root)
        root_mode = stat.S_IMODE(root_stat.st_mode)
        assert root_mode == expected_dir_perm, f"Directory {root} has incorrect permissions: {oct(root_mode)}. Expected {oct(expected_dir_perm)}."

        # Check file permissions
        for file in files:
            file_path = os.path.join(root, file)
            file_stat = os.stat(file_path)
            file_mode = stat.S_IMODE(file_stat.st_mode)
            assert file_mode == expected_file_perm, f"File {file_path} has incorrect permissions: {oct(file_mode)}. Expected {oct(expected_file_perm)}."

def test_recovered_directory_exists():
    recovered_dir = "/home/user/recovered"
    assert os.path.isdir(recovered_dir), f"Directory {recovered_dir} is missing. Did you extract the zip file?"

def test_recovered_archive_contents():
    archive_path = "/home/user/exfiltrated.zip"
    wordlist_path = "/home/user/wordlist.txt"
    recovered_dir = "/home/user/recovered"
    required = ("key.txt", "payload.enc")

    with open(wordlist_path, "rb") as f:
        candidates = [line.strip() for line in f if line.strip()]

    expected = None
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        for password in candidates:
            try:
                candidate_contents = {
                    name: archive.read(name, pwd=password)
                    for name in names
                }
            except (RuntimeError, zipfile.BadZipFile):
                continue
            expected = candidate_contents
            break

    assert expected is not None, "No password from the provided wordlist opens the archive."
    expected_by_basename = {os.path.basename(name): data for name, data in expected.items()}

    for filename in required:
        recovered_path = os.path.join(recovered_dir, filename)
        assert os.path.exists(recovered_path), f"Recovered archive member {filename} is missing."
        assert stat.S_ISREG(os.lstat(recovered_path).st_mode), f"{recovered_path} is not a regular file."
        assert filename in expected_by_basename, f"Archive does not contain required member {filename}."
        with open(recovered_path, "rb") as f:
            actual = f.read()
        assert actual == expected_by_basename[filename], f"Recovered file {filename} does not match the archive member."

def test_fix_perms_script_on_arbitrary_directory():
    script_path = "/home/user/fix_perms.sh"
    test_root = tempfile.mkdtemp(prefix="verify_fix_perms_")
    try:
        nested = os.path.join(test_root, "alpha", "beta")
        os.makedirs(nested)
        files = [
            os.path.join(test_root, "root.txt"),
            os.path.join(test_root, "alpha", "middle.bin"),
            os.path.join(nested, "leaf.txt"),
        ]
        for path in files:
            with open(path, "wb") as f:
                f.write(b"permission test\n")

        os.chmod(test_root, 0o700)
        os.chmod(os.path.join(test_root, "alpha"), 0o777)
        os.chmod(nested, 0o711)
        os.chmod(files[0], 0o777)
        os.chmod(files[1], 0o600)
        os.chmod(files[2], 0o755)

        result = subprocess.run(
            ["bash", script_path, test_root],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"fix_perms.sh failed on an arbitrary directory: {result.stderr}"

        for root, dirs, filenames in os.walk(test_root):
            mode = stat.S_IMODE(os.stat(root).st_mode)
            assert mode == 0o755, f"Directory {root} has mode {oct(mode)} after running fix_perms.sh."
            for filename in filenames:
                path = os.path.join(root, filename)
                mode = stat.S_IMODE(os.stat(path).st_mode)
                assert mode == 0o644, f"File {path} has mode {oct(mode)} after running fix_perms.sh."
    finally:
        shutil.rmtree(test_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
