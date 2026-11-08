#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tarfile
import secrets
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

SCRIPT = "/home/user/process_backups.py"
LOG = "/home/user/backup_summary.log"
CFG_DIR = "/home/user/router_configs"
FSTAB = "/home/user/network_fstab"
ORIGINAL_MOUNT = "/home/user/mnt/remote_backups"
TARGET_DEVICE = "//192.168.1.100/net_backups"
TOKYO = ZoneInfo("Asia/Tokyo")
ARCHIVE_RE = re.compile(r"^backup_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_tokyo\.tar\.gz$")


def direct_cfg_files():
    return {
        entry.name: entry.read_bytes()
        for entry in Path(CFG_DIR).iterdir()
        if entry.is_file() and entry.name.endswith(".cfg")
    }


def clear_outputs(mount):
    if os.path.exists(LOG):
        os.remove(LOG)
    os.makedirs(mount, exist_ok=True)
    for entry in Path(mount).glob("backup_*_tokyo.tar.gz"):
        if entry.is_file() or entry.is_symlink():
            entry.unlink()


def run_script():
    start = datetime.now(TOKYO)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    end = datetime.now(TOKYO)
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return start, end


def read_and_validate_log(expected_mount, expected_files):
    assert os.path.isfile(LOG), f"Log file missing: {LOG}"

    with open(LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Log file should have exactly 3 non-empty lines, found {len(lines)}"
    assert lines[0] == f"Mount: {expected_mount}", (
        f"Line 1 incorrect. Expected 'Mount: {expected_mount}', got '{lines[0]}'"
    )

    expected_size = sum(len(data) for data in expected_files.values())
    assert lines[1] == f"Size: {expected_size}", (
        f"Line 2 incorrect. Expected 'Size: {expected_size}', got '{lines[1]}'"
    )

    archive_line = lines[2]
    assert archive_line.startswith("Archive: "), (
        f"Line 3 should start with 'Archive: ', got '{archive_line}'"
    )
    archive_path = archive_line[len("Archive: "):].strip()

    pattern = rf"^{re.escape(expected_mount)}/backup_\d{{4}}-\d{{2}}-\d{{2}}_\d{{2}}-\d{{2}}-\d{{2}}_tokyo\.tar\.gz$"
    assert re.match(pattern, archive_path), f"Archive path format incorrect: {archive_path}"
    assert os.path.isfile(archive_path), f"Archive file does not exist at {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"File is not a valid tar archive: {archive_path}"
    return archive_path


def validate_timestamp(archive_path, start, end):
    match = ARCHIVE_RE.match(os.path.basename(archive_path))
    assert match, f"Archive filename has an invalid format: {archive_path}"
    timestamp = datetime.strptime(match.group(1), "%Y-%m-%d_%H-%M-%S").replace(tzinfo=TOKYO)
    assert start.replace(microsecond=0) <= timestamp <= end.replace(microsecond=0), (
        f"Archive timestamp {timestamp.isoformat()} is not the current Asia/Tokyo time "
        f"during execution ({start.isoformat()} to {end.isoformat()})"
    )


def validate_exact_archive(archive_path, expected_files):
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()

        # Preserve the original verifier's inclusion and exclusion assertions.
        for cfg in expected_files:
            assert any(cfg in name for name in names), f"Expected config file {cfg} not found in archive"
        assert not any("readme.txt" in name for name in names), "readme.txt should not be included in the archive"

        assert len(members) == len(expected_files), (
            f"Archive must contain exactly the direct .cfg files; found members: {names}"
        )
        archived = {}
        for member in members:
            assert member.isfile(), f"Archive contains a non-regular-file member: {member.name}"
            basename = os.path.basename(member.name.rstrip("/"))
            assert basename in expected_files, f"Unexpected archive member: {member.name}"
            assert basename not in archived, f"Duplicate config in archive: {basename}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            archived[basename] = extracted.read()

        assert set(archived) == set(expected_files), (
            f"Archive members differ from direct .cfg files: {set(archived)} vs {set(expected_files)}"
        )
        for name, expected_data in expected_files.items():
            assert archived[name] == expected_data, f"Archived contents are incorrect for {name}"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script missing: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"


def test_script_runs_and_produces_valid_original_backup():
    expected_files = direct_cfg_files()
    clear_outputs(ORIGINAL_MOUNT)
    start, end = run_script()

    # Preserve the original fixed-mount and size checks.
    archive_path = read_and_validate_log(ORIGINAL_MOUNT, expected_files)
    validate_timestamp(archive_path, start, end)
    validate_exact_archive(archive_path, expected_files)


def test_script_parses_fstab_and_processes_runtime_inputs():
    token = secrets.token_hex(8)
    dynamic_mount = f"/home/user/mnt/runtime_{token}"
    os.makedirs(dynamic_mount, exist_ok=True)

    cfg_path = Path(CFG_DIR)
    for entry in list(cfg_path.iterdir()):
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()

    runtime_files = {
        f"edge_{token}.cfg": secrets.token_bytes(37),
        f"core_{token}.cfg": secrets.token_bytes(113),
    }
    for name, data in runtime_files.items():
        (cfg_path / name).write_bytes(data)
    (cfg_path / f"ignore_{token}.txt").write_bytes(secrets.token_bytes(91))
    nested = cfg_path / "nested"
    nested.mkdir()
    (nested / f"nested_{token}.cfg").write_bytes(secrets.token_bytes(79))

    Path(FSTAB).write_text(
        "# runtime fstab used by verifier\n"
        f"{TARGET_DEVICE}_extra /home/user/mnt/wrong_{token} cifs rw 0 0\n"
        f"//10.0.0.5/shared /home/user/mnt/shared cifs ro 0 0\n"
        f"{TARGET_DEVICE} {dynamic_mount} cifs rw,credentials=/etc/smbcredentials 0 0\n"
        "tmpfs /run tmpfs rw,nosuid,nodev 0 0\n"
    )

    clear_outputs(dynamic_mount)
    start, end = run_script()
    archive_path = read_and_validate_log(dynamic_mount, runtime_files)
    validate_timestamp(archive_path, start, end)
    validate_exact_archive(archive_path, runtime_files)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
