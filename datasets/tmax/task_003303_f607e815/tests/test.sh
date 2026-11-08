#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import uuid


def test_c_program_exists():
    assert os.path.isfile("/home/user/process.c"), "C source file /home/user/process.c does not exist."
    assert os.path.isfile("/home/user/process"), "Compiled executable /home/user/process does not exist."
    assert os.access("/home/user/process", os.X_OK), "Compiled file /home/user/process is not executable."
    with open("/home/user/process", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not a compiled ELF executable."


def test_processed_files_content():
    expected_files = {
        "year_2018.rle": "5A5G5C5T\n2A2T2C2G\n",
        "year_2019.rle": "10G2A\n",
        "year_2020.rle": "5T6A6C3G\n1A1T1C1G\n",
        "year_2021.rle": "16A1T\n"
    }

    processed_dir = "/home/user/processed"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(processed_dir, filename)
        assert os.path.isfile(filepath), f"Expected processed file {filepath} is missing."
        with open(filepath, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content of {filepath} does not match expected RLE output."


def test_backup_hard_links():
    processed_dir = "/home/user/processed"
    backup_dir = "/home/user/backup"

    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    expected_files = ["year_2018.rle", "year_2019.rle", "year_2020.rle", "year_2021.rle"]
    for filename in expected_files:
        processed_path = os.path.join(processed_dir, filename)
        backup_path = os.path.join(backup_dir, filename)
        assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."
        stat_processed = os.stat(processed_path)
        stat_backup = os.stat(backup_path)
        assert stat_processed.st_ino == stat_backup.st_ino, f"{backup_path} is not a hard link to {processed_path} (inodes differ)."


def test_latest_year_symlink():
    symlink_path = "/home/user/latest_year.sym"
    expected_target = "/home/user/processed/year_2021.rle"

    assert os.path.islink(symlink_path), f"{symlink_path} does not exist or is not a symbolic link."
    actual_target = os.readlink(symlink_path)
    if not os.path.isabs(actual_target):
        actual_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), actual_target))
    assert actual_target == expected_target, f"Symlink {symlink_path} points to {actual_target}, expected {expected_target}."


def rle(sequence):
    parts = []
    start = 0
    while start < len(sequence):
        end = start + 1
        while end < len(sequence) and sequence[end] == sequence[start]:
            end += 1
        parts.append(str(end - start) + sequence[start])
        start = end
    return "".join(parts)


def test_executable_and_c_source_process_unseen_input():
    raw_path = "/home/user/raw_sequences.txt"
    processed_dir = "/home/user/processed"
    saved_processed = f"/home/user/.processed_verifier_{uuid.uuid4().hex}"
    compiled_from_source = f"/tmp/process_from_source_{uuid.uuid4().hex}"

    with open(raw_path, "rb") as f:
        original_raw = f.read()

    base = secrets.randbelow(5000) + 3000
    years = [base, base + 7, base + 19]
    rng = random.SystemRandom()
    sequences = [
        "A" * rng.randint(11, 25) + "C" * rng.randint(2, 8) + "G" * rng.randint(10, 20),
        "".join(rng.choice("ACGT") for _ in range(37)),
        "T",
        "G" * rng.randint(3, 9) + "A" * rng.randint(12, 22) + "T" * rng.randint(2, 7),
        "ACGT" * rng.randint(3, 7),
        "C" * rng.randint(14, 30) + "A" + "C" * rng.randint(2, 6),
    ]
    records = [
        (years[1], "R91", sequences[0]),
        (years[0], "R17", sequences[1]),
        (years[2], "R04", sequences[2]),
        (years[1], "R33", sequences[3]),
        (years[0], "R82", sequences[4]),
        (years[2], "R59", sequences[5]),
    ]

    raw_data = "".join(f"{year}-{region}:{sequence}\n" for year, region, sequence in records)
    expected = {}
    for year, _region, sequence in records:
        expected.setdefault(f"year_{year}.rle", "")
        expected[f"year_{year}.rle"] += rle(sequence) + "\n"

    def check_outputs():
        actual_names = sorted(
            name for name in os.listdir(processed_dir)
            if os.path.isfile(os.path.join(processed_dir, name))
        )
        assert actual_names == sorted(expected), f"Unexpected generated files: {actual_names}"
        for name, wanted in expected.items():
            with open(os.path.join(processed_dir, name), "r") as f:
                actual = f.read()
            assert actual == wanted, f"Incorrect dynamically generated content in {name}"

    os.rename(processed_dir, saved_processed)
    try:
        with open(raw_path, "w") as f:
            f.write(raw_data)

        os.mkdir(processed_dir)
        result = subprocess.run(
            ["/home/user/process"], cwd="/home/user", timeout=10,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"/home/user/process failed: {result.stderr}"
        check_outputs()

        shutil.rmtree(processed_dir)
        os.mkdir(processed_dir)
        build = subprocess.run(
            ["gcc", "-std=c11", "/home/user/process.c", "-o", compiled_from_source],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert build.returncode == 0, f"process.c does not compile: {build.stderr}"
        result = subprocess.run(
            [compiled_from_source], cwd="/home/user", timeout=10,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"Executable compiled from process.c failed: {result.stderr}"
        check_outputs()
    finally:
        if os.path.exists(compiled_from_source):
            os.remove(compiled_from_source)
        if os.path.isdir(processed_dir):
            shutil.rmtree(processed_dir)
        if os.path.exists(saved_processed):
            os.rename(saved_processed, processed_dir)
        with open(raw_path, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
