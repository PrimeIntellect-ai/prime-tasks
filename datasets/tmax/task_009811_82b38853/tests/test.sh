#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile

import pytest

SCRIPT_PATH = "/home/user/config_tracker.py"
MANIFEST_PATH = "/home/user/manifest.json"
LOG_PATH = "/home/user/modified.log"
CONFIG_DIR = "/home/user/configs"
BACKUP_DIR = "/home/user/backups"
BACKUP_PATH = "/home/user/backups/backup_v1.tar.gz"


def get_sha256(content):
    if isinstance(content, str):
        content = content.encode("utf-8")
    return hashlib.sha256(content).hexdigest()


def reset_dir(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    os.makedirs(path)


def tar_gz_bytes(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, content in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


def zip_bytes(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(name, content)
    return output.getvalue()


def install_fixture(backup_members, live_files):
    reset_dir(CONFIG_DIR)
    reset_dir(BACKUP_DIR)
    with open(BACKUP_PATH, "wb") as f:
        f.write(tar_gz_bytes(backup_members))
    for name, content in live_files.items():
        with open(os.path.join(CONFIG_DIR, name), "wb") as f:
            f.write(content)
    for output in (MANIFEST_PATH, LOG_PATH):
        if os.path.lexists(output):
            if os.path.isdir(output) and not os.path.islink(output):
                shutil.rmtree(output)
            else:
                os.unlink(output)


def run_script():
    assert os.path.lexists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular Python script."
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_manifest():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."
    with open(MANIFEST_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")


def read_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="module")
def original_run():
    app = b"port=8080"
    db = b"host=localhost"
    nginx = b"worker_processes 1;"
    install_fixture(
        {
            "app.zip": zip_bytes({"app.conf": app}),
            "db.tar.gz": tar_gz_bytes({"db.conf": db}),
            "nginx.conf": nginx,
        },
        {
            "app.conf": app,
            "db.conf": b"host=127.0.0.1",
            "nginx.conf": nginx,
            "new.conf": b"mode=prod",
        },
    )
    run_script()


def test_manifest_json(original_run):
    manifest_data = read_manifest()
    expected_manifest = {
        "app.conf": get_sha256("port=8080"),
        "db.conf": get_sha256("host=localhost"),
        "nginx.conf": get_sha256("worker_processes 1;"),
    }
    assert manifest_data == expected_manifest, (
        f"Manifest data is incorrect. Expected {expected_manifest}, but got {manifest_data}."
    )


def test_modified_log(original_run):
    lines = read_log()
    expected_lines = ["db.conf", "new.conf"]
    assert lines == expected_lines, (
        f"Modified log is incorrect. Expected {expected_lines}, but got {lines}. "
        "Ensure the output is sorted alphabetically and contains only modified or new files."
    )


def test_processes_generated_nested_archives():
    token = secrets.token_hex(6)
    root_name = f"root_{token}.conf"
    zip_name = f"zip_{token}.conf"
    tar_name = f"tar_{token}.conf"
    new_name = f"new_{token}.conf"

    root_content = secrets.token_bytes(31)
    zip_content = secrets.token_bytes(37)
    tar_content = secrets.token_bytes(43)
    modified_zip_content = secrets.token_bytes(41)
    new_content = secrets.token_bytes(47)

    install_fixture(
        {
            f"plain/path/{root_name}": root_content,
            f"bundle_{token}.zip": zip_bytes({f"inside/zip/{zip_name}": zip_content}),
            f"bundle_{token}.tar.gz": tar_gz_bytes({f"inside/tar/{tar_name}": tar_content}),
            f"ignored_{token}.txt": b"not a configuration file",
        },
        {
            root_name: root_content,
            zip_name: modified_zip_content,
            tar_name: tar_content,
            new_name: new_content,
        },
    )
    run_script()

    expected_manifest = {
        root_name: get_sha256(root_content),
        zip_name: get_sha256(zip_content),
        tar_name: get_sha256(tar_content),
    }
    manifest_data = read_manifest()
    assert manifest_data == expected_manifest, (
        f"Generated-fixture manifest is incorrect. Expected {expected_manifest}, "
        f"but got {manifest_data}."
    )

    expected_lines = sorted([zip_name, new_name])
    lines = read_log()
    assert lines == expected_lines, (
        f"Generated-fixture modified log is incorrect. Expected {expected_lines}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
