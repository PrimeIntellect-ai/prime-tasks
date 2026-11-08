#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
import zipfile
from pathlib import Path


def test_extracted_files_exist():
    """Test that the files have been extracted correctly."""
    extracted_dir = "/home/user/extracted"
    assert os.path.exists(extracted_dir), f"Directory {extracted_dir} does not exist."

    expected_files = ["sensor_read", "web_server", "data_logger", "notes.txt", "model.gcode"]
    for f in expected_files:
        path = os.path.join(extracted_dir, f)
        assert os.path.exists(path), f"Extracted file {path} is missing."
        assert os.path.isfile(path), f"{path} is not a file."


def test_extracted_files_match_verified_archives():
    """Verify the ZIPs and compare every extracted payload with its archived bytes."""
    archive_path = "/home/user/project_artifacts.tar.gz"
    extracted_dir = Path("/home/user/extracted")

    with tarfile.open(archive_path, "r:gz") as tar:
        zip_members = [m for m in tar.getmembers() if m.isfile() and m.name.endswith(".zip")]
        assert zip_members, "No ZIP files were found in the tar archive."

        archived_zip_names = set()
        archived_payloads = {}
        for member in zip_members:
            zip_name = os.path.basename(member.name)
            archived_zip_names.add(zip_name)
            zip_bytes = tar.extractfile(member).read()

            extracted_zip = extracted_dir / zip_name
            assert extracted_zip.is_file(), f"Extracted ZIP {extracted_zip} is missing."
            assert extracted_zip.read_bytes() == zip_bytes, f"{extracted_zip} does not match the tar member."

            with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as zf:
                assert zf.testzip() is None, f"ZIP {zip_name} failed its integrity check."
                for info in zf.infolist():
                    if not info.is_dir():
                        archived_payloads[info.filename] = zf.read(info)

            with zipfile.ZipFile(extracted_zip, "r") as zf:
                assert zf.testzip() is None, f"Extracted ZIP {extracted_zip} failed integrity checking."

    assert archived_zip_names == {"part1.zip", "part2.zip"}
    for relative_name, expected_bytes in archived_payloads.items():
        output = extracted_dir / relative_name
        assert output.is_file(), f"Archived payload {output} was not extracted."
        assert output.read_bytes() == expected_bytes, f"Extracted payload {output} differs from the ZIP entry."


def test_symlinks_created_correctly():
    """Test that the symlinks are correctly created in the organized_elfs directory."""
    arm_dir = "/home/user/organized_elfs/ARM"
    x86_dir = "/home/user/organized_elfs/x86_64"

    assert os.path.exists(arm_dir), f"Directory {arm_dir} does not exist."
    assert os.path.exists(x86_dir), f"Directory {x86_dir} does not exist."

    expected_symlinks = {
        os.path.join(arm_dir, "sensor_read"): "/home/user/extracted/sensor_read",
        os.path.join(arm_dir, "data_logger"): "/home/user/extracted/data_logger",
        os.path.join(x86_dir, "web_server"): "/home/user/extracted/web_server"
    }

    for symlink, target in expected_symlinks.items():
        assert os.path.islink(symlink), f"Expected symlink at {symlink} is missing or not a symlink."
        actual_target = os.readlink(symlink)
        assert actual_target == target, f"Symlink {symlink} points to {actual_target}, expected {target}."


def test_script_exists():
    """Test that the organize_elfs.py script exists."""
    script_path = "/home/user/organize_elfs.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_log_file_contents():
    """Test that the log file contains the correct paths, sorted alphabetically."""
    log_path = "/home/user/elf_inventory.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    expected_lines = [
        "/home/user/organized_elfs/ARM/data_logger\n",
        "/home/user/organized_elfs/ARM/sensor_read\n",
        "/home/user/organized_elfs/x86_64/web_server\n"
    ]

    with open(log_path, "r") as f:
        actual_lines = f.readlines()

    actual_lines_stripped = [line.strip() for line in actual_lines if line.strip()]
    expected_lines_stripped = [line.strip() for line in expected_lines]

    assert actual_lines_stripped == expected_lines_stripped, (
        f"Log file contents are incorrect.\nExpected: {expected_lines_stripped}\nActual: {actual_lines_stripped}"
    )


def test_script_behavior_on_unpredictable_files():
    """Execute the submitted script and derive expected results from fresh ELF headers."""
    extracted = Path("/home/user/extracted")
    organized = Path("/home/user/organized_elfs")
    log_path = Path("/home/user/elf_inventory.log")
    script = Path("/home/user/organize_elfs.py")

    shutil.rmtree(extracted)
    shutil.rmtree(organized, ignore_errors=True)
    if log_path.exists() or log_path.is_symlink():
        log_path.unlink()
    extracted.mkdir(parents=True)

    token = secrets.token_hex(8)
    arm_name = f"arm_{token}"
    x86_name = f"x86_{token}"
    text_name = f"text_{token}.txt"
    false_magic_name = f"false_magic_{token}.bin"

    def write_elf(path, machine):
        header = b"\x7fELF" + b"\x00" * 12 + b"\x02\x00" + struct.pack("<H", machine) + b"\x00" * 44
        path.write_bytes(header)

    write_elf(extracted / arm_name, 0x28)
    write_elf(extracted / x86_name, 0x3E)
    (extracted / text_name).write_text("ordinary project data\n")
    (extracted / false_magic_name).write_bytes(b"prefix\x7fELF" + b"\x00" * 64)

    result = subprocess.run(
        ["python3", str(script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Script execution failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    expected = {
        organized / "ARM" / arm_name: str((extracted / arm_name).absolute()),
        organized / "x86_64" / x86_name: str((extracted / x86_name).absolute()),
    }
    for link, target in expected.items():
        assert link.is_symlink(), f"Expected dynamically derived symlink {link} is missing."
        assert os.readlink(link) == target, f"Symlink {link} must point to absolute target {target}."

    actual_links = {p for p in organized.rglob("*") if p.is_symlink()}
    assert actual_links == set(expected), f"Unexpected or missing symlinks: {actual_links}"

    assert log_path.is_file(), "The executed script did not create elf_inventory.log."
    actual_log = [line.strip() for line in log_path.read_text().splitlines() if line.strip()]
    expected_log = sorted(str(path) for path in expected)
    assert actual_log == expected_log, f"Dynamic inventory is incorrect: {actual_log}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
