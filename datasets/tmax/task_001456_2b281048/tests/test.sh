#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile


def assert_max_compression_header(path):
    with open(path, "rb") as f:
        header = f.read(10)
    assert len(header) >= 10 and header[:3] == bytes((0x1F, 0x8B, 0x08)), "Archive is not gzip data"
    assert header[8] == 2, "Gzip header does not indicate maximum compression"


def test_backup_archive_exists_and_compressed():
    backup_path = "/home/user/archived_logs/backup.tar.gz"
    assert os.path.exists(backup_path), f"Backup archive not found at {backup_path}"
    assert os.path.isfile(backup_path), f"Backup path {backup_path} is not a file"

    file_size = os.path.getsize(backup_path)
    threshold = 25000
    assert file_size <= threshold, (
        f"Backup archive size is {file_size} bytes, which exceeds the threshold of {threshold} bytes. "
        "Make sure you are using gzip.BestCompression."
    )
    assert_max_compression_header(backup_path)

    expected_line = b"INFO: system is running normally at timestamp 2023-10-10 with no errors observed.\n"
    expected_data = expected_line * 20000
    expected_names = {f"app_{i}.log" for i in range(1, 6)}

    with tarfile.open(backup_path, "r:gz") as archive:
        regular_members = [m for m in archive.getmembers() if m.isfile()]
        archived_names = [os.path.basename(m.name) for m in regular_members]
        assert len(archived_names) == len(set(archived_names)), "Archive contains duplicate log names"
        assert set(archived_names) == expected_names, (
            f"Archive contents are incorrect: {archived_names}"
        )
        for member in regular_members:
            extracted = archive.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected_data, f"Archived content for {member.name} is incorrect"


def test_health_log_updated():
    health_log_path = "/home/user/health.log"
    assert os.path.exists(health_log_path), f"Health log not found at {health_log_path}"

    with open(health_log_path, "r") as f:
        content = f.read()

    assert "HEALTH CHECK: OK" in content, "Health log does not contain 'HEALTH CHECK: OK'"


def test_active_logs_empty():
    active_logs_dir = "/home/user/active_logs"
    assert os.path.exists(active_logs_dir), f"Active logs directory {active_logs_dir} is missing"

    files = os.listdir(active_logs_dir)
    log_files = [f for f in files if f.endswith(".log")]
    assert len(log_files) == 0, f"Active logs directory is not empty, found: {log_files}"


def test_crontab_content():
    crontab_path = "/home/user/final_crontab.txt"
    assert os.path.exists(crontab_path), f"Crontab file not found at {crontab_path}"

    with open(crontab_path, "r") as f:
        content = f.read()

    expected_path = "PATH=/usr/local/go/bin:/usr/bin:/bin:/home/user/log_manager/bin"
    assert expected_path in content, f"Crontab does not contain the correct PATH variable. Expected: {expected_path}"

    expected_cron = "*/15 * * * *"
    assert expected_cron in content, f"Crontab does not contain the correct schedule. Expected: {expected_cron}"

    assert "ACTIVE_LOGS=/home/user/active_logs" in content, "Crontab missing ACTIVE_LOGS environment variable"
    assert "BACKUP_DIR=/home/user/archived_logs" in content, "Crontab missing BACKUP_DIR environment variable"
    assert "/home/user/log_manager/bin/log_manager" in content, "Crontab missing the correct binary path execution"


def test_deployment_script_exists_and_is_valid_bash():
    deploy_path = "/home/user/deploy.sh"
    assert os.path.exists(deploy_path), f"Deployment script not found at {deploy_path}"
    assert os.path.isfile(deploy_path), f"{deploy_path} is not a file"
    result = subprocess.run(["bash", "-n", deploy_path], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.sh is not valid bash: {result.stderr}"


def test_go_binary_compiled():
    binary_path = "/home/user/log_manager/bin/log_manager"
    assert os.path.exists(binary_path), f"Compiled Go binary not found at {binary_path}"
    assert os.path.isfile(binary_path), f"{binary_path} is not a file"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled binary is not an ELF executable"
    result = subprocess.run(["go", "version", "-m", binary_path], capture_output=True, text=True)
    assert result.returncode == 0 and re.search(r"\bgo1\.\d+", result.stdout), (
        "Binary does not contain Go build information"
    )


def test_go_source_uses_required_compression_libraries():
    source_path = "/home/user/log_manager/main.go"
    assert os.path.isfile(source_path), f"Go source not found at {source_path}"
    with open(source_path, "r") as f:
        source = f.read()
    assert "archive/tar" in source, "Go source does not use archive/tar"
    assert "compress/gzip" in source, "Go source does not use compress/gzip"
    assert "gzip.BestCompression" in source, "Go source does not request gzip.BestCompression"


def test_binary_behavior_on_fresh_inputs():
    binary_path = "/home/user/log_manager/bin/log_manager"
    health_path = "/home/user/health.log"
    with open(health_path, "rb") as f:
        health_before = f.read()

    with tempfile.TemporaryDirectory(prefix="verify-log-manager-") as root:
        active = os.path.join(root, "active")
        backup = os.path.join(root, "backup")
        os.mkdir(active)

        token = os.urandom(24).hex()
        expected = {
            f"alpha_{token[:8]}.log": (f"alpha:{token}\n" * 137).encode(),
            f"beta_{token[8:16]}.log": (f"beta:{token[::-1]}\n" * 89).encode(),
        }
        for name, data in expected.items():
            with open(os.path.join(active, name), "wb") as f:
                f.write(data)
        marker_name = f"keep_{token[16:24]}.txt"
        marker_data = os.urandom(73)
        with open(os.path.join(active, marker_name), "wb") as f:
            f.write(marker_data)

        env = os.environ.copy()
        env["ACTIVE_LOGS"] = active
        env["BACKUP_DIR"] = backup
        result = subprocess.run(
            [binary_path], env=env, capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"log_manager failed on fresh inputs: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        archive_path = os.path.join(backup, "backup.tar.gz")
        assert os.path.isfile(archive_path), "Binary did not create backup.tar.gz in BACKUP_DIR"
        assert_max_compression_header(archive_path)

        with tarfile.open(archive_path, "r:gz") as archive:
            members = [m for m in archive.getmembers() if m.isfile()]
            names = [os.path.basename(m.name) for m in members]
            assert len(names) == len(set(names)), "Fresh archive contains duplicate files"
            assert set(names) == set(expected), f"Fresh archive has incorrect files: {names}"
            for member in members:
                extracted = archive.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected[os.path.basename(member.name)]

        for name in expected:
            assert not os.path.exists(os.path.join(active, name)), f"Original log {name} was not deleted"
        with open(os.path.join(active, marker_name), "rb") as f:
            assert f.read() == marker_data, "Binary modified or removed a non-log file"

    with open(health_path, "rb") as f:
        health_after = f.read()
    assert health_after == health_before + b"HEALTH CHECK: OK\n", (
        "Successful execution did not append exactly one health-check line"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
