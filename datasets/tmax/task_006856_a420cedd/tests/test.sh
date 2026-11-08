#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

SOURCE_ARCHIVE = "/home/user/project_backups.tar.gz"
EXTRACTED_PROJECT = "/home/user/extracted_project"
REPORT_PATH = "/home/user/elf_report.txt"
FILTERED_BACKUP = "/home/user/filtered_backup.tar.gz"


def machine_field(path):
    out = subprocess.check_output(
        ["readelf", "-h", str(path)], text=True, stderr=subprocess.STDOUT
    )
    for line in out.splitlines():
        if "Machine:" in line:
            return line.split("Machine:", 1)[1].strip()
    raise AssertionError(f"readelf produced no Machine field for {path}")


def regular_file_map(root):
    root = Path(root)
    assert root.is_dir(), f"Missing directory: {root}"
    result = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(current) / name
            assert not path.is_symlink(), f"Unexpected symbolic link: {path}"
        for name in files:
            path = Path(current) / name
            mode = path.lstat().st_mode
            assert stat.S_ISREG(mode), f"Expected a regular file: {path}"
            result[path.relative_to(root).as_posix()] = path.read_bytes()
    return result


def prepare_expected_tree(destination):
    with tarfile.open(SOURCE_ARCHIVE, "r:gz") as tar:
        tar.extractall(destination)

    inner_archives = list(Path(destination).rglob("inner_backup.tar"))
    assert len(inner_archives) == 1, (
        f"Expected exactly one inner_backup.tar in source archive, found {len(inner_archives)}"
    )
    inner = inner_archives[0]
    with tarfile.open(inner, "r:") as tar:
        tar.extractall(inner.parent)


def expected_outputs(root):
    root = Path(root)
    elf_files = {}
    gcode_files = {}
    report_lines = []

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        data = path.read_bytes()
        if data.startswith(b"\x7fELF"):
            architecture = machine_field(path)
            elf_files[relative] = data
            report_lines.append(f"{relative} - {architecture}")
        elif path.suffix == ".gcode":
            gcode_files[relative] = data

    return elf_files, gcode_files, sorted(report_lines)


def clean_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    path = PurePosixPath(name)
    assert name and not path.is_absolute(), f"Unsafe archive member path: {name!r}"
    assert ".." not in path.parts, f"Unsafe archive member path: {name!r}"
    return name


def test_elf_report_exists_and_content_correct():
    """Retain the original report assertions."""
    assert os.path.isfile(REPORT_PATH), f"The ELF report is missing: {REPORT_PATH}"

    try:
        out = subprocess.check_output(["readelf", "-h", "/bin/ls"], universal_newlines=True)
        arch = ""
        for line in out.splitlines():
            if "Machine:" in line:
                arch = line.split("Machine:")[1].strip()
                break
    except Exception:
        arch = "Advanced Micro Devices X86-64"

    expected_lines = [
        f"bin/tool_cat - {arch}",
        f"bin/tool_ls - {arch}",
        f"nested_dir/inner_bin/tool_echo - {arch}",
    ]

    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == sorted(expected_lines), (
        "elf_report.txt contents do not match the expected output or are not sorted correctly.\n"
        f"Expected: {sorted(expected_lines)}\nActual: {actual_lines}"
    )


def test_filtered_backup_archive():
    """Retain the original archive name/count/filter assertions."""
    assert os.path.isfile(FILTERED_BACKUP), (
        f"The filtered backup archive is missing: {FILTERED_BACKUP}"
    )

    with tarfile.open(FILTERED_BACKUP, "r:gz") as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        file_paths = [m.name for m in members]
        cleaned_paths = {p[2:] if p.startswith("./") else p for p in file_paths}

        expected_files = {
            "bin/tool_cat",
            "bin/tool_ls",
            "nested_dir/inner_bin/tool_echo",
            "shape1.gcode",
            "nested_dir/shape2.gcode",
        }

        assert len(cleaned_paths) == 5, (
            f"Incorrect number of files in {FILTERED_BACKUP}. "
            f"Expected 5, found {len(cleaned_paths)}."
        )
        missing_files = expected_files - cleaned_paths
        assert not missing_files, f"Missing expected files in archive: {missing_files}"
        extra_files = cleaned_paths - expected_files
        assert not extra_files, f"Archive contains unauthorized files: {extra_files}"

        for path in cleaned_paths:
            assert not path.endswith(".txt"), f"Archive contains unauthorized .txt file: {path}"
            assert not path.endswith(".log"), f"Archive contains unauthorized .log file: {path}"


def test_artifacts_match_extracted_source_and_are_real():
    """Derive answers from the source, verify bytes, and execute readelf on archived ELFs."""
    with tempfile.TemporaryDirectory() as expected_dir, tempfile.TemporaryDirectory() as archived_dir:
        prepare_expected_tree(expected_dir)
        expected_tree = regular_file_map(expected_dir)
        actual_tree = regular_file_map(EXTRACTED_PROJECT)
        assert actual_tree == expected_tree, (
            "extracted_project does not exactly match the main archive after extracting "
            "inner_backup.tar in place"
        )

        elf_files, gcode_files, expected_report = expected_outputs(expected_dir)
        expected_filtered = dict(elf_files)
        expected_filtered.update(gcode_files)

        with open(REPORT_PATH, "r") as report:
            actual_report = [line.rstrip("\n") for line in report if line.rstrip("\n")]
        assert actual_report == expected_report, (
            f"Report was not derived correctly from the extracted ELF files. "
            f"Expected {expected_report}, got {actual_report}"
        )

        archived_files = {}
        with tarfile.open(FILTERED_BACKUP, "r:gz") as tar:
            all_members = tar.getmembers()
            for member in all_members:
                clean_member_name(member.name)
                assert member.isdir() or member.isreg(), (
                    f"Archive contains a non-file, non-directory member: {member.name}"
                )
                if not member.isreg():
                    continue
                name = clean_member_name(member.name)
                assert name not in archived_files, f"Duplicate archive member: {name}"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archive member: {name}"
                archived_files[name] = extracted.read()

        assert set(archived_files) == set(expected_filtered), (
            f"Archive members differ from the independently derived ELF/.gcode set. "
            f"Expected {sorted(expected_filtered)}, got {sorted(archived_files)}"
        )
        for name, expected_bytes in expected_filtered.items():
            assert archived_files[name] == expected_bytes, (
                f"Archived bytes do not match extracted source file: {name}"
            )

        archive_root = Path(archived_dir)
        for name, data in archived_files.items():
            destination = archive_root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)

        for name in elf_files:
            archived_path = archive_root / name
            assert archived_path.read_bytes().startswith(b"\x7fELF"), (
                f"Archived alleged binary is not an ELF file: {name}"
            )
            assert machine_field(archived_path) == machine_field(Path(expected_dir) / name), (
                f"Archived ELF has the wrong machine architecture: {name}"
            )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
