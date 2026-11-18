#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import tempfile
import pytest

CHECKER = "/home/user/elf_checker"
SOURCE = "/home/user/elf_checker.c"


def run_checker(program, path):
    result = subprocess.run(
        [program, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}; stderr={result.stderr!r}"
    )
    return result.stdout


def expected_for(data):
    if len(data) < 5 or data[:4] != b"\x7fELF":
        return b"UNKNOWN\n"
    if data[4] == 1:
        return b"32\n"
    if data[4] == 2:
        return b"64\n"
    return b"UNKNOWN\n"


def test_elf_checker_executable_and_source():
    assert os.path.exists(CHECKER), f"{CHECKER} does not exist."
    assert os.path.isfile(CHECKER), f"{CHECKER} is not a file."
    st = os.stat(CHECKER)
    assert bool(st.st_mode & stat.S_IXUSR), f"{CHECKER} is not executable."
    with open(CHECKER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{CHECKER} is not a compiled ELF executable."

    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="checker-build-"), "elf_checker")
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert compile_result.returncode == 0, (
        f"{SOURCE} does not compile: {compile_result.stderr.decode(errors='replace')}"
    )

    cases = [
        b"\x7fELF\x01" + secrets.token_bytes(19),
        b"\x7fELF\x02" + secrets.token_bytes(23),
        b"\x7fELF\x00" + secrets.token_bytes(11),
        b"\x7fELF\x03" + secrets.token_bytes(13),
        b"not-elf" + secrets.token_bytes(17),
        b"",
        b"\x7f",
        b"\x7fE",
        b"\x7fEL",
        b"\x7fELF",
    ]

    with tempfile.TemporaryDirectory(prefix="elf-inputs-") as td:
        for data in cases:
            path = os.path.join(td, secrets.token_hex(12))
            with open(path, "wb") as f:
                f.write(data)
            expected = expected_for(data)
            assert run_checker(CHECKER, path) == expected
            assert run_checker(rebuilt, path) == expected

        missing = os.path.join(td, secrets.token_hex(16))
        assert not os.path.exists(missing)
        assert run_checker(CHECKER, missing) == b"UNKNOWN\n"
        assert run_checker(rebuilt, missing) == b"UNKNOWN\n"


def test_renamed_files_and_preserved_contents():
    backup_dir = "/home/user/bin_backup"
    expected = {
        "serviceA_64.bin": b"\x7f\x45\x4c\x46\x02\x01\x01\x00",
        "serviceB_64.bin": b"\x7f\x45\x4c\x46\x02\x01\x01\x00",
        "legacy_worker_32.bin": b"\x7f\x45\x4c\x46\x01\x01\x01\x00",
        "blob_data_UNKNOWN.bin": b"\x00\x00\x00\x00\x00\x00\x00\x00",
    }
    expected_outputs = {
        "serviceA_64.bin": b"64\n",
        "serviceB_64.bin": b"64\n",
        "legacy_worker_32.bin": b"32\n",
        "blob_data_UNKNOWN.bin": b"UNKNOWN\n",
    }

    for filename, expected_bytes in expected.items():
        filepath = os.path.join(backup_dir, filename)
        assert os.path.exists(filepath), f"Expected renamed file {filepath} does not exist."
        assert os.path.isfile(filepath), f"Expected renamed file {filepath} is not a file."
        with open(filepath, "rb") as f:
            assert f.read() == expected_bytes, f"Contents of {filepath} were not preserved."
        assert run_checker(CHECKER, filepath) == expected_outputs[filename]

    for filename in ["serviceA.bin", "serviceB.bin", "legacy_worker.bin", "blob_data.bin"]:
        filepath = os.path.join(backup_dir, filename)
        assert not os.path.exists(filepath), f"Original file {filepath} should have been renamed."


def test_links():
    archive_64_dir = "/home/user/bin_archive/64"
    archive_32_dir = "/home/user/bin_archive/32"
    backup_dir = "/home/user/bin_backup"

    for filename in ["serviceA_64.bin", "serviceB_64.bin"]:
        archive_path = os.path.join(archive_64_dir, filename)
        backup_path = os.path.join(backup_dir, filename)
        assert os.path.exists(archive_path), f"Hard link {archive_path} does not exist."
        assert not os.path.islink(archive_path), f"{archive_path} should be a hard link, not a symlink."
        st_archive = os.stat(archive_path)
        st_backup = os.stat(backup_path)
        assert st_archive.st_ino == st_backup.st_ino, (
            f"{archive_path} and {backup_path} do not point to the same inode (not hard linked)."
        )

    symlink_filename = "legacy_worker_32.bin"
    archive_symlink_path = os.path.join(archive_32_dir, symlink_filename)
    backup_target_path = os.path.join(backup_dir, symlink_filename)
    assert os.path.exists(archive_symlink_path), f"Symlink {archive_symlink_path} does not exist."
    assert os.path.islink(archive_symlink_path), f"{archive_symlink_path} is not a symlink."
    target = os.readlink(archive_symlink_path)
    resolved_target = os.path.abspath(os.path.join(archive_32_dir, target))
    assert resolved_target == backup_target_path, (
        f"Symlink {archive_symlink_path} points to {resolved_target}, expected {backup_target_path}."
    )


def test_readme_encoding():
    utf8_readme_path = "/home/user/bin_backup/readme_utf8.txt"
    assert os.path.exists(utf8_readme_path), f"{utf8_readme_path} does not exist."
    with open(utf8_readme_path, "rb") as f:
        content_bytes = f.read()
    try:
        content_str = content_bytes.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"File {utf8_readme_path} is not valid UTF-8.")
    expected_content = "Archiving requires attention to detail."
    assert content_str == expected_content, (
        f"Content of {utf8_readme_path} does not match expected text."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
