#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import runpy
import secrets
import sys

import pytest


def test_bsdiff4_installed():
    try:
        import bsdiff4
    except ImportError:
        pytest.fail("bsdiff4 is not installed or cannot be imported. The package installation failed.")


def test_setup_fixed():
    setup_py_path = "/app/bsdiff4-1.2.4/setup.py"
    assert os.path.isfile(setup_py_path), f"setup.py missing at {setup_py_path}"
    with open(setup_py_path, "r") as f:
        content = f.read()
    assert "core_broken.c" not in content, "The deliberate misconfiguration 'core_broken.c' is still present in setup.py"
    assert "core.c" in content, "The setup.py does not contain the fixed 'core.c' source file reference."


def test_backup_script_exists():
    script_path = "/home/user/backup.py"
    assert os.path.isfile(script_path), f"Backup script missing at {script_path}"
    with open(script_path, "r") as f:
        content = f.read()
    assert "fcntl" in content, "The backup script does not seem to import or use fcntl for file locking."
    assert "LOCK_SH" in content, "The backup script does not seem to use fcntl.LOCK_SH for shared locks."


def test_patch_files_exist():
    backup_dir = "/home/user/backup_dir"
    expected_patches = ["data.bin.patch", "logs.txt.patch"]
    for patch in expected_patches:
        patch_path = os.path.join(backup_dir, patch)
        assert os.path.isfile(patch_path), f"Expected patch file {patch} is missing in {backup_dir}"


def test_patches_reconstruct_project_files():
    import bsdiff4

    for name in ("data.bin", "logs.txt"):
        base_path = os.path.join("/home/user/backup_dir", name)
        patch_path = base_path + ".patch"
        source_path = os.path.join("/home/user/project", name)
        with open(base_path, "rb") as f:
            base = f.read()
        with open(patch_path, "rb") as f:
            patch = f.read()
        with open(source_path, "rb") as f:
            expected = f.read()
        try:
            reconstructed = bsdiff4.patch(base, patch)
        except Exception as exc:
            pytest.fail(f"{patch_path} is not a valid bsdiff4 patch: {exc}")
        assert reconstructed == expected, f"{patch_path} does not reconstruct the current project file"


def test_patch_size_metric():
    backup_dir = '/home/user/backup_dir'
    assert os.path.isdir(backup_dir), f"Backup directory missing at {backup_dir}"

    patch_files = [f for f in os.listdir(backup_dir) if f.endswith('.patch')]
    assert len(patch_files) > 0, "No .patch files found in backup directory."

    patch_size = sum(os.path.getsize(os.path.join(backup_dir, f)) for f in patch_files)

    assert patch_size > 0, "Total patch size is 0 bytes. Expected > 0."
    assert patch_size <= 50000, f"Total patch size {patch_size} bytes exceeds the storage efficiency threshold of 50000 bytes."


def test_base_files_intact():
    backup_dir = "/home/user/backup_dir"
    data_bin = os.path.join(backup_dir, "data.bin")
    logs_txt = os.path.join(backup_dir, "logs.txt")

    assert os.path.isfile(data_bin), f"Base file {data_bin} is missing."
    assert os.path.isfile(logs_txt), f"Base file {logs_txt} is missing."

    assert os.path.getsize(data_bin) == 1000000, f"{data_bin} size changed. It should be left intact."
    assert os.path.getsize(logs_txt) == 500000, f"{logs_txt} size changed. It should be left intact."


def run_backup_with_lock_trace(watched_path):
    real_flock = fcntl.flock
    events = []

    def traced_flock(fd, operation):
        number = fd if isinstance(fd, int) else fd.fileno()
        try:
            path = os.path.realpath(f"/proc/self/fd/{number}")
        except OSError:
            path = ""
        if path == watched_path:
            events.append(operation)
        return real_flock(fd, operation)

    old_argv = sys.argv
    fcntl.flock = traced_flock
    sys.argv = ["/home/user/backup.py"]
    try:
        runpy.run_path("/home/user/backup.py", run_name="__main__")
    finally:
        sys.argv = old_argv
        fcntl.flock = real_flock

    shared_positions = [i for i, op in enumerate(events) if op & fcntl.LOCK_SH]
    unlock_positions = [i for i, op in enumerate(events) if op & fcntl.LOCK_UN]
    assert shared_positions, f"The script did not acquire a shared lock on {watched_path}"
    assert unlock_positions, f"The script did not release its lock on {watched_path} with LOCK_UN"
    assert any(s < u for s in shared_positions for u in unlock_positions), \
        f"The shared lock on {watched_path} was not released after acquisition"


def test_script_executes_incremental_backup_and_uses_locks():
    import bsdiff4

    name = ".verifier_incremental.bin"
    source_path = os.path.join("/home/user/project", name)
    base_path = os.path.join("/home/user/backup_dir", name)
    patch_path = base_path + ".patch"

    for path in (source_path, base_path, patch_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    base_data = secrets.token_bytes(65536)
    updated_data = base_data + secrets.token_bytes(1024)

    try:
        with open(source_path, "wb") as f:
            f.write(base_data)

        run_backup_with_lock_trace(source_path)
        assert os.path.isfile(base_path), "A newly encountered project file was not copied to backup_dir"
        with open(base_path, "rb") as f:
            assert f.read() == base_data, "The initial full backup is not an exact copy"

        with open(source_path, "wb") as f:
            f.write(updated_data)

        run_backup_with_lock_trace(source_path)
        assert os.path.isfile(patch_path), "No patch was created for an existing backed-up file"
        with open(base_path, "rb") as f:
            preserved_base = f.read()
        with open(patch_path, "rb") as f:
            patch = f.read()

        assert preserved_base == base_data, "The older full file was overwritten instead of being left intact"
        assert len(patch) > 0, "The generated patch is empty"
        assert len(patch) <= 50000, "The generated incremental patch exceeds the efficiency threshold"
        try:
            reconstructed = bsdiff4.patch(preserved_base, patch)
        except Exception as exc:
            pytest.fail(f"The generated file is not a valid bsdiff4 patch: {exc}")
        assert reconstructed == updated_data, "Applying the generated patch does not reproduce the project file"
    finally:
        for path in (source_path, base_path, patch_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
