#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest

HOME = "/home/user"
LOG = f"{HOME}/service_status.log"
SOURCE = f"{HOME}/monitor.c"
BINARY = f"{HOME}/monitor"
FSTAB = f"{HOME}/user_fstab"
SETUP = f"{HOME}/setup_env.sh"
WRAPPER = f"{HOME}/start_service.sh"


def run(path, **kwargs):
    return subprocess.run([path], capture_output=True, text=True, timeout=10, **kwargs)


def test_service_status_log_exists():
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."


def test_service_status_log_content():
    with open(LOG, "r") as f:
        content = f.read()

    assert "Monitored mount: /home/user/data_mount with quota 1000" in content, \
        "Log does not contain the correct output for data_mount."
    assert "Monitored mount: /home/user/backup_mount with quota 500" in content, \
        "Log does not contain the correct output for backup_mount."
    assert "Storage monitor initialization complete." in content, \
        "Log does not indicate successful completion of the monitor daemon."


def test_setup_env_idempotent_when_present_and_absent():
    assert os.path.isfile(SETUP), f"Script {SETUP} is missing."

    result = run(SETUP)
    assert result.returncode == 0, \
        f"{SETUP} failed when directories already exist.\nError: {result.stderr}"

    mounts = [f"{HOME}/data_mount", f"{HOME}/backup_mount"]
    backup_root = tempfile.mkdtemp(prefix="mount-backup-", dir="/tmp")
    saved = []
    try:
        for mount in mounts:
            if os.path.lexists(mount):
                destination = os.path.join(backup_root, os.path.basename(mount))
                shutil.move(mount, destination)
                saved.append((mount, destination))

        first = run(SETUP)
        assert first.returncode == 0, \
            f"{SETUP} failed when mount directories were absent.\nError: {first.stderr}"
        for mount in mounts:
            assert os.path.isdir(mount), f"{SETUP} did not create {mount}."

        second = run(SETUP)
        assert second.returncode == 0, \
            f"{SETUP} failed on a repeated invocation.\nError: {second.stderr}"
    finally:
        for mount in mounts:
            if os.path.lexists(mount):
                if os.path.isdir(mount) and not os.path.islink(mount):
                    shutil.rmtree(mount)
                else:
                    os.unlink(mount)
        for mount, saved_path in saved:
            shutil.move(saved_path, mount)
        shutil.rmtree(backup_root, ignore_errors=True)


def test_monitor_compiled_from_source_and_handles_generated_fstab():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    rebuilt = "/tmp/monitor_rebuilt"
    compilation = subprocess.run(
        ["gcc", "-o", rebuilt, SOURCE], capture_output=True, text=True, timeout=20
    )
    assert compilation.returncode == 0, \
        f"{SOURCE} does not compile successfully.\n{compilation.stderr}"

    with open(BINARY, "rb") as submitted, open(rebuilt, "rb") as fresh:
        assert submitted.read() == fresh.read(), \
            f"{BINARY} is not the binary produced by compiling the current {SOURCE}."

    token = uuid.uuid4().hex
    entries = [
        (f"/tmp/generated_{token}_a", 101 + int(token[:2], 16)),
        (f"/tmp/generated_{token}_b", 700 + int(token[2:4], 16)),
        (f"/tmp/generated_{token}_c", 2000 + int(token[4:6], 16)),
    ]
    fixture = (
        "\n"
        f"{entries[0][0]} {entries[0][1]}\n"
        "   \n"
        "\t \t\n"
        f"{entries[1][0]} {entries[1][1]}\n"
        "\n\n"
        f"{entries[2][0]} {entries[2][1]}\n"
        " \t  \n"
    )
    expected = "".join(
        f"Monitored mount: {path} with quota {quota}\n" for path, quota in entries
    ) + "Storage monitor initialization complete.\n"

    with open(FSTAB, "rb") as f:
        original_fstab = f.read()
    try:
        with open(FSTAB, "w") as f:
            f.write(fixture)

        for executable in (BINARY, rebuilt):
            result = run(executable)
            assert result.returncode == 0, \
                f"{executable} crashed or failed on generated blank-line input.\n" \
                f"Return code: {result.returncode}\nStderr: {result.stderr}"
            assert result.stderr == "", f"{executable} wrote unexpected stderr: {result.stderr}"
            assert result.stdout == expected, \
                f"{executable} produced incorrect output for generated input.\n" \
                f"Expected: {expected!r}\nActual: {result.stdout!r}"

        with open(LOG, "w") as log_file:
            wrapped = subprocess.run(
                [WRAPPER], stdout=log_file, stderr=subprocess.STDOUT, text=True, timeout=10
            )
        assert wrapped.returncode == 0, \
            f"{WRAPPER} did not exit successfully; return code {wrapped.returncode}."
        with open(LOG, "r") as f:
            wrapper_output = f.read()
        assert wrapper_output == expected, \
            "The wrapper's redirected log is not the exact output of the monitor daemon.\n" \
            f"Expected: {expected!r}\nActual: {wrapper_output!r}"
        assert wrapper_output.endswith("Storage monitor initialization complete.\n")
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
