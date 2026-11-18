#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bz2
import gzip
import hashlib
import io
import lzma
import os
import random
import subprocess
import tarfile
import zipfile
import zlib


def test_compressor_script_exists_and_executable():
    script_path = "/home/user/compressor.py"
    assert os.path.isfile(script_path), f"Expected script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Expected script {script_path} to be executable."


def test_backup_bin_exists():
    backup_path = "/home/user/backup.bin"
    assert os.path.isfile(backup_path), f"Expected backup file {backup_path} does not exist."


def test_compression_ratio():
    backup_path = "/home/user/backup.bin"
    bin_b_path = "/home/user/repo/bin_B.dat"
    bin_c_path = "/home/user/repo/bin_C.dat"

    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."
    assert os.path.isfile(bin_b_path), f"File {bin_b_path} is missing."
    assert os.path.isfile(bin_c_path), f"File {bin_c_path} is missing."

    raw_size = os.path.getsize(bin_b_path) + os.path.getsize(bin_c_path)
    compressed_size = os.path.getsize(backup_path)

    assert compressed_size > 0, "Backup file is empty."

    compression_ratio = raw_size / compressed_size
    threshold = 1.42

    assert compression_ratio >= threshold, (
        f"Compression ratio too low. "
        f"Raw size: {raw_size}, Compressed size: {compressed_size}. "
        f"Ratio: {compression_ratio:.3f}, Expected at least: {threshold}"
    )


def _decoded_blobs(archive):
    """Return bounded, recursively unpacked representations of an archive."""
    queue = [archive]
    result = []
    seen = set()

    while queue and len(result) < 200:
        blob = queue.pop(0)
        digest = hashlib.sha256(blob).digest()
        if digest in seen or len(blob) > 2_000_000:
            continue
        seen.add(digest)
        result.append(blob)

        for decoder in (gzip.decompress, bz2.decompress, lzma.decompress, zlib.decompress):
            try:
                value = decoder(blob)
                if value and len(value) <= 2_000_000:
                    queue.append(value)
            except Exception:
                pass

        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as zf:
                for info in zf.infolist():
                    if info.file_size <= 2_000_000:
                        queue.append(zf.read(info))
        except Exception:
            pass

        try:
            with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as tf:
                for member in tf.getmembers():
                    if member.isfile() and member.size <= 2_000_000:
                        stream = tf.extractfile(member)
                        if stream is not None:
                            queue.append(stream.read())
        except Exception:
            pass

        # Also recognize a zlib stream following a small custom archive header.
        for offset in range(max(0, len(blob) - 1)):
            if blob[offset] != 0x78:
                continue
            try:
                value = zlib.decompress(blob[offset:])
                if value and len(value) <= 2_000_000:
                    queue.append(value)
            except Exception:
                pass

    return result


def test_executable_builds_incremental_dictionary_archive():
    script = "/home/user/compressor.py"
    backup = "/home/user/backup.bin"
    repo = "/home/user/repo"

    # Derived test data: the verifier knows the expected post-dictionary bytes,
    # but the submitted program must read and transform the current files.
    rng = random.Random(917263)
    b_tokens = bytes(rng.choice((0x01, 0x03)) for _ in range(7000))
    b_raw = b"".join(
        b"\x00\x00\x00\x00" if token == 0x01 else b"\xde\xad\xbe\xef"
        for token in b_tokens
    )
    c_tokens = b"\x02" * 5000
    c_raw = b"\xff\xff\xff\xff" * 5000

    with open(os.path.join(repo, "bin_B.dat"), "wb") as f:
        f.write(b_raw)
    with open(os.path.join(repo, "bin_C.dat"), "wb") as f:
        f.write(c_raw)

    # A is old according to snapshot.csv. Making it large and incompressible
    # detects implementations that package every file instead of incrementally.
    with open(os.path.join(repo, "bin_A.dat"), "wb") as f:
        f.write(os.urandom(262144))

    os.utime(os.path.join(repo, "bin_A.dat"), (1600000000, 1600000000))
    os.utime(os.path.join(repo, "bin_B.dat"), (1700000105, 1700000105))
    os.utime(os.path.join(repo, "bin_C.dat"), (1700000110, 1700000110))

    if os.path.exists(backup):
        os.unlink(backup)

    completed = subprocess.run(
        [script], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert completed.returncode == 0, (
        "compressor.py failed when executed:\n"
        + completed.stderr.decode("utf-8", "replace")
    )
    assert os.path.isfile(backup), "Executing compressor.py did not create backup.bin."

    with open(backup, "rb") as f:
        archive = f.read()
    assert archive, "Executing compressor.py created an empty archive."

    raw_size = len(b_raw) + len(c_raw)
    assert len(archive) <= raw_size * 0.70, (
        f"Generated archive is not at least 30% smaller than updated files: "
        f"raw={raw_size}, archive={len(archive)}"
    )

    blobs = _decoded_blobs(archive)
    assert any(b_tokens in blob for blob in blobs), (
        "Archive does not contain bin_B.dat after the configured "
        "00000000->01 and DEADBEEF->03 replacements."
    )
    assert any(c_tokens in blob for blob in blobs), (
        "Archive does not contain bin_C.dat after the configured FFFFFFFF->02 replacement."
    )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
