#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/operator_sync.py"
RAW_MANIFESTS_DIR = "/home/user/raw_manifests"
STRUCTURED_MANIFESTS_DIR = "/home/user/structured_manifests"
LOG_FILE = "/home/user/operator_status.log"
FSTAB_FILE = "/home/user/k8s_backup_fstab"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_symlinks_created():
    deployment_link = os.path.join(STRUCTURED_MANIFESTS_DIR, "Deployment", "app-deployment.yaml")
    service_link = os.path.join(STRUCTURED_MANIFESTS_DIR, "Service", "app-service.yaml")

    assert os.path.islink(deployment_link), f"{deployment_link} is not a symlink."
    assert os.readlink(deployment_link) == os.path.join(RAW_MANIFESTS_DIR, "app-deployment.yaml"), \
        f"{deployment_link} does not point to the correct raw manifest."

    assert os.path.islink(service_link), f"{service_link} is not a symlink."
    assert os.readlink(service_link) == os.path.join(RAW_MANIFESTS_DIR, "app-service.yaml"), \
        f"{service_link} does not point to the correct raw manifest."


def test_log_file_content():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."

    total_size = sum(
        os.path.getsize(os.path.join(RAW_MANIFESTS_DIR, f))
        for f in os.listdir(RAW_MANIFESTS_DIR)
        if os.path.isfile(os.path.join(RAW_MANIFESTS_DIR, f))
    )
    expected_status = "QUOTA EXCEEDED" if total_size > 1024 else "QUOTA OK"

    with open(LOG_FILE, "r") as f:
        lines = f.readlines()

    assert lines, f"Log file {LOG_FILE} is empty."
    assert lines[-1] == expected_status + "\n", \
        f"Last log entry must be exactly '{expected_status}' followed by a newline."


def test_cron_job_configured():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab. Is it configured?")

    valid = False
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split(None, 5)
        if len(fields) != 6 or fields[:5] != ["*/5", "*", "*", "*", "*"]:
            continue
        try:
            command = shlex.split(fields[5])
        except ValueError:
            continue
        if not command:
            continue
        if command[0] == SCRIPT_PATH:
            valid = os.access(SCRIPT_PATH, os.X_OK)
        elif (re.fullmatch(r"python3(?:\.\d+)?", os.path.basename(command[0]))
              and len(command) >= 2 and command[1] == SCRIPT_PATH
              and shutil.which(command[0]) is not None):
            valid = True
        if valid:
            break

    assert valid, "No every-five-minutes cron entry actually invokes /home/user/operator_sync.py."


def test_fstab_file_content():
    assert os.path.isfile(FSTAB_FILE), f"File {FSTAB_FILE} does not exist."
    with open(FSTAB_FILE, "r") as f:
        content = f.read().strip()
    expected_line = "/dev/sdc1 /home/user/structured_manifests ext4 defaults,usrquota 0 2"
    assert content == expected_line, \
        f"Content of {FSTAB_FILE} is incorrect. Expected: '{expected_line}', Got: '{content}'"


def _assert_all_manifest_links():
    for name in os.listdir(RAW_MANIFESTS_DIR):
        if not name.endswith(".yaml"):
            continue
        source = os.path.join(RAW_MANIFESTS_DIR, name)
        kind = None
        with open(source, "r") as f:
            for line in f:
                if line.startswith("kind: "):
                    kind = line[len("kind: "):].strip()
                    break
        assert kind is not None, f"Test manifest {name} has no kind."
        link = os.path.join(STRUCTURED_MANIFESTS_DIR, kind, name)
        assert os.path.islink(link), f"Script did not create symlink {link}."
        assert os.readlink(link) == source, f"{link} does not point to {source}."


def test_script_handles_runtime_changes_and_quota_boundary():
    kind_one = "Kind" + secrets.token_hex(6)
    changed_kind = "Kind" + secrets.token_hex(6)
    kind_two = "Kind" + secrets.token_hex(6)
    name_one = "dynamic-" + secrets.token_hex(6) + ".yaml"
    name_two = "added-" + secrets.token_hex(6) + ".yaml"

    with tempfile.TemporaryDirectory() as td:
        saved_raw = os.path.join(td, "raw")
        saved_structured = os.path.join(td, "structured")
        saved_log = os.path.join(td, "status.log")
        had_structured = os.path.lexists(STRUCTURED_MANIFESTS_DIR)
        had_log = os.path.lexists(LOG_FILE)

        os.rename(RAW_MANIFESTS_DIR, saved_raw)
        if had_structured:
            os.rename(STRUCTURED_MANIFESTS_DIR, saved_structured)
        if had_log:
            os.rename(LOG_FILE, saved_log)

        try:
            os.mkdir(RAW_MANIFESTS_DIR)
            first = os.path.join(RAW_MANIFESTS_DIR, name_one)
            with open(first, "w") as f:
                f.write(f"apiVersion: v1\nmetadata:\n  kind: ignored\nkind: {kind_one}\n")

            current_size = sum(
                os.path.getsize(os.path.join(RAW_MANIFESTS_DIR, n))
                for n in os.listdir(RAW_MANIFESTS_DIR)
                if os.path.isfile(os.path.join(RAW_MANIFESTS_DIR, n))
            )
            assert current_size < 1024
            with open(os.path.join(RAW_MANIFESTS_DIR, "boundary.bin"), "wb") as f:
                f.write(b"x" * (1024 - current_size))
            with open(LOG_FILE, "w") as f:
                f.write("PREEXISTING\n")

            subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=15)
            _assert_all_manifest_links()
            with open(LOG_FILE, "r") as f:
                assert f.read() == "PREEXISTING\nQUOTA OK\n"

            with open(first, "w") as f:
                f.write(f"apiVersion: v1\nmetadata:\n  kind: ignored\nkind: {changed_kind}\n")
            with open(os.path.join(RAW_MANIFESTS_DIR, name_two), "w") as f:
                f.write(f"apiVersion: v1\nkind: {kind_two}\nmetadata:\n  name: added\n")

            if os.path.lexists(STRUCTURED_MANIFESTS_DIR):
                shutil.rmtree(STRUCTURED_MANIFESTS_DIR)

            total_size = sum(
                os.path.getsize(os.path.join(RAW_MANIFESTS_DIR, n))
                for n in os.listdir(RAW_MANIFESTS_DIR)
                if os.path.isfile(os.path.join(RAW_MANIFESTS_DIR, n))
            )
            assert total_size > 1024

            subprocess.run(["python3", SCRIPT_PATH], check=True, timeout=15)
            _assert_all_manifest_links()
            with open(LOG_FILE, "r") as f:
                assert f.read() == "PREEXISTING\nQUOTA OK\nQUOTA EXCEEDED\n"
        finally:
            if os.path.lexists(RAW_MANIFESTS_DIR):
                shutil.rmtree(RAW_MANIFESTS_DIR)
            os.rename(saved_raw, RAW_MANIFESTS_DIR)

            if os.path.lexists(STRUCTURED_MANIFESTS_DIR):
                shutil.rmtree(STRUCTURED_MANIFESTS_DIR)
            if had_structured:
                os.rename(saved_structured, STRUCTURED_MANIFESTS_DIR)

            if os.path.lexists(LOG_FILE):
                os.remove(LOG_FILE)
            if had_log:
                os.rename(saved_log, LOG_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
