#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile
import uuid


def test_deploy_metadata_csv():
    csv_path = "/home/user/deploy_metadata.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    # Compute expected entry point dynamically
    bin_path = "/home/user/app_v1.bin"
    assert os.path.exists(bin_path), f"File {bin_path} is missing."
    result = subprocess.run(
        ["readelf", "-h", bin_path],
        capture_output=True, text=True, check=True
    )
    entry_point = ""
    for line in result.stdout.splitlines():
        if "Entry point address:" in line:
            entry_point = line.split(":", 1)[1].strip()
            break
    assert entry_point, "Could not extract entry point from ELF binary."

    expected_rows = [
        ["FilePath", "FileType", "Metadata"],
        ["/home/user/app_v1.bin", "ELF", entry_point],
        ["/home/user/local_db.wal", "WAL", "377f0682"],
        ["/home/user/part_a.gcode", "GCODE", "135"]
    ]

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, f"CSV content does not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"


def test_deploy_manifest_sha256():
    manifest_path = "/home/user/deploy_manifest.sha256"
    assert os.path.exists(manifest_path), f"File {manifest_path} does not exist."

    files_to_hash = [
        "/home/user/app_v1.bin",
        "/home/user/local_db.wal",
        "/home/user/part_a.gcode"
    ]

    expected_lines = []
    for filepath in files_to_hash:
        assert os.path.exists(filepath), f"File {filepath} is missing."
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_lines.append(f"{file_hash}  {filepath}")

    expected_lines.sort(key=lambda x: x.split("  ")[1])

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Manifest content does not match expected output.\nExpected: {expected_lines}\nActual: {actual_lines}"


def _file_state(path):
    st = os.stat(path)
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid


def test_script_exists_executes_and_analyzes_fresh_inputs_without_mutation():
    script_path = "/home/user/config_tracker.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."
    assert not os.path.islink(script_path), f"{script_path} must not be a symbolic link."

    syntax = subprocess.run(
        ["bash", "-n", script_path], capture_output=True, text=True
    )
    assert syntax.returncode == 0, f"Bash syntax check failed:\n{syntax.stderr}"

    token = uuid.uuid4().hex
    elf_path = f"/home/user/challenge_{token}.bin"
    gcode_path = f"/home/user/challenge_{token}.gcode"
    wal_path = f"/home/user/challenge_{token}.wal"
    failed_path = f"/home/user/failed_{token}.gcode"
    source_path = f"/tmp/challenge_{token}.c"

    managed_paths = [
        "/home/user/deploy.log",
        "/home/user/deploy_metadata.csv",
        "/home/user/deploy_manifest.sha256",
        "/home/user/app_v1.bin",
        "/home/user/local_db.wal",
        "/home/user/part_a.gcode",
        "/home/user/bad.bin",
    ]
    backup_dir = tempfile.mkdtemp(prefix="tracker-backup-")
    backups = {}

    try:
        for path in managed_paths:
            assert os.path.exists(path), f"Required fixture {path} is missing."
            assert not os.path.islink(path), f"Required fixture {path} must not be a symlink."
            backup = os.path.join(backup_dir, os.path.basename(path))
            shutil.copy2(path, backup)
            backups[path] = backup

        with open(source_path, "w") as f:
            f.write(f"volatile unsigned long marker_{token} = 0x5a17UL;\nint main(void) {{ return (int)(marker_{token} & 0); }}\n")
        subprocess.run(["gcc", "-o", elf_path, source_path], check=True)

        hours = 3
        minutes = 17
        seconds = 49
        with open(gcode_path, "w") as f:
            f.write("; FLAVOR:Marlin\n")
            f.write(f"; estimated printing time = {hours}h {minutes}m {seconds}s\n")
            f.write("G90\nM82\nG28\n")

        wal_magic = os.urandom(4)
        with open(wal_path, "wb") as f:
            f.write(wal_magic + os.urandom(28))

        with open(failed_path, "w") as f:
            f.write("; estimated printing time = 99h 59m 59s\n")

        for path in (elf_path, gcode_path, wal_path, failed_path):
            os.chown(path, 1000, 1000)
            os.chmod(path, 0o644)

        challenge_log = f"""=== DEPLOYMENT ===
Date: 2026-01-01
Status: SUCCESS
File: {wal_path}
User: system

=== DEPLOYMENT ===
Date: 2026-01-02
Status: FAILED
File: {failed_path}
User: operator

=== DEPLOYMENT ===
Date: 2026-01-03
Status: SUCCESS
File: {elf_path}
User: admin

=== DEPLOYMENT ===
Date: 2026-01-04
Status: SUCCESS
File: {gcode_path}
User: operator
"""
        with open("/home/user/deploy.log", "w") as f:
            f.write(challenge_log)
        os.chown("/home/user/deploy.log", 1000, 1000)
        os.chmod("/home/user/deploy.log", 0o777)

        protected_paths = [
            "/home/user/app_v1.bin",
            "/home/user/local_db.wal",
            "/home/user/part_a.gcode",
            "/home/user/bad.bin",
            elf_path,
            gcode_path,
            wal_path,
            failed_path,
        ]
        before = {path: _file_state(path) for path in protected_paths}

        run = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", script_path],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "HOME": "/home/user"},
        )
        assert run.returncode == 0, (
            f"Executing {script_path} failed with status {run.returncode}.\n"
            f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        )

        after = {path: _file_state(path) for path in protected_paths}
        assert after == before, "The script changed the contents, permissions, or ownership of deployed files."

        readelf = subprocess.run(
            ["readelf", "-h", elf_path], capture_output=True, text=True, check=True
        )
        entry_point = ""
        for line in readelf.stdout.splitlines():
            if "Entry point address:" in line:
                entry_point = line.split(":", 1)[1].strip()
                break
        assert entry_point, "Could not derive the challenge ELF entry point."

        expected_rows = [
            ["FilePath", "FileType", "Metadata"],
            [elf_path, "ELF", entry_point],
            [gcode_path, "GCODE", str(hours * 60 + minutes)],
            [wal_path, "WAL", wal_magic.hex()],
        ]
        expected_rows[1:] = sorted(expected_rows[1:], key=lambda row: row[0])

        with open("/home/user/deploy_metadata.csv", newline="") as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows, (
            f"Script did not analyze the fresh deployment log correctly.\n"
            f"Expected: {expected_rows}\nActual: {actual_rows}"
        )

        expected_manifest = []
        for path in sorted((elf_path, gcode_path, wal_path)):
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            expected_manifest.append(f"{digest}  {path}")

        with open("/home/user/deploy_manifest.sha256") as f:
            actual_manifest = [line.rstrip("\n") for line in f if line.strip()]
        assert actual_manifest == expected_manifest, (
            f"Script did not generate the fresh manifest correctly.\n"
            f"Expected: {expected_manifest}\nActual: {actual_manifest}"
        )
    finally:
        for path, backup in backups.items():
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            shutil.copy2(backup, path)
        for path in (elf_path, gcode_path, wal_path, failed_path, source_path):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
