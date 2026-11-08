#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import importlib.metadata
import importlib.util
import io
import os
from pathlib import PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import time

PACKAGE_ROOT = "/app/vendored/artifact_curator-1.2.0"
SCRIPT_PATH = "/home/user/process_all.sh"
PROCESSED_DIR = "/home/user/processed"
SYSTEM_FAKE_DIR = "/home/user/system_fake"
INCOMING_DIR = "/home/user/incoming"


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def test_process_all_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    source = open(SCRIPT_PATH, encoding="utf-8").read()
    assert "artifact-curator" in source, "process_all.sh does not use the artifact-curator CLI"


def test_vendored_package_was_fixed():
    extractor_path = os.path.join(PACKAGE_ROOT, "artifact_curator", "extractor.py")
    dedup_path = os.path.join(PACKAGE_ROOT, "artifact_curator", "dedup.py")
    assert os.path.isfile(extractor_path)
    assert os.path.isfile(dedup_path)

    dedup_source = open(dedup_path, encoding="utf-8").read().lower()
    assert "hashlib" in dedup_source, "Vendored deduplication code does not use hashing"
    assert re.search(r"sha(?:224|256|384|512)|blake2|sha3", dedup_source), \
        "Vendored deduplication code does not use a cryptographic hash"

    spec = importlib.util.spec_from_file_location("vendored_extractor", extractor_path)
    extractor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(extractor)

    with tempfile.TemporaryDirectory(prefix="vendored_extract_") as root:
        archive = os.path.join(root, "case.tar")
        target = os.path.join(root, "out")
        os.mkdir(target)
        traversal_escape = os.path.join(root, "escape.txt")
        absolute_escape = os.path.join("/tmp", f"artifact_curator_abs_{os.getpid()}")
        if os.path.lexists(absolute_escape):
            os.unlink(absolute_escape)

        with tarfile.open(archive, "w") as tar:
            add_bytes(tar, "../escape.txt", b"traversal")
            add_bytes(tar, absolute_escape, b"absolute")
            add_bytes(tar, "safe.bin", b"safe")

        extractor.extract_archive(archive, target)
        assert open(os.path.join(target, "safe.bin"), "rb").read() == b"safe", \
            "Safe members were not extracted"
        assert not os.path.exists(traversal_escape), "Vendored extractor permits ../ traversal"
        assert not os.path.exists(absolute_escape), "Vendored extractor permits absolute-path traversal"

    spec = importlib.util.spec_from_file_location("vendored_dedup", dedup_path)
    dedup = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dedup)
    with tempfile.TemporaryDirectory(prefix="vendored_dedup_") as target:
        first = os.path.join(target, "first.bin")
        second = os.path.join(target, "second.bin")
        third = os.path.join(target, "third.bin")
        open(first, "wb").write(b"identical payload")
        open(second, "wb").write(b"identical payload")
        open(third, "wb").write(b"different payload")
        dedup.deduplicate_binaries(target)
        assert os.stat(first).st_ino == os.stat(second).st_ino, \
            "Vendored deduplication does not replace duplicates with hard links"
        assert os.stat(first).st_ino != os.stat(third).st_ino


def test_cli_is_installed_and_uses_fixed_behavior():
    cli = shutil.which("artifact-curator")
    assert cli is not None, "artifact-curator CLI is not installed or not on PATH"
    assert importlib.metadata.version("artifact-curator") == "1.2.0"

    with tempfile.TemporaryDirectory(prefix="cli_test_") as root:
        archive = os.path.join(root, "case.tar")
        target = os.path.join(root, "out")
        os.mkdir(target)
        traversal_escape = os.path.join(root, "cli_escape.txt")
        absolute_escape = os.path.join("/tmp", f"artifact_curator_cli_abs_{os.getpid()}")
        if os.path.lexists(absolute_escape):
            os.unlink(absolute_escape)

        with tarfile.open(archive, "w") as tar:
            add_bytes(tar, "../cli_escape.txt", b"bad")
            add_bytes(tar, absolute_escape, b"bad")
            add_bytes(tar, "one.bin", b"duplicate")
            add_bytes(tar, "two.bin", b"duplicate")
            add_bytes(tar, "good.bin", b"good")

        result = subprocess.run([cli, archive, target], capture_output=True, text=True)
        assert result.returncode == 0, \
            f"Installed CLI failed. STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        assert open(os.path.join(target, "good.bin"), "rb").read() == b"good"
        assert not os.path.exists(traversal_escape), "Installed CLI permits ../ traversal"
        assert not os.path.exists(absolute_escape), "Installed CLI permits absolute-path traversal"
        assert os.stat(os.path.join(target, "one.bin")).st_ino == \
               os.stat(os.path.join(target, "two.bin")).st_ino, \
               "Installed CLI did not hard-link duplicate files"


def expected_files_from_archives():
    archives = sorted(glob.glob(os.path.join(INCOMING_DIR, "*.tar")))
    assert len(archives) == 100, f"Expected the supplied 100 archives, found {len(archives)}"
    expected = {}
    for archive in archives:
        with tarfile.open(archive, "r") as tar:
            for member in tar.getmembers():
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts or not member.isfile():
                    continue
                stream = tar.extractfile(member)
                assert stream is not None
                data = stream.read()
                relpath = os.path.normpath(member.name)
                expected[relpath] = (hashlib.sha256(data).hexdigest(), data)
    return expected


def test_execution_time_security_complete_output_and_hardlinks():
    expected = expected_files_from_archives()
    assert len(expected) == 100, f"Expected 100 safe artifact files, derived {len(expected)}"

    # Clean up directories before running to ensure accurate timing and security checks.
    if os.path.exists(PROCESSED_DIR):
        shutil.rmtree(PROCESSED_DIR)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    if os.path.exists(SYSTEM_FAKE_DIR):
        shutil.rmtree(SYSTEM_FAKE_DIR)
    os.makedirs(SYSTEM_FAKE_DIR, exist_ok=True)

    start_time = time.time()
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    execution_time = time.time() - start_time

    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    # Preserve the original tar-slip assertion.
    if os.path.isdir(SYSTEM_FAKE_DIR):
        files_in_fake = os.listdir(SYSTEM_FAKE_DIR)
        assert len(files_in_fake) == 0, \
            f"Tar slip vulnerability not fixed! Files found in {SYSTEM_FAKE_DIR}: {files_in_fake}"

    extracted_files = glob.glob(os.path.join(PROCESSED_DIR, "**", "*"), recursive=True)
    extracted_files = [f for f in extracted_files if os.path.isfile(f)]
    assert len(extracted_files) > 0, \
        f"No files were extracted to {PROCESSED_DIR}. The script did not process the archives correctly."

    observed = {}
    for path in extracted_files:
        assert not os.path.islink(path), f"Unexpected symbolic link in output: {path}"
        relpath = os.path.relpath(path, PROCESSED_DIR)
        with open(path, "rb") as handle:
            observed[relpath] = hashlib.sha256(handle.read()).hexdigest()

    assert set(observed) == set(expected), \
        f"Output does not contain exactly all archive artifacts. Missing: {sorted(set(expected)-set(observed))}; unexpected: {sorted(set(observed)-set(expected))}"
    for relpath, (digest, _) in expected.items():
        assert observed[relpath] == digest, f"Incorrect content for {relpath}"

    # Every output with identical content must refer to the same inode.
    inode_by_digest = {}
    for relpath, digest in observed.items():
        stat = os.stat(os.path.join(PROCESSED_DIR, relpath))
        inode = (stat.st_dev, stat.st_ino)
        if digest in inode_by_digest:
            assert inode == inode_by_digest[digest], \
                f"Duplicate artifact {relpath} was not deduplicated with a hard link"
        else:
            inode_by_digest[digest] = inode

    # Preserve the original performance requirement.
    assert execution_time <= 2.0, \
        f"Execution time {execution_time:.2f}s exceeded the 2.0s threshold. Optimization may be incomplete."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
