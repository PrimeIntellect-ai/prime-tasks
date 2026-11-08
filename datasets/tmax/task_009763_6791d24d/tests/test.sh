#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

import pytest


def test_slip_attempts_log():
    log_path = "/home/user/slip_attempts.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_malicious_paths = {
        "../../../../../home/user/hacked.txt",
        "/etc/passwd",
        "absolute_trick/../../../../../../tmp/pwn"
    }

    actual_paths = set(lines)
    assert actual_paths == expected_malicious_paths, f"slip_attempts.log does not contain the exact expected malicious paths. Expected {expected_malicious_paths}, got {actual_paths}"
    assert len(lines) == 3, f"slip_attempts.log should contain exactly 3 lines, but found {len(lines)}"


def test_safe_files_extracted():
    expected_files = {
        "/home/user/extracted/safe_file.txt": "This is safe data.",
        "/home/user/extracted/nested/dir/safe2.txt": "More safe data.",
        "/home/user/extracted/safe3.txt": "Sneaky but technically safe if resolved strictly."
    }

    for path, expected_content in expected_files.items():
        assert os.path.isfile(path), f"Safe file missing: {path}"
        with open(path, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {path}. Expected '{expected_content}', got '{content}'"


def test_malicious_files_not_extracted():
    malicious_paths = [
        "/home/user/hacked.txt",
        "/tmp/pwn"
    ]

    for path in malicious_paths:
        assert not os.path.exists(path), f"Malicious file was extracted outside the target directory: {path}"


def test_rust_project_exists():
    project_dir = "/home/user/wal_extractor"
    assert os.path.isdir(project_dir), f"Rust project directory missing: {project_dir}"

    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing in {project_dir}"

    src_dir = os.path.join(project_dir, "src")
    assert os.path.isdir(src_dir), f"src directory missing in {project_dir}"

    main_rs = os.path.join(src_dir, "main.rs")
    assert os.path.isfile(main_rs), f"main.rs missing in {src_dir}"


def _write_entry(handle, path, data):
    path_bytes = path.encode("utf-8")
    handle.write(struct.pack("<H", len(path_bytes)))
    handle.write(path_bytes)
    handle.write(struct.pack("<I", len(data)))
    handle.write(data)


def _remove_path(path):
    path = Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def test_compiled_tool_on_randomized_recursive_archive():
    token = secrets.token_hex(12)
    root = Path("/tmp") / f"wal_verifier_{token}"
    source = root / "source"
    target = root / "target"
    nested_source = source / "one" / "two" / "three"
    nested_source.mkdir(parents=True)
    target.mkdir(parents=True)

    config_path = Path("/home/user/backup_config.toml")
    log_path = Path("/home/user/slip_attempts.log")
    config_original = config_path.read_bytes()
    log_existed = log_path.exists()
    log_original = log_path.read_bytes() if log_existed else None

    safe_name = f"safe_{token}.bin"
    safe_data = os.urandom(6 * 1024 * 1024 + 137)
    normalized_name = f"normalized_{token}.txt"
    normalized_data = f"normalized-{token}".encode()
    reentered_name = f"reentered_{token}.txt"
    reentered_data = f"reentered-{token}".encode()

    sibling_name = f"target_evil_{token}"
    sibling_slip = f"../{sibling_name}/sibling_escape_{token}.bin"
    relative_slip = f"../../outside_relative_{token}.bin"
    absolute_escape = root / f"outside_absolute_{token}.bin"
    absolute_slip = str(absolute_escape)
    malicious_paths = [sibling_slip, relative_slip, absolute_slip]

    sibling_escape = root / sibling_name / f"sibling_escape_{token}.bin"
    relative_escape = Path(os.path.normpath(os.path.join(str(target), relative_slip)))

    try:
        archive = nested_source / f"random_{token}.wal"
        with archive.open("wb") as handle:
            _write_entry(handle, safe_name, safe_data)
            _write_entry(handle, f"folder/../{normalized_name}", normalized_data)
            _write_entry(handle, sibling_slip, os.urandom(31))
            _write_entry(handle, f"../{target.name}/{reentered_name}", reentered_data)
            _write_entry(handle, relative_slip, os.urandom(37))
            _write_entry(handle, absolute_slip, os.urandom(41))

        with (source / f"ignored_{token}.bin").open("wb") as handle:
            _write_entry(handle, f"must_not_extract_{token}.txt", b"not a WAL")

        config_path.write_text(
            f'source_dir = "{source}"\n'
            f'target_dir = "{target}"\n',
            encoding="utf-8",
        )
        if log_path.exists():
            log_path.unlink()

        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", "/home/user/wal_extractor/Cargo.toml"],
            cwd="/home/user/wal_extractor",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"Rust project failed to compile or run (exit {result.returncode}).\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert (target / safe_name).is_file(), "Randomized safe entry was not extracted"
        assert (target / safe_name).read_bytes() == safe_data, "Large binary payload was not preserved"
        assert (target / normalized_name).read_bytes() == normalized_data, "Normalized safe path was not extracted correctly"
        assert (target / reentered_name).read_bytes() == reentered_data, "Path that normalizes back into target was incorrectly rejected"
        assert not (target / f"must_not_extract_{token}.txt").exists(), "A non-.wal file was processed"

        assert log_path.is_file(), "Tool did not create slip_attempts.log"
        actual_log = log_path.read_text(encoding="utf-8").splitlines()
        assert actual_log == malicious_paths, f"Unexpected slip log contents/order: {actual_log!r}"

        assert not sibling_escape.exists(), "A sibling path sharing the target prefix was extracted"
        assert not relative_escape.exists(), "A relative traversal path was extracted"
        assert not absolute_escape.exists(), "An absolute path was extracted"
    finally:
        config_path.write_bytes(config_original)
        if log_existed:
            log_path.write_bytes(log_original)
        elif log_path.exists():
            log_path.unlink()
        _remove_path(root)
        _remove_path(relative_escape)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
