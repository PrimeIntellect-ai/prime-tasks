#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_extracted_directory_exists():
    """Verify that the extracted directory was created."""
    dir_path = "/home/user/extracted"
    assert os.path.isdir(dir_path), f"Expected directory {dir_path} does not exist."

def test_libmath_so_extracted_correctly():
    """Verify libmath.so was extracted and decompressed correctly."""
    file_path = "/home/user/extracted/libmath.so"
    assert os.path.isfile(file_path), f"Expected file {file_path} does not exist."

    with open(file_path, "rb") as f:
        content = f.read()

    expected_content = b"\x7FELF_MOCK_MATH_DATA_9921"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected {expected_content!r}, got {content!r}."

def test_libutils_so_extracted_correctly():
    """Verify libutils.so was extracted correctly."""
    file_path = "/home/user/extracted/libutils.so"
    assert os.path.isfile(file_path), f"Expected file {file_path} does not exist."

    with open(file_path, "rb") as f:
        content = f.read()

    expected_content = b"\x7FELF_MOCK_UTILS_DATA_4455\x00\x01\x02"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected {expected_content!r}, got {content!r}."

def test_ignored_files_not_extracted():
    """Verify that non-.so files were not extracted."""
    readme_path = "/home/user/extracted/readme.txt"
    config_path = "/home/user/extracted/config.json"

    assert not os.path.exists(readme_path), f"File {readme_path} should not have been extracted."
    assert not os.path.exists(config_path), f"File {config_path} should not have been extracted."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_extractor_program.py
import gzip
import os
import pwd
import secrets
import shutil
import stat
import struct
import subprocess
import tempfile

SOURCE = "/home/user/extractor.go"
ARCHIVE = "/home/user/artifacts.bin"
OUTPUT = "/home/user/extracted"

assert os.path.exists(SOURCE), f"Expected Go source {SOURCE} does not exist"
assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"Expected {SOURCE} to be a regular file"
assert os.path.getsize(SOURCE) > 0, f"Expected {SOURCE} to be non-empty"

user = pwd.getpwnam("user")
build_dir = tempfile.mkdtemp(prefix="extractor-verifier-", dir="/tmp")
os.chown(build_dir, user.pw_uid, user.pw_gid)
os.chmod(build_dir, 0o700)
binary = os.path.join(build_dir, "extractor")
cache = os.path.join(build_dir, "gocache")
os.mkdir(cache)
os.chown(cache, user.pw_uid, user.pw_gid)

def demote():
    os.initgroups(user.pw_name, user.pw_gid)
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)

env = os.environ.copy()
env["HOME"] = user.pw_dir
env["GOCACHE"] = cache
build = subprocess.run(
    ["go", "build", "-o", binary, SOURCE],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=60,
    env=env,
    preexec_fn=demote,
)
assert build.returncode == 0, "extractor.go is not a buildable Go program:\n" + build.stderr.decode(errors="replace")

token = secrets.token_hex(6)
gzip_name = f"libgzip_{token}.so"
plain_name = f"libplain_{token}.so"
empty_name = f"libempty_{token}.so"
text_name = f"notes_{token}.txt"
json_name = f"settings_{token}.json"

expected = {
    gzip_name: b"\x7fELF" + os.urandom(1024 * 1024) + (b"GZIP_STREAM_TEST" * 131072),
    plain_name: b"\x7fELF" + os.urandom(3 * 1024 * 1024) + b"\x00\x01\x02",
    empty_name: b"",
}
entries = [
    (text_name, os.urandom(8192), 0),
    (gzip_name, expected[gzip_name], 1),
    (json_name, b'{"random":"' + secrets.token_bytes(24).hex().encode() + b'"}', 1),
    (plain_name, expected[plain_name], 0),
    (empty_name, expected[empty_name], 0),
]

with open(ARCHIVE, "wb") as archive:
    archive.write(b"ARTF")
    archive.write(struct.pack("<I", len(entries)))
    for name, original, compression in entries:
        name_bytes = name.encode("utf-8")
        payload = gzip.compress(original) if compression == 1 else original
        archive.write(struct.pack("<H", len(name_bytes)))
        archive.write(name_bytes)
        archive.write(struct.pack("<I", len(payload)))
        archive.write(struct.pack("<I", len(original)))
        archive.write(struct.pack("<B", compression))
        archive.write(payload)

if os.path.lexists(OUTPUT):
    if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
        shutil.rmtree(OUTPUT)
    else:
        os.unlink(OUTPUT)

run = subprocess.run(
    [binary],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    timeout=45,
    env=env,
    preexec_fn=demote,
)
assert run.returncode == 0, "compiled extractor failed on a fresh archive:\n" + run.stderr.decode(errors="replace")
assert os.path.isdir(OUTPUT), "extractor did not create /home/user/extracted"

actual_names = set(os.listdir(OUTPUT))
assert actual_names == set(expected), (
    f"expected only the generated .so entries {set(expected)!r}, got {actual_names!r}"
)
for name, wanted in expected.items():
    path = os.path.join(OUTPUT, name)
    assert os.path.isfile(path), f"expected extracted file {path}"
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == wanted, f"incorrect extracted content for {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_extractor_program.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
