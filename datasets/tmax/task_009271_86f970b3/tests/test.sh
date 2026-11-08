#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import subprocess
import tarfile
import tempfile
import pytest

INCOMING_DIR = "/home/user/incoming_artifacts"
CURATED_DIR = "/home/user/curated_repo"
REPORT_PATH = "/home/user/artifact_report.txt"
BACKUP_INC_TAR = "/home/user/backups/inc.tar"
SNAPSHOT_PATH = "/home/user/backups/repo.snar"


def get_elf_info(filepath):
    """Run readelf -h and extract Machine and Type."""
    try:
        output = subprocess.check_output(
            ["readelf", "-h", filepath],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return None, None

    machine = None
    elf_type = None

    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Type:"):
            val = line.split(":", 1)[1].strip()
            if "EXEC" in val:
                elf_type = "executable"
            elif "DYN" in val:
                elf_type = "shared"
        elif line.startswith("Machine:"):
            val = line.split(":", 1)[1].strip()
            machine = val.replace(" ", "_").replace("-", "")

    return machine, elf_type


def get_expected_state():
    expected_files = {}
    counts = {}

    if not os.path.isdir(INCOMING_DIR):
        return expected_files, counts

    for filename in os.listdir(INCOMING_DIR):
        filepath = os.path.join(INCOMING_DIR, filename)
        if not os.path.isfile(filepath):
            continue

        machine, elf_type = get_elf_info(filepath)
        if machine and elf_type:
            expected_files[filename] = {
                "machine": machine,
                "type": elf_type,
                "src_path": filepath,
            }

            if machine not in counts:
                counts[machine] = {"executable": 0, "shared": 0}
            counts[machine][elf_type] += 1

    return expected_files, counts


def curated_relative_name(name):
    parts = [part for part in name.split("/") if part not in ("", ".")]
    try:
        root_index = parts.index("curated_repo")
    except ValueError:
        return None
    return "/".join(parts[root_index + 1:])


def test_curated_repo_structure_and_hardlinks():
    expected_files, _ = get_expected_state()
    assert expected_files, "No valid ELF files found in incoming_artifacts to test against."

    for filename, info in expected_files.items():
        expected_dir = os.path.join(CURATED_DIR, info["machine"], info["type"])
        expected_path = os.path.join(expected_dir, filename)

        assert os.path.isdir(expected_dir), f"Directory {expected_dir} does not exist."
        assert os.path.isfile(expected_path), f"File {expected_path} does not exist."

        src_stat = os.stat(info["src_path"])
        dst_stat = os.stat(expected_path)

        assert src_stat.st_ino == dst_stat.st_ino, f"{expected_path} is not a hard link to {info['src_path']}."
        assert src_stat.st_dev == dst_stat.st_dev, f"{expected_path} is on a different device."


def test_artifact_report():
    _, counts = get_expected_state()
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

    expected_lines = []
    for machine in sorted(counts.keys()):
        exec_count = counts[machine]["executable"]
        shared_count = counts[machine]["shared"]
        expected_lines.append(
            f"{machine} -> Executables: {exec_count}, Shared: {shared_count}"
        )

    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Report content mismatch. Expected: {expected_lines}, Got: {actual_lines}"


def test_incremental_backup():
    assert os.path.isfile(BACKUP_INC_TAR), f"Incremental backup {BACKUP_INC_TAR} is missing."

    try:
        output = subprocess.check_output(
            ["tar", "-tf", BACKUP_INC_TAR],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read incremental tar archive: {e.output}")

    # Preserve the original archive assertion.
    assert any("curated_repo" in line for line in output.splitlines()), "curated_repo not found in the incremental backup."

    expected_files, _ = get_expected_state()
    expected_by_relative_name = {
        f"{info['machine']}/{info['type']}/{filename}": info["src_path"]
        for filename, info in expected_files.items()
    }

    try:
        with tarfile.open(BACKUP_INC_TAR, "r:*") as archive:
            members = archive.getmembers()

            # GNU tar marks directories in a listed-incremental archive with its
            # GNU dump-directory member type. An ordinary tar archive lacks it.
            dumpdirs = [member for member in members if member.type == tarfile.GNUTYPE_DUMPDIR]
            assert dumpdirs, "inc.tar is not a GNU listed-incremental archive (no dump-directory records)."
            assert any(curated_relative_name(member.name) is not None for member in dumpdirs), \
                "GNU incremental metadata for curated_repo is missing."

            regular_members = {
                curated_relative_name(member.name): member
                for member in members
                if member.isfile() and curated_relative_name(member.name) is not None
            }

            for relative_name, source_path in expected_by_relative_name.items():
                assert relative_name in regular_members, f"{relative_name} is missing from the incremental backup."
                archived = archive.extractfile(regular_members[relative_name])
                assert archived is not None, f"Could not read {relative_name} from the incremental backup."
                with archived, open(source_path, "rb") as source:
                    assert archived.read() == source.read(), f"Archived content for {relative_name} does not match the curated file."
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Failed to inspect incremental archive: {e}")

    assert os.path.isfile(SNAPSHOT_PATH), f"Incremental snapshot {SNAPSHOT_PATH} is missing."

    # A successful backup using the existing snapshot updates it to describe the
    # current repository. Reusing a copy immediately must therefore produce no
    # regular-file payloads because the repository has not changed.
    with tempfile.TemporaryDirectory() as temp_dir:
        snapshot_copy = os.path.join(temp_dir, "repo.snar")
        probe_tar = os.path.join(temp_dir, "probe.tar")
        shutil.copy2(SNAPSHOT_PATH, snapshot_copy)

        probe = subprocess.run(
            [
                "tar",
                f"--listed-incremental={snapshot_copy}",
                "-cf",
                probe_tar,
                CURATED_DIR,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert probe.returncode == 0, f"repo.snar is not usable GNU tar incremental state: {probe.stderr}"

        try:
            with tarfile.open(probe_tar, "r:*") as archive:
                repeated_files = [
                    member.name
                    for member in archive.getmembers()
                    if member.isfile() and curated_relative_name(member.name) is not None
                ]
        except (tarfile.TarError, OSError) as e:
            pytest.fail(f"Failed to inspect snapshot consistency probe: {e}")

        assert not repeated_files, \
            f"repo.snar was not updated for the current repository; unchanged files were backed up again: {repeated_files}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
