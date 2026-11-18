#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from collections import Counter


def test_executable_exists():
    assert os.path.isfile("/home/user/health_monitor.cpp"), "The C++ source file /home/user/health_monitor.cpp is missing."
    assert os.path.isfile("/home/user/health_monitor"), "The compiled executable /home/user/health_monitor is missing."
    assert os.access("/home/user/health_monitor", os.X_OK), "The file /home/user/health_monitor is not executable."


def test_log_file_contents():
    log_path = "/home/user/health_monitor.log"
    assert os.path.isfile(log_path), f"The log file {log_path} is missing. Did the program run and create it?"

    with open(log_path, "r") as f:
        log_contents = f.read().splitlines()

    assert "RESTORED c2" in log_contents, "Log file is missing the 'RESTORED c2' entry."
    assert "RESTORED c3" in log_contents, "Log file is missing the 'RESTORED c3' entry."
    assert "RESTORED c1" not in log_contents, "Log file incorrectly contains 'RESTORED c1', but c1 was already healthy."


def test_container_statuses():
    containers = ["c1", "c2", "c3"]
    for c in containers:
        status_file = f"/home/user/containers/{c}/status.txt"
        assert os.path.isfile(status_file), f"Status file missing: {status_file}"
        with open(status_file, "r") as f:
            status = f.read().strip()
        assert status == "HEALTHY", f"Container {c} status should be 'HEALTHY', but is '{status}'."


def test_container_data_restored():
    containers = ["c1", "c2", "c3"]
    for c in containers:
        data_file = f"/home/user/containers/{c}/data.bin"
        backup_file = f"/home/user/backups/{c}_data.bin"

        assert os.path.isfile(data_file), f"Data file missing: {data_file}"
        assert os.path.isfile(backup_file), f"Backup file missing: {backup_file}"

        with open(data_file, "r") as f:
            data_content = f.read().strip()

        with open(backup_file, "r") as f:
            backup_content = f.read().strip()

        assert data_content == backup_content, f"Data file for container {c} does not match its backup. Expected '{backup_content}', got '{data_content}'."


def test_zz_dynamic_containers_and_submitted_program():
    source = "/home/user/health_monitor.cpp"
    executable = "/home/user/health_monitor"
    containers_root = "/home/user/containers"
    backups_root = "/home/user/backups"
    log_path = "/home/user/health_monitor.log"

    # Rebuild the demanded executable from the submitted source, then exercise it.
    result = subprocess.run(
        ["g++", "-std=c++17", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Submitted C++ source did not compile:\n{result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    token = uuid.uuid4().hex
    unhealthy = [f"dyn_unhealthy_{token}_a", f"dyn_unhealthy_{token}_b"]
    healthy = f"dyn_healthy_{token}"
    no_status = f"dyn_no_status_{token}"

    expected_payloads = {}
    for index, container_id in enumerate(unhealthy):
        container_dir = os.path.join(containers_root, container_id)
        os.makedirs(container_dir)
        original = f"corrupt-{token}-{index}".encode()
        backup = (f"restored-{token}-{index}-".encode() + os.urandom(31))
        with open(os.path.join(container_dir, "status.txt"), "wb") as f:
            f.write(b"UNHEALTHY\n")
        with open(os.path.join(container_dir, "data.bin"), "wb") as f:
            f.write(original)
        with open(os.path.join(backups_root, container_id + "_data.bin"), "wb") as f:
            f.write(backup)
        expected_payloads[container_id] = backup

    healthy_dir = os.path.join(containers_root, healthy)
    os.makedirs(healthy_dir)
    healthy_original = (f"healthy-original-{token}-".encode() + os.urandom(19))
    with open(os.path.join(healthy_dir, "status.txt"), "wb") as f:
        f.write(b"HEALTHY\n")
    with open(os.path.join(healthy_dir, "data.bin"), "wb") as f:
        f.write(healthy_original)
    with open(os.path.join(backups_root, healthy + "_data.bin"), "wb") as f:
        f.write(b"backup-must-not-replace-healthy-data-" + os.urandom(17))

    no_status_dir = os.path.join(containers_root, no_status)
    os.makedirs(no_status_dir)
    no_status_original = b"skip-this-directory-" + os.urandom(23)
    with open(os.path.join(no_status_dir, "data.bin"), "wb") as f:
        f.write(no_status_original)
    with open(os.path.join(backups_root, no_status + "_data.bin"), "wb") as f:
        f.write(b"unused-backup-" + os.urandom(13))

    # A known prefix verifies that entries are appended rather than replacing the log.
    prefix = b"PREEXISTING LOG ENTRY\n"
    with open(log_path, "wb") as f:
        f.write(prefix)

    run = subprocess.run(
        [executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert run.returncode == 0, (
        f"health_monitor exited with {run.returncode}; "
        f"stderr={run.stderr.decode(errors='replace')}"
    )

    for container_id in unhealthy:
        container_dir = os.path.join(containers_root, container_id)
        with open(os.path.join(container_dir, "status.txt"), "r") as f:
            assert f.read().strip() == "HEALTHY"
        with open(os.path.join(container_dir, "data.bin"), "rb") as f:
            assert f.read() == expected_payloads[container_id]

    with open(os.path.join(healthy_dir, "status.txt"), "r") as f:
        assert f.read().strip() == "HEALTHY"
    with open(os.path.join(healthy_dir, "data.bin"), "rb") as f:
        assert f.read() == healthy_original, "Healthy container data was incorrectly overwritten."
    with open(os.path.join(no_status_dir, "data.bin"), "rb") as f:
        assert f.read() == no_status_original, "Directory lacking status.txt was not skipped."

    with open(log_path, "rb") as f:
        complete_log = f.read()
    assert complete_log.startswith(prefix), "The monitor replaced the log instead of appending to it."
    appended = complete_log[len(prefix):].decode("utf-8").splitlines()
    expected_lines = [f"RESTORED {container_id}" for container_id in unhealthy]
    assert Counter(appended) == Counter(expected_lines), (
        f"Expected exactly the dynamic restore entries {expected_lines}, got {appended}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
