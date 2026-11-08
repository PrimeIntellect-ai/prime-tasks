#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import sys

import pytest

RAW_DIR = "/home/user/raw_gcode"
DOCS_DIR = "/home/user/docs"
TREE_FILE = "/home/user/docs_tree.txt"
SCRIPT_FILE = "/home/user/organizer.py"

EXPECTED_MAPPING = [
    {"filename": "bracket.gcode", "printer": "Ender3", "material": "PLA"},
    {"filename": "gear.gcode", "printer": "PrusaMK3", "material": "PETG"},
    {"filename": "flex_joint.gcode", "printer": "Ender3", "material": "TPU"},
    {"filename": "test_cube.gcode", "printer": "Unknown", "material": "Unknown"},
]

DYNAMIC_MAPPING = []


def parse_expected(path):
    printer = "Unknown"
    material = "Unknown"
    with open(path, "r", errors="replace") as f:
        for line in list(f)[:20]:
            if line.startswith("; PRINTER: "):
                printer = line[len("; PRINTER: "):].strip()
            elif line.startswith("; MATERIAL: "):
                material = line[len("; MATERIAL: "):].strip()
    return printer, material


def assert_links(item):
    symlink_path = os.path.join(
        DOCS_DIR, "by_printer", item["printer"], item["material"], item["filename"]
    )
    original_path = os.path.join(RAW_DIR, item["filename"])
    hardlink_path = os.path.join(
        DOCS_DIR, "by_material", item["material"], item["printer"], item["filename"]
    )

    assert os.path.islink(symlink_path), (
        f"Expected symbolic link missing or not a symlink: {symlink_path}"
    )
    actual_target = os.readlink(symlink_path)
    if not os.path.isabs(actual_target):
        actual_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), actual_target))
    assert actual_target == original_path, (
        f"Symlink {symlink_path} points to {actual_target}, expected {original_path}"
    )

    assert os.path.exists(hardlink_path), f"Expected hard link missing: {hardlink_path}"
    assert not os.path.islink(hardlink_path), (
        f"Expected a hard link, but found a symlink: {hardlink_path}"
    )
    original_stat = os.stat(original_path)
    hardlink_stat = os.stat(hardlink_path)
    assert original_stat.st_ino == hardlink_stat.st_ino, (
        f"File {hardlink_path} is not a hard link to {original_path} "
        f"(inode {hardlink_stat.st_ino} != {original_stat.st_ino})"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_organizer():
    assert os.path.isfile(SCRIPT_FILE), f"Organizer script is missing: {SCRIPT_FILE}"
    assert not os.path.islink(SCRIPT_FILE), f"Organizer script must be a regular file: {SCRIPT_FILE}"

    token = secrets.token_hex(8)
    probes = {
        f"audit_{token}_both.gcode": (
            f"; PRINTER: Printer_{token}\n"
            f"; MATERIAL: Material_{token}\n"
            "G90\n"
        ),
        f"audit_{token}_printer_only.gcode": (
            f"; PRINTER: SoloPrinter_{token}\n"
            "G90\n"
        ),
        f"audit_{token}_material_only.gcode": (
            f"; MATERIAL: SoloMaterial_{token}\n"
            "G90\n"
        ),
        f"audit_{token}_late_metadata.gcode": (
            "".join(f"; filler {i}\n" for i in range(20))
            + f"; PRINTER: LatePrinter_{token}\n"
            + f"; MATERIAL: LateMaterial_{token}\n"
            + "G90\n"
        ),
    }

    for filename, content in probes.items():
        with open(os.path.join(RAW_DIR, filename), "w") as f:
            f.write(content)

    for filename in sorted(os.listdir(RAW_DIR)):
        if filename.endswith(".gcode"):
            printer, material = parse_expected(os.path.join(RAW_DIR, filename))
            DYNAMIC_MAPPING.append({
                "filename": filename,
                "printer": printer,
                "material": material,
            })

    shutil.rmtree(DOCS_DIR, ignore_errors=True)
    os.makedirs(DOCS_DIR)

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("organizer.py did not finish within 20 seconds")

    assert result.returncode == 0, (
        f"organizer.py exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_symlinks_by_printer():
    """Verify that symbolic links are correctly created in the by_printer directory."""
    for item in EXPECTED_MAPPING:
        symlink_path = os.path.join(
            DOCS_DIR, "by_printer", item["printer"], item["material"], item["filename"]
        )
        target_path = os.path.join(RAW_DIR, item["filename"])

        assert os.path.islink(symlink_path), f"Expected symbolic link missing or not a symlink: {symlink_path}"

        actual_target = os.readlink(symlink_path)
        if not os.path.isabs(actual_target):
            actual_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), actual_target))

        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}"


def test_hardlinks_by_material():
    """Verify that hard links are correctly created in the by_material directory."""
    for item in EXPECTED_MAPPING:
        hardlink_path = os.path.join(
            DOCS_DIR, "by_material", item["material"], item["printer"], item["filename"]
        )
        original_path = os.path.join(RAW_DIR, item["filename"])

        assert os.path.exists(hardlink_path), f"Expected hard link missing: {hardlink_path}"
        assert not os.path.islink(hardlink_path), f"Expected a hard link, but found a symlink: {hardlink_path}"

        original_stat = os.stat(original_path)
        hardlink_stat = os.stat(hardlink_path)

        assert original_stat.st_ino == hardlink_stat.st_ino, (
            f"File {hardlink_path} is not a hard link to {original_path} "
            f"(inode {hardlink_stat.st_ino} != {original_stat.st_ino})"
        )


def test_organizer_scans_and_parses_all_gcode_files():
    """Exercise the submitted script on unpredictable files and derived metadata."""
    for item in DYNAMIC_MAPPING:
        assert_links(item)


def test_tree_output_file():
    """Verify that the tree output file exists and contains expected content."""
    assert os.path.isfile(TREE_FILE), f"Tree output file is missing: {TREE_FILE}"

    with open(TREE_FILE, "r") as f:
        content = f.read()

    assert "by_printer" in content, "Tree output does not contain 'by_printer' directory."
    assert "by_material" in content, "Tree output does not contain 'by_material' directory."

    for item in EXPECTED_MAPPING:
        assert item["filename"] in content, f"Tree output is missing file: {item['filename']}"
        if item["printer"] != "Unknown":
            assert item["printer"] in content, f"Tree output is missing printer: {item['printer']}"
        if item["material"] != "Unknown":
            assert item["material"] in content, f"Tree output is missing material: {item['material']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
