#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest


def test_backups_exist():
    """Check if the backup files were created correctly."""
    v1_path = "/home/user/backups/app_v1.txt"
    v2_path = "/home/user/backups/app_v2.txt"

    assert os.path.isfile(v1_path), f"{v1_path} does not exist."
    with open(v1_path, "r") as f:
        assert f.read().strip() == "version 1 backup", f"Incorrect content in {v1_path}"

    assert os.path.isfile(v2_path), f"{v2_path} does not exist."
    with open(v2_path, "r") as f:
        assert f.read().strip() == "version 2 backup", f"Incorrect content in {v2_path}"


def test_rust_script_and_binary_exist():
    """Check if the Rust script and compiled binary exist."""
    rs_path = "/home/user/deploy_restore.rs"
    bin_path = "/home/user/deploy_restore"

    assert os.path.isfile(rs_path), f"{rs_path} does not exist."
    assert os.path.isfile(bin_path), f"{bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a native compiled executable."


def test_active_files_state():
    """Check the state of the files in the active directory after running the script twice."""
    app_path = "/home/user/active/app.txt"
    log_path = "/home/user/active/deploy.log"
    log_old_path = "/home/user/active/deploy.log.old"

    assert os.path.isfile(app_path), f"{app_path} does not exist."
    with open(app_path, "r") as f:
        assert f.read().strip() == "version 2 backup", f"Incorrect content in {app_path}"

    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        assert f.read().strip() == "Deployed v2", f"Incorrect content in {log_path}"

    assert os.path.isfile(log_old_path), f"{log_old_path} does not exist."
    with open(log_old_path, "r") as f:
        assert f.read().strip() == "Deployed v1", f"Incorrect content in {log_old_path}"


def test_cron_configuration():
    """Check if the cron job was installed correctly."""
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed for the current user?")

    pattern = r"0\s+3\s+\*\s+\*\s+\*\s+/home/user/deploy_restore\s+3"
    assert re.search(pattern, crontab_output), f"Crontab does not contain the expected schedule. Got:\n{crontab_output}"


def _exercise(binary, versions):
    backup_dir = "/home/user/backups"
    active_dir = "/home/user/active"
    os.makedirs(backup_dir, exist_ok=True)
    os.makedirs(active_dir, exist_ok=True)

    contents = {}
    for version in versions:
        contents[version] = f"random backup payload {secrets.token_hex(24)}\n"
        with open(os.path.join(backup_dir, f"app_v{version}.txt"), "w") as f:
            f.write(contents[version])

    initial_log = f"preexisting log {secrets.token_hex(16)}\n"
    stale_old = f"stale old log {secrets.token_hex(16)}\n"
    with open(os.path.join(active_dir, "deploy.log"), "w") as f:
        f.write(initial_log)
    with open(os.path.join(active_dir, "deploy.log.old"), "w") as f:
        f.write(stale_old)

    first, second = versions
    result = subprocess.run(
        [binary, first], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"{binary} failed for version {first}: {result.stderr}"
    with open(os.path.join(active_dir, "app.txt"), "r") as f:
        assert f.read() == contents[first]
    with open(os.path.join(active_dir, "deploy.log"), "r") as f:
        assert f.read() == f"Deployed v{first}\n"
    with open(os.path.join(active_dir, "deploy.log.old"), "r") as f:
        assert f.read() == initial_log

    result = subprocess.run(
        [binary, second], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"{binary} failed for version {second}: {result.stderr}"
    with open(os.path.join(active_dir, "app.txt"), "r") as f:
        assert f.read() == contents[second]
    with open(os.path.join(active_dir, "deploy.log"), "r") as f:
        assert f.read() == f"Deployed v{second}\n"
    with open(os.path.join(active_dir, "deploy.log.old"), "r") as f:
        assert f.read() == f"Deployed v{first}\n"


def _random_versions():
    values = set()
    while len(values) < 2:
        value = str(secrets.randbelow(800000000) + 100000000)
        if value not in {"1", "2", "3"}:
            values.add(value)
    return tuple(values)


def test_source_compiles_and_both_compiled_artifacts_behave_correctly():
    """Compile the submitted source and exercise it and the installed binary on unpredictable inputs."""
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "deploy_restore")
        result = subprocess.run(
            ["rustc", "/home/user/deploy_restore.rs", "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Rust source did not compile:\n{result.stderr}"
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        _exercise(rebuilt, _random_versions())
        _exercise("/home/user/deploy_restore", _random_versions())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
