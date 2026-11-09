#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess


def test_clean_new_manifest():
    clean_manifest_path = "/home/user/clean_new_manifest.csv"
    assert os.path.isfile(clean_manifest_path), f"File {clean_manifest_path} is missing."

    with open(clean_manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ART-001,/home/user/storage/vol1/artA.bin,1",
        "ART-002,/home/user/storage/vol1/artB.bin,3",
        "ART-003,/home/user/storage/vol2/artC.bin,1",
        "ART-004,/home/user/storage/vol2/artD.bin,1"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {clean_manifest_path}, got {len(lines)}."
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {clean_manifest_path}."


def test_incremental_backup_directory_contents():
    backup_dir = "/home/user/incremental_backup"
    assert os.path.isdir(backup_dir), f"Directory {backup_dir} is missing."

    files = set(os.listdir(backup_dir))
    expected_files = {"artB.bin", "artD.bin"}

    assert files == expected_files, f"Expected backup directory to contain exactly {expected_files}, but got {files}."

    with open(os.path.join(backup_dir, "artB.bin"), "r") as f:
        assert f.read() == "binarydataB_v2", "Content of artB.bin in backup is incorrect."

    with open(os.path.join(backup_dir, "artD.bin"), "r") as f:
        assert f.read() == "binarydataD_v3", "Content of artD.bin in backup is incorrect."


def test_backup_log_contents():
    log_path = "/home/user/backup_log.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/storage/vol1/artB.bin",
        "/home/user/storage/vol2/artD.bin"
    ]

    assert lines == expected_lines, f"Expected log file lines to be exactly {expected_lines}, but got {lines}."


def _run_dynamic_case(executable):
    token = secrets.token_hex(6)
    vol1 = "/home/user/storage/vol1"
    vol2 = "/home/user/storage/vol2"
    paths = {
        "unchanged": f"{vol1}/verify_{token}_unchanged.bin",
        "updated": f"{vol1}/verify_{token}_updated.bin",
        "downgraded": f"{vol2}/verify_{token}_downgraded.bin",
        "new": f"{vol2}/verify_{token}_new.bin",
    }
    contents = {
        "unchanged": bytes([0, 17, 34, 255, 1]),
        "updated": bytes([9, 0, 8, 7, 200, 6]),
        "downgraded": bytes([5, 4, 3, 2, 1]),
        "new": bytes([255, 0, 128, 64, 32]),
    }
    for key, path in paths.items():
        with open(path, "wb") as f:
            f.write(contents[key])

    ids = {key: f"VERIFY-{token}-{key.upper()}" for key in paths}
    with open("/home/user/old_manifest.csv", "w") as f:
        f.write(f"{ids['unchanged']},{paths['unchanged']},5\n")
        f.write(f"{ids['updated']},{paths['updated']},2\n")
        f.write(f"{ids['downgraded']},{paths['downgraded']},12\n")

    with open("/home/user/clean_new_manifest.csv", "w") as f:
        f.write(f"{ids['new']},{paths['new']},1\n")
        f.write(f"{ids['downgraded']},{paths['downgraded']},7\n")
        f.write(f"{ids['unchanged']},{paths['unchanged']},5\n")
        f.write(f"{ids['updated']},{paths['updated']},11\n")

    backup_dir = "/home/user/incremental_backup"
    shutil.rmtree(backup_dir, ignore_errors=True)
    try:
        os.remove("/home/user/backup_log.txt")
    except FileNotFoundError:
        pass

    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, f"{executable} exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
    assert os.path.isdir(backup_dir), "The C program did not create the incremental backup directory."

    expected_names = {os.path.basename(paths['updated']), os.path.basename(paths['new'])}
    assert set(os.listdir(backup_dir)) == expected_names, "The C program did not select exactly the new and updated artifacts."
    for key in ("updated", "new"):
        with open(os.path.join(backup_dir, os.path.basename(paths[key])), "rb") as f:
            assert f.read() == contents[key], f"Copied content for {key} artifact is incorrect."

    assert os.path.isfile("/home/user/backup_log.txt"), "The C program did not create the backup log."
    with open("/home/user/backup_log.txt", "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]
    assert log_lines == sorted([paths["updated"], paths["new"]]), "The dynamic backup log is incomplete, inaccurate, or unsorted."


def test_c_program_exists_and_performs_differential_backup():
    source = "/home/user/backup_manager.c"
    executable = "/home/user/backup_manager"
    assert os.path.isfile(source), f"File {source} is missing."
    assert os.path.isfile(executable), f"File {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {executable} is not a compiled ELF program."

    rebuilt = f"/tmp/backup_manager_rebuilt_{secrets.token_hex(6)}"
    build = subprocess.run(
        ["gcc", source, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert build.returncode == 0, f"backup_manager.c does not compile: {build.stderr.decode(errors='replace')}"

    _run_dynamic_case(executable)
    _run_dynamic_case(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
