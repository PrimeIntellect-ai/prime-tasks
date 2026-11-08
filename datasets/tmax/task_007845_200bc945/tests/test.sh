#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
import secrets
import sqlite3
import struct
import subprocess
import uuid
import xml.etree.ElementTree as ET

BASE_DIR = "/home/user/mobile_pipeline"
SO_PATH = os.path.join(BASE_DIR, "build", "libcore.so")
MANIFEST_PATH = os.path.join(BASE_DIR, "manifest.json")
DB_PATH = os.path.join(BASE_DIR, "ota.db")
XML_PATH = os.path.join(BASE_DIR, "metadata.xml")
PIPELINE_PATH = os.path.join(BASE_DIR, "pipeline.py")


def get_expected_metadata():
    tree = ET.parse(XML_PATH)
    root = tree.getroot()
    version = root.find("version").text
    target = root.find("target").text
    return version, target


def get_file_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def assert_shared_library_and_behavior():
    with open(SO_PATH, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "build/libcore.so is not an ELF file."
    assert len(header) >= 18, "build/libcore.so has a truncated ELF header."
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None, "build/libcore.so has an invalid ELF byte order."
    assert struct.unpack(endian + "H", header[16:18])[0] == 3, "build/libcore.so is not an ELF shared object."

    library = ctypes.CDLL(SO_PATH)
    assert hasattr(library, "process_data"), "Shared library does not export process_data."
    process_data = library.process_data
    process_data.argtypes = [ctypes.c_int]
    process_data.restype = ctypes.c_int
    inputs = [0, 1, -1, secrets.randbelow(100000) + 2, -(secrets.randbelow(100000) + 2)]
    for value in inputs:
        assert process_data(value) == value * 42, f"process_data({value}) returned an incorrect result."


def test_build_success():
    """Test that make actually builds a valid, functional shared library."""
    if os.path.lexists(SO_PATH):
        os.remove(SO_PATH)
    result = subprocess.run(
        ["make"], cwd=BASE_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"Running make failed:\n{result.stdout}"
    assert os.path.isfile(SO_PATH), f"Shared object file {SO_PATH} was not built. Did 'make' succeed?"
    assert_shared_library_and_behavior()


def test_manifest_json():
    """Test that manifest.json is created with correct values."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, "manifest.json is not a valid JSON file."

    expected_version, expected_target = get_expected_metadata()
    expected_sha256 = get_file_sha256(SO_PATH)

    assert set(manifest) == {"version", "file", "sha256"}, "manifest.json does not have the exact required structure."
    assert manifest.get("version") == expected_version, f"Expected version '{expected_version}' in manifest, got '{manifest.get('version')}'"
    assert manifest.get("file") == expected_target, f"Expected file '{expected_target}' in manifest, got '{manifest.get('file')}'"
    assert manifest.get("sha256") == expected_sha256, f"Expected sha256 '{expected_sha256}' in manifest, got '{manifest.get('sha256')}'"


def test_database_schema_and_data():
    """Test that ota.db schema is migrated and the new record is inserted."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(releases);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}

    assert "checksum" in columns, "Column 'checksum' was not added to the releases table."
    assert "status" in columns, "Column 'status' was not added to the releases table."

    expected_version, expected_target = get_expected_metadata()
    expected_sha256 = get_file_sha256(SO_PATH)

    cursor.execute("SELECT target, checksum, status FROM releases WHERE version=?;", (expected_version,))
    row = cursor.fetchone()

    assert row is not None, f"No record found in releases table for version '{expected_version}'."
    assert row[0] == expected_target, f"Expected target '{expected_target}' in DB, got '{row[0]}'."
    assert row[1] == expected_sha256, f"Expected checksum '{expected_sha256}' in DB, got '{row[1]}'."
    assert row[2] == "pending", f"Expected status 'pending' in DB, got '{row[2]}'."

    conn.close()


def test_pipeline_performs_automation():
    """Exercise pipeline.py from a fresh legacy database using unpredictable metadata."""
    assert os.path.isfile(PIPELINE_PATH), f"Python pipeline {PIPELINE_PATH} does not exist."

    dynamic_version = "verify-" + uuid.uuid4().hex
    dynamic_target = "libcore-" + uuid.uuid4().hex + ".so"
    with open(XML_PATH, "w") as f:
        f.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<build>\n'
            f'  <version>{dynamic_version}</version>\n'
            f'  <target>{dynamic_target}</target>\n'
            '</build>\n'
        )

    if os.path.lexists(MANIFEST_PATH):
        os.remove(MANIFEST_PATH)
    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE releases (id INTEGER PRIMARY KEY, version TEXT, target TEXT)")
    conn.execute("INSERT INTO releases (version, target) VALUES (?, ?)", ("1.4.1", "libcore.so"))
    conn.commit()
    conn.close()

    result = subprocess.run(
        ["python3", PIPELINE_PATH], cwd=BASE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"Executing pipeline.py failed:\n{result.stdout}"

    assert os.path.isfile(MANIFEST_PATH), "pipeline.py did not create manifest.json."
    with open(MANIFEST_PATH, "r") as f:
        manifest = json.load(f)
    expected_sha256 = get_file_sha256(SO_PATH)
    assert manifest == {
        "version": dynamic_version,
        "file": dynamic_target,
        "sha256": expected_sha256,
    }, "pipeline.py did not derive the required manifest from the current metadata and library."

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("PRAGMA table_info(releases)").fetchall()
    columns = {row[1]: row for row in rows}
    assert "checksum" in columns, "pipeline.py did not add the checksum column."
    assert "status" in columns, "pipeline.py did not add the status column."
    assert columns["checksum"][2].upper() == "TEXT", "checksum column is not TEXT."
    assert columns["status"][2].upper() == "TEXT", "status column is not TEXT."
    default = columns["status"][4]
    assert default is not None and str(default).strip("'\"") == "pending", "status column does not default to 'pending'."

    row = conn.execute(
        "SELECT target, checksum, status FROM releases WHERE version=?",
        (dynamic_version,),
    ).fetchone()
    assert row == (dynamic_target, expected_sha256, "pending"), "pipeline.py did not insert the required release row."
    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
