#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import shutil
import stat
import subprocess
import tarfile
import uuid

HOME = "/home/user"
ARCHIVE = f"{HOME}/dataset.tar"
LINK = f"{HOME}/latest_dataset"
SCRIPT = f"{HOME}/process_dataset.py"
EXTRACT = f"{HOME}/extracted_safe"
HEADERS = f"{HOME}/headers.txt"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_dataset.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def clear_outputs():
    if os.path.lexists(EXTRACT):
        if os.path.isdir(EXTRACT) and not os.path.islink(EXTRACT):
            shutil.rmtree(EXTRACT)
        else:
            os.unlink(EXTRACT)
    if os.path.lexists(HEADERS):
        os.unlink(HEADERS)


def read_headers():
    assert os.path.isfile(HEADERS), f"File {HEADERS} does not exist."
    with open(HEADERS, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def assert_extracted(expected):
    assert os.path.isdir(EXTRACT), f"Directory {EXTRACT} does not exist."
    actual_files = set()
    actual_dirs = set()
    for root, dirs, files in os.walk(EXTRACT, followlinks=False):
        rel_root = os.path.relpath(root, EXTRACT)
        for name in dirs:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Extracted directory is a symlink: {path}"
            rel = name if rel_root == "." else os.path.join(rel_root, name)
            actual_dirs.add(rel.replace(os.sep, "/"))
        for name in files:
            path = os.path.join(root, name)
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f"Extracted path is not a regular file: {path}"
            rel = name if rel_root == "." else os.path.join(rel_root, name)
            rel = rel.replace(os.sep, "/")
            actual_files.add(rel)
            with open(path, "rb") as f:
                assert f.read() == expected[rel], f"Incorrect contents in extracted file {rel}"

    assert actual_files == set(expected), (
        f"Expected extracted files {set(expected)}, found {actual_files}"
    )
    expected_dirs = set()
    for rel in expected:
        parent = os.path.dirname(rel)
        while parent:
            expected_dirs.add(parent)
            parent = os.path.dirname(parent)
    assert actual_dirs == expected_dirs, (
        f"Expected only required parent directories {expected_dirs}, found {actual_dirs}"
    )


def assert_no_token_paths(token):
    for base in ["/home", "/root", "/tmp"]:
        for root, dirs, files in os.walk(base, followlinks=False):
            for name in dirs + files:
                assert token not in name, f"Unsafe archive member was extracted at {os.path.join(root, name)}"


def test_complete_safe_processing():
    # Preserve the original symlink assertion.
    assert os.path.islink(LINK), f"Expected {LINK} to be a symbolic link."
    target = os.readlink(LINK)
    assert os.path.abspath(os.path.join(HOME, target)) == ARCHIVE, (
        f"Symlink points to {target}, expected it to point to {ARCHIVE}."
    )

    assert os.path.lexists(SCRIPT), f"Expected script {SCRIPT} to exist."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"Expected {SCRIPT} to be a regular file."

    unsafe_paths = [
        "/home/user/evil.txt",
        "/root.bin",
        "/home/evil.txt",
        "/evil.txt",
    ]
    for path in unsafe_paths:
        assert not os.path.exists(path), f"Unsafe file was extracted to {path}!"

    with open(ARCHIVE, "rb") as f:
        original_hash = hashlib.sha256(f.read()).hexdigest()

    # Remove hardcoded/empty artifacts and actually execute the submitted script.
    clear_outputs()
    run_script()

    for path in unsafe_paths:
        assert not os.path.exists(path), f"Unsafe file was extracted to {path}!"

    original_expected = {
        "safe1.bin": b"\xDE\xAD\xBE\xEF" + b"some dataset content",
        "safe2.dat": b"\xCA\xFE\xBA\xBE" + b"more dataset content",
        "safe_alpha.bin": b"\x12\x34\x56\x78" + b"alpha content",
    }
    assert_extracted(original_expected)

    # Preserve the original exact top-level name and header assertions.
    assert set(os.listdir(EXTRACT)) == {"safe1.bin", "safe2.dat", "safe_alpha.bin"}
    assert read_headers() == [
        "safe1.bin DEADBEEF",
        "safe2.dat CAFEBABE",
        "safe_alpha.bin 12345678",
    ]

    with open(ARCHIVE, "rb") as f:
        assert hashlib.sha256(f.read()).hexdigest() == original_hash, "dataset.tar was modified"

    # Exercise the script on a fresh archive reached only through latest_dataset.
    # Random names and bytes prevent fixed-output solutions from passing.
    challenge_id = uuid.uuid4().hex
    unsafe_token = "unsafe_" + uuid.uuid4().hex
    challenge_archive = f"/tmp/challenge_{challenge_id}.tar"
    safe_expected = {
        f"nested_{challenge_id}/alpha.bin": os.urandom(19),
        f"zeta_{challenge_id}.dat": os.urandom(23),
        f"middle_{challenge_id}.raw": os.urandom(11),
    }

    with tarfile.open(challenge_archive, "w") as tar:
        for rel, data in safe_expected.items():
            info = tarfile.TarInfo(rel)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))

        directory = tarfile.TarInfo(f"ignored_directory_{challenge_id}")
        directory.type = tarfile.DIRTYPE
        tar.addfile(directory)

        for unsafe_name in [
            f"../{unsafe_token}.bin",
            f"../../tmp/{unsafe_token}_traversal.bin",
            f"/tmp/{unsafe_token}_absolute.bin",
            f"safe/../{unsafe_token}_embedded.bin",
            f"contains..dots/{unsafe_token}_substring.bin",
        ]:
            data = os.urandom(17)
            info = tarfile.TarInfo(unsafe_name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))

        link = tarfile.TarInfo(f"link_{challenge_id}")
        link.type = tarfile.SYMTYPE
        link.linkname = "/etc/passwd"
        tar.addfile(link)

    try:
        os.unlink(LINK)
        os.symlink(challenge_archive, LINK)
        clear_outputs()
        run_script()

        assert_extracted(safe_expected)
        expected_headers = sorted(
            f"{os.path.basename(rel)} {data[:4].hex().upper()}"
            for rel, data in safe_expected.items()
        )
        assert read_headers() == expected_headers, (
            f"Headers were not derived correctly from the challenge archive: {read_headers()}"
        )
        assert_no_token_paths(unsafe_token)
    finally:
        if os.path.lexists(LINK):
            os.unlink(LINK)
        os.symlink(ARCHIVE, LINK)
        if os.path.exists(challenge_archive):
            os.unlink(challenge_archive)

    assert os.path.islink(LINK)
    assert os.path.realpath(LINK) == ARCHIVE
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
