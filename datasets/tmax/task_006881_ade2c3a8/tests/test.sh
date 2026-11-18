#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess

SOURCE = '/home/user/migrator.rs'
BINARY = '/tmp/migrator_under_test'
BASE_DIR = '/home/user/new_volume'

EXPECTED_STATE = {
    'configs': {'type': 'd', 'perms': 0o750},
    'configs/database.conf': {'type': 'f', 'perms': 0o600},
    'data': {'type': 'd', 'perms': 0o700},
    'data/v1': {'type': 'd', 'perms': 0o755},
    'data/active': {'type': 'l', 'target': 'v1'},
    'current_config': {'type': 'l', 'target': 'configs/database.conf'},
}


def assert_expected_state():
    assert os.path.isdir(BASE_DIR), f"The target directory {BASE_DIR} is missing."

    for path, props in EXPECTED_STATE.items():
        full_path = os.path.join(BASE_DIR, path)
        assert os.path.lexists(full_path), f"Path missing: {full_path}"

        if props['type'] == 'd':
            assert os.path.isdir(full_path), f"Expected directory at {full_path}"
            mode = stat.S_IMODE(os.stat(full_path).st_mode)
            assert mode == props['perms'], f"Expected permissions {oct(props['perms'])} for {full_path}, got {oct(mode)}"
        elif props['type'] == 'f':
            assert os.path.isfile(full_path), f"Expected file at {full_path}"
            assert not os.path.islink(full_path), f"Expected regular file at {full_path}, not a symlink"
            mode = stat.S_IMODE(os.stat(full_path).st_mode)
            assert mode == props['perms'], f"Expected permissions {oct(props['perms'])} for {full_path}, got {oct(mode)}"
            assert os.path.getsize(full_path) == 0, f"Expected empty file at {full_path}"
        elif props['type'] == 'l':
            assert os.path.islink(full_path), f"Expected symlink at {full_path}"
            target = os.readlink(full_path)
            assert target == props['target'], f"Expected symlink {full_path} to point to {props['target']}, got {target}"


def run_migrator():
    subprocess.run([BINARY], cwd='/home/user', check=True, timeout=20)


def test_00_compile_run_and_idempotently_repair_state():
    """Compile the submitted Rust program and verify that it creates and repairs the state."""
    assert os.path.isfile(SOURCE), "The Rust source file /home/user/migrator.rs is missing."
    assert not os.path.islink(SOURCE), "The Rust source must be a regular file, not a symlink."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), "The Rust source must be a regular file."

    subprocess.run(['rustc', SOURCE, '-o', BINARY], check=True, timeout=30)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Rust compilation did not produce an executable."

    # Start from the empty target supplied by the environment, so preconstructed
    # filesystem state cannot substitute for behavior in the Rust program.
    if os.path.lexists(BASE_DIR):
        if os.path.isdir(BASE_DIR) and not os.path.islink(BASE_DIR):
            shutil.rmtree(BASE_DIR)
        else:
            os.unlink(BASE_DIR)
    os.mkdir(BASE_DIR)
    os.chmod(BASE_DIR, 0o777)

    run_migrator()
    assert_expected_state()

    # Introduce deviations explicitly named by the task and ensure another run
    # repairs them without error.
    os.chmod(os.path.join(BASE_DIR, 'configs'), 0o777)
    os.chmod(os.path.join(BASE_DIR, 'configs/database.conf'), 0o666)
    os.chmod(os.path.join(BASE_DIR, 'data'), 0o755)
    os.chmod(os.path.join(BASE_DIR, 'data/v1'), 0o700)
    with open(os.path.join(BASE_DIR, 'configs/database.conf'), 'wb') as f:
        f.write(b'not empty')

    for relpath, wrong_target in (
        ('data/active', 'wrong-version'),
        ('current_config', 'wrong-config'),
    ):
        path = os.path.join(BASE_DIR, relpath)
        os.unlink(path)
        os.symlink(wrong_target, path)

    run_migrator()
    assert_expected_state()

    # A further unchanged run must also succeed and preserve the desired state.
    run_migrator()
    assert_expected_state()


def test_migrator_rs_exists():
    """Verify that the Rust source file was created."""
    assert os.path.isfile('/home/user/migrator.rs'), "The Rust source file /home/user/migrator.rs is missing."


def test_filesystem_structure_and_permissions():
    """Verify the exact filesystem structure, permissions, and symlinks in /home/user/new_volume."""
    base_dir = '/home/user/new_volume'
    assert os.path.isdir(base_dir), f"The target directory {base_dir} is missing."

    expected_state = {
        'configs': {'type': 'd', 'perms': 0o750},
        'configs/database.conf': {'type': 'f', 'perms': 0o600},
        'data': {'type': 'd', 'perms': 0o700},
        'data/v1': {'type': 'd', 'perms': 0o755},
        'data/active': {'type': 'l', 'target': 'v1'},
        'current_config': {'type': 'l', 'target': 'configs/database.conf'},
    }

    for path, props in expected_state.items():
        full_path = os.path.join(base_dir, path)
        assert os.path.lexists(full_path), f"Path missing: {full_path}"

        if props['type'] == 'd':
            assert os.path.isdir(full_path), f"Expected directory at {full_path}"
            mode = stat.S_IMODE(os.stat(full_path).st_mode)
            assert mode == props['perms'], f"Expected permissions {oct(props['perms'])} for {full_path}, got {oct(mode)}"
        elif props['type'] == 'f':
            assert os.path.isfile(full_path), f"Expected file at {full_path}"
            assert not os.path.islink(full_path), f"Expected regular file at {full_path}, not a symlink"
            mode = stat.S_IMODE(os.stat(full_path).st_mode)
            assert mode == props['perms'], f"Expected permissions {oct(props['perms'])} for {full_path}, got {oct(mode)}"
        elif props['type'] == 'l':
            assert os.path.islink(full_path), f"Expected symlink at {full_path}"
            target = os.readlink(full_path)
            assert target == props['target'], f"Expected symlink {full_path} to point to {props['target']}, got {target}"


def test_verification_log():
    """Verify the contents of the generated log file."""
    log_path = '/home/user/migration_verify.log'
    assert os.path.isfile(log_path), f"Verification log {log_path} is missing."

    expected_log = (
        "d configs 750\n"
        "d data 700\n"
        "d data/v1 755\n"
        "f configs/database.conf 600\n"
        "l current_config 777\n"
        "l data/active 777\n"
        "current_config -> configs/database.conf\n"
        "data/active -> v1\n"
    )

    with open(log_path, 'r') as f:
        actual_log = f.read()

    assert actual_log.strip() == expected_log.strip(), (
        f"Log file contents do not match expected.\n"
        f"Expected:\n{expected_log.strip()}\n\n"
        f"Actual:\n{actual_log.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
