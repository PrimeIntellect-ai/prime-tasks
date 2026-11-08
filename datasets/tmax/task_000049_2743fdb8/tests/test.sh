#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile


def test_c_program_exists():
    source = "/home/user/queue_parser.c"
    assert os.path.isfile(source), "C program /home/user/queue_parser.c is missing."
    assert stat.S_ISREG(os.stat(source).st_mode), f"{source} must be a regular file."


def test_targets_txt():
    targets_file = "/home/user/targets.txt"
    assert os.path.isfile(targets_file), f"{targets_file} is missing."

    with open(targets_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_paths = {"/home/user/data/dir_alpha", "/home/user/data/dir_gamma"}
    actual_paths = set(lines)

    assert actual_paths == expected_paths, f"Expected {targets_file} to contain exactly {expected_paths}, but found {actual_paths}"
    assert len(lines) == len(expected_paths), f"{targets_file} contains duplicates or extra lines."


def test_tar_archive():
    archive_file = "/home/user/required_backups.tar.gz"
    assert os.path.isfile(archive_file), f"Archive {archive_file} is missing."
    assert tarfile.is_tarfile(archive_file), f"{archive_file} is not a valid tar archive."

    with tarfile.open(archive_file, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        # Preserve the original inclusion and exclusion assertions.
        has_alpha = any("dir_alpha" in name for name in names)
        has_gamma = any("dir_gamma" in name for name in names)
        assert has_alpha, "dir_alpha is missing from the tar archive."
        assert has_gamma, "dir_gamma is missing from the tar archive."

        has_beta = any("dir_beta" in name for name in names)
        has_delta = any("dir_delta" in name for name in names)
        assert not has_beta, "dir_beta should NOT be in the tar archive."
        assert not has_delta, "dir_delta should NOT be in the tar archive."

        expected_files = {
            ("dir_alpha", "file1.txt"): b"alpha content\n",
            ("dir_gamma", "file3.txt"): b"gamma content\n",
        }
        allowed_directories = {("dir_alpha",), ("dir_gamma",)}
        seen = set()

        for member in members:
            parts = tuple(part for part in member.name.split("/") if part not in ("", "."))
            roots = [i for i, part in enumerate(parts) if part in ("dir_alpha", "dir_gamma")]
            assert len(roots) == 1, f"Unexpected archive member: {member.name}"
            relative = parts[roots[0]:]
            assert relative not in seen, f"Duplicate archive member: {member.name}"
            seen.add(relative)

            if relative in allowed_directories:
                assert member.isdir(), f"{member.name} should be a directory entry."
            elif relative in expected_files:
                assert member.isfile(), f"{member.name} should be a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected_files[relative], f"Incorrect contents in {member.name}."
            else:
                raise AssertionError(f"Unexpected archive member: {member.name}")

        assert set(expected_files).issubset(seen), "The archive does not contain all required files."


def test_compile_and_run_parser_on_varied_records():
    source = "/home/user/queue_parser.c"
    executable = "/tmp/queue_parser_verifier"
    queue_file = "/home/user/backup_queue.log"
    targets_file = "/home/user/targets.txt"

    subprocess.run(
        ["gcc", source, "-o", executable],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )

    records = [
        [("Path", "/tmp/verifier_data/first"), ("Priority", "LOW"), ("Status", "REQUIRED"), ("JobID", "9001")],
        [("Status", "IGNORED"), ("Path", "/tmp/verifier_data/ignored"), ("JobID", "9002"), ("Priority", "HIGH")],
        [("Priority", "CRITICAL"), ("JobID", "9003"), ("Status", "REQUIRED"), ("Path", "/tmp/verifier_data/second")],
        [("Path", "/tmp/verifier_data/not_exact"), ("Status", "NOT_REQUIRED"), ("Priority", "NORMAL"), ("JobID", "9004")],
        [("JobID", "9005"), ("Path", "/tmp/verifier_data/completed"), ("Priority", "LOW"), ("Status", "COMPLETED")],
    ]
    expected = [dict(record)["Path"] for record in records if dict(record)["Status"] == "REQUIRED"]
    generated_log = "".join(
        "BEGIN_JOB\n" + "".join(f"{key}: {value}\n" for key, value in record) + "END_JOB\n"
        for record in records
    )

    original_queue = open(queue_file, "rb").read()
    targets_existed = os.path.exists(targets_file)
    original_targets = open(targets_file, "rb").read() if targets_existed else None

    try:
        with open(queue_file, "w", encoding="utf-8") as f:
            f.write(generated_log)
        with open(targets_file, "w", encoding="utf-8") as f:
            f.write("stale output that must be replaced\n")

        subprocess.run(
            [executable],
            cwd="/home/user",
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )

        assert os.path.isfile(targets_file), "The parser did not create /home/user/targets.txt."
        with open(targets_file, "r", encoding="utf-8") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, f"Parser produced {actual}; expected {expected}."
    finally:
        with open(queue_file, "wb") as f:
            f.write(original_queue)
        if targets_existed:
            with open(targets_file, "wb") as f:
                f.write(original_targets)
        elif os.path.exists(targets_file):
            os.remove(targets_file)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
