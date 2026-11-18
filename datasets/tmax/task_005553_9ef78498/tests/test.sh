#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import gzip
import io
import os
import secrets
import stat
import subprocess
import tarfile
import zipfile

import pytest

SCRIPT = "/home/user/archive_optimizer.sh"
RAW_DIR = "/home/user/backups/raw"
PROCESSED_DIR = "/home/user/backups/processed"


def elf_bytes(bits):
    cls = b"\x01" if bits == 32 else b"\x02"
    return b"\x7fELF" + cls + b"\x01\x01\x00" + (b"\x00" * 8) + (b"\x00" * 64)


def decode_archive(filepath):
    with open(filepath, "rb") as f:
        encoded = f.read()

    # The base64 CLI normally wraps output, so permit ASCII whitespace while
    # still strictly validating all non-whitespace characters.
    compact = b"".join(encoded.split())
    try:
        gz_data = base64.b64decode(compact, validate=True)
    except Exception as e:
        pytest.fail(f"Failed to base64 decode {filepath}: {e}")

    assert len(gz_data) >= 10, f"Truncated gzip stream in {filepath}"
    assert gz_data[:3] == b"\x1f\x8b\x08", f"Output in {filepath} is not gzip data"
    assert gz_data[8] == 2, f"Gzip stream in {filepath} was not produced at maximum compression (-9)"

    try:
        tar_data = gzip.decompress(gz_data)
    except Exception as e:
        pytest.fail(f"Failed to gzip decompress {filepath}: {e}")

    try:
        with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r:") as archive:
            members = archive.getmembers()
            regular = [member for member in members if member.isfile()]
            result = []
            for member in regular:
                extracted = archive.extractfile(member)
                assert extracted is not None
                result.append((member.name, extracted.read()))
            return members, result
    except Exception as e:
        pytest.fail(f"Failed to read tar archive from {filepath}: {e}")


def files_by_basename(filepath):
    members, regular = decode_archive(filepath)
    result = {}
    for name, data in regular:
        basename = os.path.basename(name)
        assert basename not in result, f"Duplicate basename {basename} in {filepath}"
        result[basename] = data
    return members, result


def get_tar_contents_from_b64gz(filepath):
    members, _ = decode_archive(filepath)
    return [member.name for member in members]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_raw_directory_empty():
    assert os.path.isdir(RAW_DIR), f"Directory {RAW_DIR} does not exist."
    files = os.listdir(RAW_DIR)
    assert len(files) == 0, f"Raw directory {RAW_DIR} is not empty. Found: {files}"


def test_processed_files_exist():
    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."
    for filename in ["db_node_A.b64gz", "db_node_B.b64gz"]:
        filepath = os.path.join(PROCESSED_DIR, filename)
        assert os.path.isfile(filepath), f"Expected processed file {filepath} does not exist."


def test_db_node_a_contents():
    filepath = os.path.join(PROCESSED_DIR, "db_node_A.b64gz")
    assert os.path.isfile(filepath), f"File {filepath} missing."

    names = get_tar_contents_from_b64gz(filepath)
    basenames = [os.path.basename(name) for name in names]
    assert "txn_10452.wal" in basenames, f"txn_10452.wal not found in {filepath}. Found: {basenames}"
    assert "dump1_64.elf" in basenames, f"dump1_64.elf not found in {filepath}. Found: {basenames}"

    _, files = files_by_basename(filepath)
    assert set(files) == {"txn_10452.wal", "dump1_64.elf"}, f"Unexpected regular files in {filepath}: {set(files)}"
    assert files["txn_10452.wal"] == b"TXN: 10452\\nLOGDATA\\n0x00AABB\n"
    assert files["dump1_64.elf"] == elf_bytes(64)


def test_db_node_b_contents():
    filepath = os.path.join(PROCESSED_DIR, "db_node_B.b64gz")
    assert os.path.isfile(filepath), f"File {filepath} missing."

    names = get_tar_contents_from_b64gz(filepath)
    basenames = [os.path.basename(name) for name in names]
    assert "txn_9912.wal" in basenames, f"txn_9912.wal not found in {filepath}. Found: {basenames}"
    assert "crash2_32.elf" in basenames, f"crash2_32.elf not found in {filepath}. Found: {basenames}"

    _, files = files_by_basename(filepath)
    assert set(files) == {"txn_9912.wal", "crash2_32.elf"}, f"Unexpected regular files in {filepath}: {set(files)}"
    assert files["txn_9912.wal"] == b"TXN: 9912\\nLOGDATA\\n0x00CCDD\n"
    assert files["crash2_32.elf"] == elf_bytes(32)


def make_zip(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return output.getvalue()


def make_outer_tar(path, zip_entries):
    with tarfile.open(path, "w") as archive:
        for name, data in zip_entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def test_script_processes_fresh_archives_end_to_end():
    token = secrets.token_hex(6)
    txn_a = secrets.randbelow(800000000) + 100000000
    txn_b = secrets.randbelow(800000000) + 100000000

    wal_a = f"source_{token}.wal"
    wal_b = f"other_{token}.wal"
    elf_a = f"core_{token}.elf"
    elf_b = f"mini_{token}.elf"
    note_a = f"note_{token}.txt"
    note_b = f"manifest_{token}.dat"

    wal_a_data = f"TXN: {txn_a}\nrandom payload {token}\n".encode()
    wal_b_data = f"TXN: {txn_b}\nsecond payload {token}\n".encode()
    note_a_data = f"preserve this file: {token}\n".encode()
    note_b_data = secrets.token_bytes(97)

    base_a = f"live_A_{token}"
    base_b = f"live_B_{token}"
    tar_a = os.path.join(RAW_DIR, base_a + ".tar")
    tar_b = os.path.join(RAW_DIR, base_b + ".tar")

    # Use multiple ZIPs and nested paths so the verifier exercises discovery,
    # extraction, metadata parsing, renaming, and inclusion of unrelated files.
    make_outer_tar(tar_a, {
        "nested/first.zip": make_zip({
            f"deep/{wal_a}": wal_a_data,
            f"deep/{note_a}": note_a_data,
        }),
        "nested/second.zip": make_zip({
            f"bin/{elf_a}": elf_bytes(64),
        }),
    })
    make_outer_tar(tar_b, {
        "payload.zip": make_zip({
            wal_b: wal_b_data,
            elf_b: elf_bytes(32),
            note_b: note_b_data,
        }),
    })

    completed = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, f"Script failed on fresh inputs:\n{completed.stdout}"

    assert not os.path.exists(tar_a), f"Original input was not deleted: {tar_a}"
    assert not os.path.exists(tar_b), f"Original input was not deleted: {tar_b}"
    assert os.listdir(RAW_DIR) == [], f"Raw directory is not empty after processing: {os.listdir(RAW_DIR)}"

    output_a = os.path.join(PROCESSED_DIR, base_a + ".b64gz")
    output_b = os.path.join(PROCESSED_DIR, base_b + ".b64gz")
    assert os.path.isfile(output_a), f"Missing output {output_a}"
    assert os.path.isfile(output_b), f"Missing output {output_b}"

    _, files_a = files_by_basename(output_a)
    expected_a = {
        f"txn_{txn_a}.wal": wal_a_data,
        f"core_{token}_64.elf": elf_bytes(64),
        note_a: note_a_data,
    }
    assert files_a == expected_a, f"Incorrect files or contents in {output_a}: {set(files_a)}"
    assert wal_a not in files_a and elf_a not in files_a
    assert not any(name.endswith(".zip") for name in files_a)

    _, files_b = files_by_basename(output_b)
    expected_b = {
        f"txn_{txn_b}.wal": wal_b_data,
        f"mini_{token}_32.elf": elf_bytes(32),
        note_b: note_b_data,
    }
    assert files_b == expected_b, f"Incorrect files or contents in {output_b}: {set(files_b)}"
    assert wal_b not in files_b and elf_b not in files_b
    assert not any(name.endswith(".zip") for name in files_b)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
