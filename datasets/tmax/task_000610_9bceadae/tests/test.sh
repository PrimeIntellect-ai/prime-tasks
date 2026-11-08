#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import zlib
import hashlib
import csv
import pytest
import subprocess
import tempfile
import shutil
import time

ARCHIVE_DIR = "/home/user/archive"
INCOMING_DIR = "/home/user/incoming_docs"
DOCS_ARCHIVE = os.path.join(ARCHIVE_DIR, "docs.archive")
MANIFEST_CSV = os.path.join(ARCHIVE_DIR, "manifest.csv")
PROCESSOR = "/home/user/processor.py"
EXPECTED_FILENAMES = {f"doc_{i:02d}.md" for i in range(1, 51)}

def test_processor_exists():
    assert os.path.isfile(PROCESSOR), f"{PROCESSOR} does not exist or is not a regular file."

def test_archive_files_exist():
    assert os.path.isfile(DOCS_ARCHIVE), f"{DOCS_ARCHIVE} does not exist."
    assert os.path.isfile(MANIFEST_CSV), f"{MANIFEST_CSV} does not exist."

def test_incoming_directory_empty():
    assert os.path.isdir(INCOMING_DIR), f"{INCOMING_DIR} does not exist."
    files = os.listdir(INCOMING_DIR)
    md_files = [f for f in files if f.endswith('.md')]
    assert len(md_files) == 0, f"Found unprocessed .md files in {INCOMING_DIR}: {md_files}"

def test_manifest_and_archive_contents():
    with open(MANIFEST_CSV, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 50, f"Expected 50 rows in manifest.csv, found {len(rows)}"

    try:
        parsed_rows = []
        for row in rows:
            filename, sha256_hex, offset, size = row
            parsed_rows.append({
                'filename': filename,
                'sha256_hex': sha256_hex,
                'offset': int(offset),
                'size': int(size)
            })
    except ValueError as e:
        pytest.fail(f"Manifest row format is incorrect: {e}")

    filenames = [row['filename'] for row in parsed_rows]
    assert len(set(filenames)) == 50, "Manifest filenames must be unique"
    assert set(filenames) == EXPECTED_FILENAMES, (
        f"Manifest filenames do not match doc_01.md through doc_50.md: {filenames}"
    )

    parsed_rows.sort(key=lambda x: x['offset'])

    with open(DOCS_ARCHIVE, 'rb') as f:
        archive_data = f.read()

    expected_offset = 0
    for i, row in enumerate(parsed_rows):
        file_num = row['filename'].replace('doc_', '').replace('.md', '')
        assert row['offset'] == expected_offset, f"Expected offset {expected_offset} for {row['filename']}, got {row['offset']}"

        compressed_chunk = archive_data[row['offset']:row['offset'] + row['size']]
        assert len(compressed_chunk) == row['size'], f"Could not read {row['size']} bytes for {row['filename']} at offset {row['offset']}"

        try:
            decompressed_bytes = zlib.decompress(compressed_chunk)
        except zlib.error as e:
            pytest.fail(f"Failed to decompress data for {row['filename']}: {e}")

        decompressed_text = decompressed_bytes.decode('utf-8')

        assert "INTERNAL_CONFIDENTIAL" not in decompressed_text, f"Found INTERNAL_CONFIDENTIAL in {row['filename']}"
        assert "[REDACTED]" in decompressed_text, f"Did not find [REDACTED] in {row['filename']}"

        expected_text = f"# API Documentation {file_num}\nStatus: [REDACTED]\nDetails: This is the payload for endpoint {file_num}.\n"
        assert decompressed_text == expected_text, f"Content mismatch for {row['filename']}"

        actual_sha256 = hashlib.sha256(decompressed_bytes).hexdigest()
        assert actual_sha256 == row['sha256_hex'], f"SHA-256 mismatch for {row['filename']}. Expected {row['sha256_hex']}, got {actual_sha256}"

        expected_offset += row['size']

    assert len(archive_data) == expected_offset, f"Archive size ({len(archive_data)}) does not match total size from manifest ({expected_offset})"

def test_processor_behavior_on_fresh_race_safe_inputs():
    backup_root = tempfile.mkdtemp(prefix="processor-verifier-")
    backup_incoming = os.path.join(backup_root, "incoming_docs")
    backup_archive = os.path.join(backup_root, "archive")
    proc = None

    shutil.move(INCOMING_DIR, backup_incoming)
    shutil.move(ARCHIVE_DIR, backup_archive)

    expected = {}
    try:
        os.makedirs(INCOMING_DIR)
        os.makedirs(ARCHIVE_DIR)

        proc = subprocess.Popen(
            ["python3", PROCESSOR],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for i in range(1, 51):
            filename = f"doc_{i:02d}.md"
            original = (
                f"# Runtime verification {i:02d}\n"
                f"token=INTERNAL_CONFIDENTIAL\n"
                f"second=INTERNAL_CONFIDENTIAL:{i * 7919}\n"
                "near-match=internal_confidential\n"
            )
            expected[filename] = original.replace("INTERNAL_CONFIDENTIAL", "[REDACTED]").encode("utf-8")
            tmp_path = os.path.join(INCOMING_DIR, f"doc_{i:02d}.tmp")
            md_path = os.path.join(INCOMING_DIR, filename)
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(original)
            os.rename(tmp_path, md_path)
            time.sleep(0.01)

        deadline = time.time() + 20
        while time.time() < deadline:
            md_left = [name for name in os.listdir(INCOMING_DIR) if name.endswith('.md')]
            row_count = 0
            if os.path.isfile(MANIFEST_CSV):
                try:
                    with open(MANIFEST_CSV, newline='') as f:
                        row_count = sum(1 for _ in csv.reader(f))
                except OSError:
                    pass
            if row_count == 50 and not md_left:
                break
            if proc.poll() is not None and (row_count != 50 or md_left):
                break
            time.sleep(0.1)

        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)

        stdout, stderr = proc.communicate()
        assert os.path.isfile(DOCS_ARCHIVE), f"Processor did not create archive. stdout={stdout!r}, stderr={stderr!r}"
        assert os.path.isfile(MANIFEST_CSV), f"Processor did not create manifest. stdout={stdout!r}, stderr={stderr!r}"

        with open(MANIFEST_CSV, newline='') as f:
            rows = list(csv.reader(f))
        assert len(rows) == 50, f"Fresh processor run produced {len(rows)} manifest rows; stderr={stderr!r}"

        parsed = []
        for row in rows:
            assert len(row) == 4, f"Fresh manifest row has wrong format: {row}"
            filename, digest, offset, size = row
            parsed.append((filename, digest, int(offset), int(size)))

        filenames = [row[0] for row in parsed]
        assert len(set(filenames)) == 50, "Fresh manifest contains duplicate filenames"
        assert set(filenames) == EXPECTED_FILENAMES, "Fresh manifest does not contain the exact expected filename set"
        assert not [name for name in os.listdir(INCOMING_DIR) if name.endswith('.md')], "Processor left fresh .md files unprocessed"

        with open(DOCS_ARCHIVE, 'rb') as f:
            archive_data = f.read()

        next_offset = 0
        for filename, digest, offset, size in sorted(parsed, key=lambda row: row[2]):
            assert offset == next_offset, f"Non-sequential offset for {filename}: {offset}, expected {next_offset}"
            transformed = expected[filename]
            chunk = archive_data[offset:offset + size]
            assert len(chunk) == size, f"Truncated compressed chunk for {filename}"
            assert chunk == zlib.compress(transformed), f"{filename} was not compressed with default zlib.compress()"
            assert zlib.decompress(chunk) == transformed, f"Incorrect transformed content for {filename}"
            assert digest == hashlib.sha256(transformed).hexdigest(), f"Incorrect SHA-256 for {filename}"
            next_offset += size

        assert len(archive_data) == next_offset, "Fresh archive has unreferenced or missing bytes"
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if os.path.lexists(INCOMING_DIR):
            shutil.rmtree(INCOMING_DIR)
        if os.path.lexists(ARCHIVE_DIR):
            shutil.rmtree(ARCHIVE_DIR)
        shutil.move(backup_incoming, INCOMING_DIR)
        shutil.move(backup_archive, ARCHIVE_DIR)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
