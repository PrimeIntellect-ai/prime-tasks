#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import sys
import uuid

import pytest

MANIFEST_PATH = "/home/user/manifests/vms.json"
BACKUP_PATH = "/home/user/backup/vms.json.bak"
RUNNERS_DIR = "/home/user/runners"
LOG_PATH = "/home/user/operator_state.log"
OPERATOR_PATH = "/home/user/vm_operator.py"


def clean_outputs():
    for path in ("/home/user/backup", RUNNERS_DIR):
        if os.path.lexists(path):
            if os.path.islink(path) or not os.path.isdir(path):
                os.unlink(path)
            else:
                shutil.rmtree(path)
    if os.path.lexists(LOG_PATH):
        if os.path.isdir(LOG_PATH) and not os.path.islink(LOG_PATH):
            shutil.rmtree(LOG_PATH)
        else:
            os.unlink(LOG_PATH)


def run_operator():
    result = subprocess.run(
        [sys.executable, OPERATOR_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Operator exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_operator():
    assert os.path.exists(OPERATOR_PATH), f"Operator script {OPERATOR_PATH} does not exist"
    assert os.path.isfile(OPERATOR_PATH), f"Operator path {OPERATOR_PATH} is not a regular file"
    assert not os.path.islink(OPERATOR_PATH), f"Operator path {OPERATOR_PATH} must not be a symlink"
    clean_outputs()
    run_operator()


def test_backup_created_and_identical():
    assert os.path.exists(BACKUP_PATH), f"Backup file {BACKUP_PATH} does not exist"
    assert os.path.exists(MANIFEST_PATH), f"Original manifest {MANIFEST_PATH} is missing"

    with open(MANIFEST_PATH, 'r') as f_orig, open(BACKUP_PATH, 'r') as f_bak:
        orig_content = f_orig.read()
        bak_content = f_bak.read()

    assert orig_content == bak_content, "Backup content does not match the original manifest"


def test_web_server_runner():
    runner_path = os.path.join(RUNNERS_DIR, "web-server.sh")
    assert os.path.exists(runner_path), f"Runner script {runner_path} does not exist"
    assert os.access(runner_path, os.X_OK), f"Runner script {runner_path} is not executable"

    with open(runner_path, 'r') as f:
        content = f.read().strip()

    expected_command = "qemu-system-x86_64 -m 2G -hda /home/user/images/web.img -vnc :1"
    assert content == expected_command, f"Incorrect content in {runner_path}. Expected: '{expected_command}', but got: '{content}'"


def test_db_server_runner():
    runner_path = os.path.join(RUNNERS_DIR, "db-server.sh")
    assert os.path.exists(runner_path), f"Runner script {runner_path} does not exist"
    assert os.access(runner_path, os.X_OK), f"Runner script {runner_path} is not executable"

    with open(runner_path, 'r') as f:
        content = f.read().strip()

    expected_command = "qemu-system-x86_64 -m 4G -hda /home/user/images/db.img -vnc :0"
    assert content == expected_command, f"Incorrect content in {runner_path}. Expected: '{expected_command}', but got: '{content}'"


def test_cache_server_runner_not_created():
    runner_path = os.path.join(RUNNERS_DIR, "cache-server.sh")
    assert not os.path.exists(runner_path), f"Runner script {runner_path} should not exist due to missing image"


def test_operator_state_log():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist"

    with open(LOG_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "[SUCCESS] Created runner for web-server",
        "[SUCCESS] Created runner for db-server",
        "[ERROR] Missing image for cache-server"
    ]

    assert lines == expected_lines, f"Log file content is incorrect. Expected {expected_lines}, got {lines}"


def test_operator_processes_unseen_manifest():
    with open(MANIFEST_PATH, "rb") as f:
        original_manifest = f.read()

    token = uuid.uuid4().hex
    default_name = f"default-{token[:10]}"
    custom_name = f"custom-{token[10:20]}"
    missing_name = f"missing-{token[20:30]}"
    custom_port = 5901 + (int(token[:8], 16) % 80)
    default_memory = f"{3 + (int(token[8:10], 16) % 20)}G"
    custom_memory = f"{24 + (int(token[10:12], 16) % 20)}G"
    default_image = f"/tmp/{token}-default.img"
    custom_image = f"/tmp/{token}-custom.img"

    manifest = {
        "vms": [
            {
                "name": default_name,
                "memory": default_memory,
                "image": default_image,
            },
            {
                "name": custom_name,
                "memory": custom_memory,
                "vnc_port": custom_port,
                "image": custom_image,
            },
            {
                "name": missing_name,
                "memory": "7G",
                "vnc_port": 5917,
            },
        ]
    }
    alternate_bytes = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")

    try:
        clean_outputs()
        with open(MANIFEST_PATH, "wb") as f:
            f.write(alternate_bytes)

        run_operator()

        assert os.path.isfile(BACKUP_PATH), "Alternate manifest backup was not created"
        with open(BACKUP_PATH, "rb") as f:
            assert f.read() == alternate_bytes, "Alternate manifest was not backed up exactly"
        with open(MANIFEST_PATH, "rb") as f:
            assert f.read() == alternate_bytes, "Operator modified the source manifest"

        expected_runners = {
            f"{default_name}.sh": (
                f"qemu-system-x86_64 -m {default_memory} -hda {default_image} -vnc :0"
            ),
            f"{custom_name}.sh": (
                f"qemu-system-x86_64 -m {custom_memory} -hda {custom_image} "
                f"-vnc :{custom_port - 5900}"
            ),
        }
        assert os.path.isdir(RUNNERS_DIR), "Runners directory was not created"
        assert set(os.listdir(RUNNERS_DIR)) == set(expected_runners), (
            "Runner set does not match the alternate manifest"
        )
        for filename, expected_command in expected_runners.items():
            runner_path = os.path.join(RUNNERS_DIR, filename)
            assert os.path.isfile(runner_path), f"{runner_path} is not a regular file"
            assert os.access(runner_path, os.X_OK), f"{runner_path} is not executable"
            with open(runner_path, "r") as f:
                content = f.read().strip()
            assert content == expected_command, (
                f"Incorrect dynamic runner content: expected {expected_command!r}, got {content!r}"
            )

        assert not os.path.exists(os.path.join(RUNNERS_DIR, f"{missing_name}.sh")), (
            "A runner was created for a VM with no image"
        )
        with open(LOG_PATH, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        expected_lines = [
            f"[SUCCESS] Created runner for {default_name}",
            f"[SUCCESS] Created runner for {custom_name}",
            f"[ERROR] Missing image for {missing_name}",
        ]
        assert lines == expected_lines, (
            f"Dynamic log content is incorrect. Expected {expected_lines}, got {lines}"
        )
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
