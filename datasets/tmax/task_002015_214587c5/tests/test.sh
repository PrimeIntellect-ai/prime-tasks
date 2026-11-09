#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import io
import json
import tarfile
import zipfile
import csv
import hashlib
import subprocess
import pytest

RAW_ARCHIVE = "/home/user/backup_staging/titan_raw.tar.gz"
PROCESSED_DIR = "/home/user/titan_processed"
GCODE_DIR = os.path.join(PROCESSED_DIR, "gcode")
FIRMWARE_DIR = os.path.join(PROCESSED_DIR, "firmware")
MANIFEST_FILE = os.path.join(PROCESSED_DIR, "elf_manifest.csv")
FINAL_TAR = "/home/user/titan_final.tar.gz"
FINAL_SHA = "/home/user/titan_final.sha256"


def get_sha256(filepath):
    sha = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha.update(chunk)
    return sha.hexdigest()


def get_readelf_machine(filepath):
    try:
        output = subprocess.check_output(["readelf", "-h", filepath], text=True)
        for line in output.splitlines():
            if "Machine:" in line:
                return line.split("Machine:", 1)[1].strip()
    except Exception:
        pass
    return None


def read_raw_inputs():
    assert os.path.isfile(RAW_ARCHIVE), f"Source archive {RAW_ARCHIVE} is missing."
    with tarfile.open(RAW_ARCHIVE, "r:gz") as outer:
        regular = {os.path.basename(m.name): m for m in outer.getmembers() if m.isfile()}
        assert {"config.json", "models.tar", "firmware.zip"}.issubset(regular)
        config_bytes = outer.extractfile(regular["config.json"]).read()
        models_bytes = outer.extractfile(regular["models.tar"]).read()
        firmware_bytes = outer.extractfile(regular["firmware.zip"]).read()

    config = json.loads(config_bytes.decode("utf-8"))
    id_to_name = {asset["id"]: asset["name"] for asset in config["assets"]}

    expected_gcode = {}
    with tarfile.open(fileobj=io.BytesIO(models_bytes), mode="r:") as models:
        for member in models.getmembers():
            if not member.isfile() or not member.name.lower().endswith(".gcode"):
                continue
            data = models.extractfile(member).read()
            first_line = data.splitlines()[0].decode("utf-8").strip()
            assert first_line.startswith("; AssetID: ")
            asset_id = first_line[len("; AssetID: "):].strip()
            assert asset_id in id_to_name
            output_name = id_to_name[asset_id].replace(" ", "_") + ".gcode"
            assert output_name not in expected_gcode
            expected_gcode[output_name] = (asset_id, data)

    expected_firmware = {}
    with zipfile.ZipFile(io.BytesIO(firmware_bytes), "r") as firmware:
        for info in firmware.infolist():
            if info.is_dir() or not info.filename.lower().endswith(".elf"):
                continue
            name = os.path.basename(info.filename)
            assert name and name not in expected_firmware
            expected_firmware[name] = firmware.read(info)

    return expected_gcode, expected_firmware


EXPECTED_GCODE, EXPECTED_FIRMWARE = read_raw_inputs()


def test_gcode_files_renamed_and_moved():
    assert os.path.isdir(GCODE_DIR), f"{GCODE_DIR} is missing."

    expected_files = {
        "Main_Bracket.gcode": "A-101",
        "Drive_Gear.gcode": "B-202",
        "Sensor_Housing.gcode": "C-303"
    }
    assert set(EXPECTED_GCODE) == set(expected_files)
    assert set(os.listdir(GCODE_DIR)) == set(EXPECTED_GCODE), "GCode output set does not match models.tar."

    for filename, asset_id in expected_files.items():
        filepath = os.path.join(GCODE_DIR, filename)
        assert os.path.isfile(filepath), f"Expected GCode file {filepath} not found."
        assert not os.path.islink(filepath), f"{filepath} must be a regular output file."

        with open(filepath, "r") as f:
            first_line = f.readline().strip()
            assert asset_id in first_line, f"{filepath} does not contain the expected AssetID {asset_id} in the first line."

        with open(filepath, "rb") as f:
            actual = f.read()
        assert actual == EXPECTED_GCODE[filename][1], f"{filepath} does not match the corresponding file in models.tar."


def test_firmware_files_moved():
    assert os.path.isdir(FIRMWARE_DIR), f"{FIRMWARE_DIR} is missing."
    assert set(EXPECTED_FIRMWARE) == {"controller.elf", "sensor.elf"}
    assert set(os.listdir(FIRMWARE_DIR)) == set(EXPECTED_FIRMWARE), "Firmware output set does not match firmware.zip."

    for filename in ["controller.elf", "sensor.elf"]:
        filepath = os.path.join(FIRMWARE_DIR, filename)
        assert os.path.isfile(filepath), f"Expected ELF file {filepath} not found."
        assert not os.path.islink(filepath), f"{filepath} must be a regular output file."
        with open(filepath, "rb") as f:
            actual = f.read()
        assert actual == EXPECTED_FIRMWARE[filename], f"{filepath} does not match the corresponding ELF in firmware.zip."
        assert get_readelf_machine(filepath) is not None, f"{filepath} is not a readable ELF file."


def test_elf_manifest():
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file {MANIFEST_FILE} is missing."
    assert not os.path.islink(MANIFEST_FILE), "Manifest must be a regular output file."

    with open(MANIFEST_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 3, "Manifest CSV does not have enough rows."
    assert rows[0] == ["Filename", "Machine", "SHA256"], "Manifest header is incorrect."
    assert len(rows) == 1 + len(EXPECTED_FIRMWARE), "Manifest must contain exactly one row per extracted ELF."
    assert all(len(row) == 3 for row in rows[1:]), "Every manifest data row must have exactly three fields."
    assert len({row[0] for row in rows[1:]}) == len(rows) - 1, "Manifest contains duplicate filenames."

    manifest_data = {row[0]: {"machine": row[1], "sha256": row[2]} for row in rows[1:] if len(row) == 3}
    assert set(manifest_data) == set(EXPECTED_FIRMWARE), "Manifest filenames do not match the extracted ELF files."

    for filename in ["controller.elf", "sensor.elf"]:
        assert filename in manifest_data, f"{filename} missing from manifest."
        filepath = os.path.join(FIRMWARE_DIR, filename)

        actual_sha = get_sha256(filepath)
        actual_machine = get_readelf_machine(filepath)

        assert manifest_data[filename]["sha256"] == actual_sha, f"SHA256 mismatch for {filename} in manifest."
        assert manifest_data[filename]["machine"] == actual_machine, f"Machine value mismatch for {filename} in manifest."


def disk_processed_files():
    result = {}
    for root, dirs, files in os.walk(PROCESSED_DIR):
        for dirname in dirs:
            assert not os.path.islink(os.path.join(root, dirname)), "Processed directory must not contain symlinked directories."
        for filename in files:
            path = os.path.join(root, filename)
            assert not os.path.islink(path), "Processed directory must not contain symlinked files."
            rel = os.path.relpath(path, "/home/user").replace(os.sep, "/")
            with open(path, "rb") as f:
                result[rel] = f.read()
    return result


def test_final_tarball():
    assert os.path.isfile(FINAL_TAR), f"Final tarball {FINAL_TAR} is missing."

    expected_files = disk_processed_files()
    required = {
        "titan_processed/elf_manifest.csv",
        *{"titan_processed/gcode/" + name for name in EXPECTED_GCODE},
        *{"titan_processed/firmware/" + name for name in EXPECTED_FIRMWARE},
    }
    assert required.issubset(expected_files), "Required processed outputs are missing before archiving."

    with tarfile.open(FINAL_TAR, "r:gz") as tar:
        names = tar.getnames()
        assert any(name.startswith("titan_processed") for name in names), "Tarball does not contain titan_processed/ directory."
        assert any(name.rstrip("/") == "titan_processed" and m.isdir() for name, m in zip(names, tar.getmembers())), "Tarball root directory titan_processed/ is missing."

        archived_files = {}
        file_names = []
        for member in tar.getmembers():
            normalized = member.name.rstrip("/")
            assert normalized == "titan_processed" or normalized.startswith("titan_processed/"), "Tarball contains entries outside titan_processed/."
            assert not member.issym() and not member.islnk(), "Tarball must not use links for processed outputs."
            assert member.isdir() or member.isfile(), "Tarball contains an unsupported member type."
            if member.isfile():
                file_names.append(member.name)
                archived_files[member.name] = tar.extractfile(member).read()

        assert len(file_names) == len(set(file_names)), "Tarball contains duplicate file entries."
        assert set(archived_files) == set(expected_files), "Tarball does not contain exactly the files in titan_processed/."
        for name, data in expected_files.items():
            assert archived_files[name] == data, f"Archived content for {name} differs from the processed output."


def test_final_sha256():
    assert os.path.isfile(FINAL_SHA), f"Checksum file {FINAL_SHA} is missing."

    actual_hash = get_sha256(FINAL_TAR)
    expected_content = f"{actual_hash}  titan_final.tar.gz"

    with open(FINAL_SHA, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Checksum file content is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
