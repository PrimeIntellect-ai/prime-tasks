#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

ZIP_PATH = "/home/user/release_assets.zip"
SCRIPT_PATH = "/home/user/organize_assets.sh"
RAW_PATH = "/home/user/raw_assets.tar.gz"
PROCESSING_PATH = "/home/user/processing"
ORGANIZED_PATH = "/home/user/organized_assets"
CUTOFF = datetime.datetime(2024, 1, 1, tzinfo=datetime.timezone.utc).timestamp()
STATE = {}


def elf_architecture(data):
    with tempfile.NamedTemporaryFile() as candidate:
        candidate.write(data)
        candidate.flush()
        description = subprocess.check_output(
            ["file", "-b", candidate.name], text=True
        ).strip()

    assert "ELF" in description and "executable" in description.lower(), \
        f"ELF candidate was not identified as an ELF executable: {description}"

    if "x86-64" in description:
        return "x86-64"
    if "AArch64" in description:
        return "AArch64"
    if re.search(r"\bARM\b", description):
        return "ARM"
    raise AssertionError(f"Could not determine ELF architecture from: {description}")


def derive_expected_assets():
    assert os.path.isfile(RAW_PATH), f"Source archive {RAW_PATH} is missing."
    source_files = {}

    with tarfile.open(RAW_PATH, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            original_name = os.path.basename(member.name)
            assert original_name, f"Invalid archive member name: {member.name!r}"
            assert original_name not in source_files, \
                f"Duplicate source basename in archive: {original_name}"
            extracted = archive.extractfile(member)
            assert extracted is not None
            source_files[original_name] = {
                "data": extracted.read(),
                "mtime": member.mtime,
            }

    # Preserve the original verifier's assumptions about the supplied input.
    assert {"a1b2c3d4", "e5f6g7h8", "x9y8z7w6", "m1n2o3p4", "j5k4l3m2"}.issubset(source_files)

    expected = {}
    selected_originals = set()
    excluded_originals = set()

    for original_name, info in source_files.items():
        data = info["data"]
        if info["mtime"] >= CUTOFF:
            excluded_originals.add(original_name)
            continue

        output_name = None
        if data.startswith(b"\x7fELF"):
            arch = elf_architecture(data)
            assert " " not in arch
            output_name = f"binary_{arch}_{original_name}.elf"
        elif data.startswith((b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")):
            output_name = f"database_{original_name}.wal"
        else:
            text = data.decode("utf-8", errors="replace")
            lines = text.splitlines()
            if any("; BEGIN GCODE" in line for line in lines[:5]):
                model_lines = [line for line in lines if line.startswith("; ModelName: ")]
                assert model_lines, f"GCode source {original_name} has no ModelName line"
                model_name = model_lines[0][len("; ModelName: "):]
                output_name = f"gcode_{model_name}.gcode"

        if output_name is not None:
            assert output_name not in expected, f"Duplicate expected output name: {output_name}"
            expected[output_name] = data
            selected_originals.add(original_name)

    assert len(expected) == 3, f"Expected three qualifying assets, derived {list(expected)}"
    assert "gcode_Extruder_Gear.gcode" in expected
    assert "database_j5k4l3m2.wal" in expected
    assert any(re.match(r"binary_[^_]+_a1b2c3d4\.elf$", name) for name in expected)
    assert "e5f6g7h8" in excluded_originals
    assert "m1n2o3p4" in excluded_originals
    return source_files, expected, selected_originals, excluded_originals


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    path_stat = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(path_stat.st_mode), f"{SCRIPT_PATH} is not a regular Bash script"
    assert os.path.getsize(SCRIPT_PATH) > 0, f"{SCRIPT_PATH} is empty"
    with open(SCRIPT_PATH, "rb") as script_file:
        assert b"\x00" not in script_file.read(), f"{SCRIPT_PATH} is not a text script"

    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], capture_output=True, text=True, timeout=15
    )
    assert syntax.returncode == 0, f"Bash syntax check failed:\n{syntax.stderr}"

    source_files, expected, selected, excluded = derive_expected_assets()
    STATE.update(
        source_files=source_files,
        expected=expected,
        selected=selected,
        excluded=excluded,
    )

    for path in (PROCESSING_PATH, ORGANIZED_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    if os.path.lexists(ZIP_PATH):
        if os.path.isdir(ZIP_PATH) and not os.path.islink(ZIP_PATH):
            shutil.rmtree(ZIP_PATH)
        else:
            os.unlink(ZIP_PATH)

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"organize_assets.sh exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_release_assets_zip_exists():
    """Test that the final zip archive was created."""
    assert os.path.exists(ZIP_PATH), f"The archive {ZIP_PATH} does not exist."
    assert os.path.isfile(ZIP_PATH), f"The path {ZIP_PATH} exists but is not a file."


def test_release_assets_zip_contents():
    """Test that the zip archive contains the correctly identified, filtered, and renamed files at its root."""
    assert os.path.exists(ZIP_PATH), f"Cannot check contents, {ZIP_PATH} is missing."

    with zipfile.ZipFile(ZIP_PATH, 'r') as zf:
        assert zf.testzip() is None, "The ZIP contains a corrupt entry."
        namelist = zf.namelist()

        # Ensure files are at the root (no directory separators)
        for name in namelist:
            assert '/' not in name and '\\' not in name, f"File '{name}' is not at the root of the zip archive."

        # Check for the expected GCode file
        assert "gcode_Extruder_Gear.gcode" in namelist, "Missing or incorrect GCode file 'gcode_Extruder_Gear.gcode' in zip."

        # Check for the expected WAL file
        assert "database_j5k4l3m2.wal" in namelist, "Missing or incorrect WAL file 'database_j5k4l3m2.wal' in zip."

        # Check for the expected ELF file (architecture string can vary)
        elf_found = any(re.match(r"binary_[^_]+_a1b2c3d4\.elf$", name) for name in namelist)
        assert elf_found, "Missing or incorrectly named ELF file for 'a1b2c3d4' in zip. Expected format: binary_<architecture>_a1b2c3d4.elf"

        # Check that files modified on or after Jan 1, 2024 are excluded
        for name in namelist:
            assert "e5f6g7h8" not in name, f"Included file '{name}' which should have been filtered out by date (newer ELF)."
            assert "m1n2o3p4" not in name, f"Included file '{name}' which should have been filtered out by date (newer GCode)."

        # Check that exactly 3 files are present
        assert len(namelist) == 3, f"Expected exactly 3 files in zip, but found {len(namelist)}: {namelist}"

        assert set(namelist) == set(STATE["expected"]), \
            f"ZIP names differ from the names derived from the source archive: {namelist}"
        for name, source_data in STATE["expected"].items():
            archived_data = zf.read(name)
            assert archived_data == source_data, \
                f"Archived file {name} does not match its source asset byte-for-byte"


def test_extraction_and_organized_directory():
    assert os.path.isdir(PROCESSING_PATH), "The processing directory was not created."
    assert os.path.isdir(ORGANIZED_PATH), "The organized_assets directory was not created."

    organized_names = sorted(
        name for name in os.listdir(ORGANIZED_PATH)
        if os.path.isfile(os.path.join(ORGANIZED_PATH, name))
    )
    assert organized_names == sorted(STATE["expected"]), \
        f"organized_assets has incorrect contents: {organized_names}"

    for name, expected_data in STATE["expected"].items():
        output_path = os.path.join(ORGANIZED_PATH, name)
        assert os.path.isfile(output_path), f"Missing organized file {output_path}"
        with open(output_path, "rb") as output_file:
            assert output_file.read() == expected_data, \
                f"Organized file {name} does not match the source asset"

    processing_files = {}
    for root, _, files in os.walk(PROCESSING_PATH):
        for name in files:
            with open(os.path.join(root, name), "rb") as source_file:
                processing_files[name] = source_file.read()

    for original_name in STATE["excluded"]:
        assert original_name in processing_files, \
            f"Extracted, date-excluded source file {original_name} is missing from processing"
        assert processing_files[original_name] == STATE["source_files"][original_name]["data"]

    for original_name in STATE["selected"]:
        assert original_name not in processing_files, \
            f"Selected source file {original_name} was not moved out of processing"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
