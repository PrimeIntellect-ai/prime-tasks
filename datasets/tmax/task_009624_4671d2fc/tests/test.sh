#!/bin/bash
mkdir -p /logs/verifier

cat << 'DYNAMIC_EOF' > /tmp/test_curator_execution.py
import hashlib
import os
import secrets
import shutil
import subprocess

ROOT = "/home/user/repository_extracted"
MANIFEST = "/home/user/manifest.csv"
CURATOR = "/home/user/curator"

assert os.path.isdir(ROOT), f"Extracted directory missing at {ROOT}"

token = secrets.token_hex(12)
probe_dir = os.path.join(ROOT, ".verifier_probe_" + token)
os.makedirs(os.path.join(probe_dir, "nested"))

elf_probe = os.path.join(probe_dir, "nested", "probe_" + token)
nonelf_probe = os.path.join(probe_dir, "note_" + token + ".txt")
with open(elf_probe, "wb") as f:
    f.write(b"\x7fELF" + secrets.token_bytes(257))
with open(nonelf_probe, "wb") as f:
    f.write(b"not an ELF file\n" + secrets.token_bytes(113))

expected = {}
for current, _, files in os.walk(ROOT):
    for name in files:
        path = os.path.join(current, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        if data[:4] == b"\x7fELF":
            rel = os.path.relpath(path, ROOT)
            expected[rel] = hashlib.sha256(data).hexdigest()

try:
    if os.path.lexists(MANIFEST):
        os.remove(MANIFEST)
    subprocess.run([CURATOR], check=True, timeout=30)
    assert os.path.isfile(MANIFEST), "Running curator did not create manifest.csv"

    with open(MANIFEST, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    actual = {}
    paths = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        rel, digest = parts
        assert rel and not os.path.isabs(rel), f"Manifest path is not relative: {rel}"
        assert rel not in actual, f"Duplicate manifest path: {rel}"
        actual[rel] = digest.lower()
        paths.append(rel)

    assert paths == sorted(paths), "Curator output is not sorted by relative path"
    assert actual == expected, f"Curator output did not match independently derived ELF files: {actual}"
    assert os.path.relpath(nonelf_probe, ROOT) not in actual, "Curator included a non-ELF probe"
finally:
    shutil.rmtree(probe_dir, ignore_errors=True)
    if os.path.lexists(MANIFEST):
        os.remove(MANIFEST)
    subprocess.run([CURATOR], check=True, timeout=30)
DYNAMIC_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib

MANIFEST_PATH = "/home/user/manifest.csv"
EXTRACTED_DIR = "/home/user/repository_extracted"

EXPECTED_BY_PATH = {
    "bin/client": "076ebdd2652db7e1bb7270fc6cf16fb13c9df920f7797cf43b9e4a3bfec8f438",
    "bin/server": "b109e51c86d8cb27dfd8a86a6abcfca2ca1f0bf1ec7eddf95c47fb5af82622df",
    "libcore.so": "1bc832eddd683c3189912be21dc91f543e5904de970f5e1f0e42d76378e1c6b8",
    "libnet.so": "3f48682cdb66bd1095bf8107ef4f0ebf0f970ea4541bf777e434f82635a82208",
}
EXPECTED_HASHES = set(EXPECTED_BY_PATH.values())
EXPECTED_FILES = {
    "bin/client",
    "bin/server",
    "readme.txt",
    "data/config.json",
    "libcore.so",
    "libnet.so",
    "notes.md",
}
EXPECTED_NON_ELF_CONTENT = {
    "readme.txt": b"This is a readme",
    "data/config.json": b"{}",
    "notes.md": b"Library notes",
}

def test_manifest_exists():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"Path {MANIFEST_PATH} is not a file"

def test_manifest_content_and_sorting():
    assert os.path.exists(MANIFEST_PATH), "Manifest file missing"

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 entries in manifest, found {len(lines)}"

    paths = []
    hashes = set()

    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        path, sha256_hash = parts
        paths.append(path)
        hashes.add(sha256_hash.lower())

        abs_path = os.path.join(EXTRACTED_DIR, path)
        assert os.path.exists(abs_path), f"File {path} listed in manifest does not exist in {EXTRACTED_DIR}"

        with open(abs_path, "rb") as bf:
            header = bf.read(4)
            assert header == b"\x7fELF", f"File {path} is not an ELF binary"

        with open(abs_path, "rb") as bf:
            file_hash = hashlib.sha256(bf.read()).hexdigest()
            assert file_hash == sha256_hash.lower(), f"Hash mismatch for {path}: expected {file_hash}, got {sha256_hash}"

    assert hashes == EXPECTED_HASHES, f"Hashes in manifest do not match expected ELF hashes. Got {hashes}"
    assert set(paths) == set(EXPECTED_BY_PATH), f"Manifest paths are incorrect. Got {set(paths)}"
    for path, expected_hash in EXPECTED_BY_PATH.items():
        index = paths.index(path)
        assert lines[index].split(",")[1].lower() == expected_hash, f"Incorrect path/hash pairing for {path}"

    sorted_paths = sorted(paths)
    assert paths == sorted_paths, "Manifest entries are not sorted alphabetically by relative_path"

def test_all_archive_contents_were_extracted():
    actual_files = set()
    for root, _, files in os.walk(EXTRACTED_DIR):
        for name in files:
            path = os.path.join(root, name)
            if os.path.isfile(path):
                actual_files.add(os.path.relpath(path, EXTRACTED_DIR))
    assert actual_files == EXPECTED_FILES, f"Extracted files differ from archive contents. Got {actual_files}"

    for rel, expected_content in EXPECTED_NON_ELF_CONTENT.items():
        path = os.path.join(EXTRACTED_DIR, rel)
        assert os.path.isfile(path), f"Missing extracted non-ELF file: {rel}"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Incorrect content for extracted file: {rel}"

def test_no_archives_remain():
    assert os.path.exists(EXTRACTED_DIR), f"Extracted directory missing at {EXTRACTED_DIR}"

    archive_extensions = ('.zip', '.tar.gz', '.tar.bz2', '.tgz', '.tbz2', '.tar')

    for root, dirs, files in os.walk(EXTRACTED_DIR):
        for file in files:
            assert not file.endswith(archive_extensions), f"Archive file {file} was not deleted from {root}"
TEST_EOF

status=0

if [ ! -f /home/user/curator.cpp ] || [ -L /home/user/curator.cpp ]; then
    echo "Missing or invalid /home/user/curator.cpp"
    status=1
else
    rm -f /home/user/curator
    if ! g++ -O3 /home/user/curator.cpp -lssl -lcrypto -o /home/user/curator; then
        status=1
    elif [ ! -f /home/user/curator ] || [ -L /home/user/curator ] || [ ! -x /home/user/curator ]; then
        echo "Compilation did not produce a regular executable"
        status=1
    elif ! python3 /tmp/test_curator_execution.py; then
        status=1
    fi
fi

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
