#!/bin/bash
mkdir -p /logs/verifier

cat <<'RUNNER_EOF' > /tmp/run_backup_instrumented.py
import json
import mmap
import os
import runpy
import sys
import traceback

script = "/home/user/perform_backup.py"
trace_path = "/tmp/mmap_trace.json"
real_mmap = mmap.mmap
mapped_paths = []

def traced_mmap(fileno, *args, **kwargs):
    try:
        path = os.path.realpath(os.readlink(f"/proc/self/fd/{fileno}"))
        mapped_paths.append(path)
    except Exception:
        mapped_paths.append(None)
    return real_mmap(fileno, *args, **kwargs)

mmap.mmap = traced_mmap
exit_code = 0
try:
    sys.argv = [script]
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_code = exc.code if isinstance(exc.code, int) else 1
except BaseException:
    traceback.print_exc()
    exit_code = 1
finally:
    mmap.mmap = real_mmap
    with open(trace_path, "w") as f:
        json.dump(mapped_paths, f)

sys.exit(exit_code)
RUNNER_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import subprocess

import pytest

SOURCE = "/home/user/data_source"
INC_DIR = "/home/user/backup_dest/inc_01"
MANIFEST = "/home/user/backup_dest/manifest_01.json"
WARNINGS = "/home/user/symlink_warnings.log"
SCRIPT = "/home/user/perform_backup.py"
TRACE = "/tmp/mmap_trace.json"

EXPECTED_KEYS = {
    "file1.txt",
    "dirA/file2.txt",
    "dirB/large1.dat",
    "dirB/large2.dat",
}
EXPECTED_BACKUPS = {
    "file1.txt",
    "dirB/large1.dat",
    "dirB/large2.dat",
}


def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"Backup script missing at {SCRIPT}"
    assert not os.path.islink(SCRIPT), "Backup script must be a regular file, not a symlink"

    shutil.rmtree(INC_DIR, ignore_errors=True)
    for path in (MANIFEST, WARNINGS, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            ["python3", "/tmp/run_backup_instrumented.py"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("perform_backup.py did not terminate; possible symlink loop")

    assert result.returncode == 0, (
        f"perform_backup.py failed with exit code {result.returncode}:\n{result.stdout}"
    )


def test_backup_destination_contents():
    assert os.path.exists(INC_DIR), f"Backup directory {INC_DIR} does not exist"
    assert os.path.isdir(INC_DIR), f"Backup destination {INC_DIR} is not a directory"

    actual_files = set()
    for root, dirs, files in os.walk(INC_DIR, followlinks=False):
        for name in files:
            full_path = os.path.join(root, name)
            assert not os.path.islink(full_path), f"Backup contains a symlink: {full_path}"
            actual_files.add(os.path.relpath(full_path, INC_DIR))

    for rel_path in EXPECTED_BACKUPS:
        full_path = os.path.join(INC_DIR, rel_path)
        assert os.path.isfile(full_path), f"Expected backed up file missing: {full_path}"

    unexpected_file = os.path.join(INC_DIR, "dirA/file2.txt")
    assert not os.path.exists(unexpected_file), (
        f"File {unexpected_file} should not have been copied (unchanged)"
    )

    assert actual_files == EXPECTED_BACKUPS, (
        f"Backup contains an incorrect set of files: {actual_files}"
    )

    for rel_path in EXPECTED_BACKUPS:
        source_path = os.path.join(SOURCE, rel_path)
        backup_path = os.path.join(INC_DIR, rel_path)
        with open(source_path, "rb") as source_file, open(backup_path, "rb") as backup_file:
            assert backup_file.read() == source_file.read(), (
                f"Backed-up contents differ from source for {rel_path}"
            )


def test_symlink_warnings_log():
    assert os.path.isfile(WARNINGS), f"Symlink warnings log missing at {WARNINGS}"

    with open(WARNINGS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "Symlink warnings log is empty, expected loop detection warnings."

    loop_detected = any("link_to_A" in line or "link_to_B" in line for line in lines)
    assert loop_detected, "Symlink warnings log does not contain expected loop paths."

    for line in lines:
        assert os.path.isabs(line), f"Warning entry is not an absolute path: {line}"
        try:
            inside_source = os.path.commonpath([SOURCE, line]) == SOURCE
        except ValueError:
            inside_source = False
        assert inside_source, f"Warning entry is outside the source tree: {line}"
        assert os.path.islink(line), f"Warning entry is not an offending symlink: {line}"


def test_new_manifest():
    assert os.path.isfile(MANIFEST), f"New manifest missing at {MANIFEST}"

    with open(MANIFEST, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    assert isinstance(manifest, dict), "Manifest must be a flat JSON object"
    manifest_keys = set(manifest.keys())
    assert EXPECTED_KEYS.issubset(manifest_keys), (
        f"Manifest is missing keys. Expected {EXPECTED_KEYS}, found {manifest_keys}"
    )
    assert manifest_keys == EXPECTED_KEYS, (
        f"Manifest contains fabricated or symlink-derived extra entries: {manifest_keys - EXPECTED_KEYS}"
    )

    for rel_path in EXPECTED_KEYS:
        assert isinstance(manifest[rel_path], str), f"Manifest hash is not a string for {rel_path}"
        full_path = os.path.join(SOURCE, rel_path)
        actual_hash = compute_sha256(full_path)
        assert manifest[rel_path] == actual_hash, (
            f"Hash mismatch in manifest for {rel_path}. "
            f"Expected {actual_hash}, got {manifest[rel_path]}"
        )


def test_dat_files_were_memory_mapped():
    assert os.path.isfile(TRACE), "mmap instrumentation trace was not produced"
    with open(TRACE, "r") as f:
        mapped_paths = {path for path in json.load(f) if isinstance(path, str)}

    expected_dat_paths = {
        os.path.realpath(os.path.join(SOURCE, "dirB/large1.dat")),
        os.path.realpath(os.path.join(SOURCE, "dirB/large2.dat")),
    }
    assert expected_dat_paths.issubset(mapped_paths), (
        f"Every .dat file must be hashed using Python mmap; missing mappings for "
        f"{expected_dat_paths - mapped_paths}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
