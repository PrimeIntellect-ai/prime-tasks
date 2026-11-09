#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import pytest


def test_original_fixtures_still_present():
    archives_dir = "/home/user/backups/archives"
    expected_archives = {
        os.path.join(archives_dir, "backup_valid_1.tar.gz"),
        os.path.join(archives_dir, "backup_valid_2.tar.gz"),
        os.path.join(archives_dir, "backup_corrupt_1.tar.gz"),
        os.path.join(archives_dir, "backup_corrupt_2.tar.gz"),
    }
    assert set(glob.glob(os.path.join(archives_dir, "*.tar.gz"))) == expected_archives

    for name, member, contents in (
        ("backup_valid_1.tar.gz", "valid1.txt", b"Valid data 1\n"),
        ("backup_valid_2.tar.gz", "valid2.txt", b"Valid data 2\n"),
    ):
        path = os.path.join(archives_dir, name)
        result = subprocess.run(
            ["tar", "-xOzf", path, member], capture_output=True, check=False
        )
        assert result.returncode == 0, f"Valid archive was removed or damaged: {path}"
        assert result.stdout == contents, f"Archive contents changed: {path}"

    for name in ("backup_corrupt_1.tar.gz", "backup_corrupt_2.tar.gz"):
        path = os.path.join(archives_dir, name)
        assert os.path.getsize(path) == 1024, f"Corrupted archive changed: {path}"
        result = subprocess.run(
            ["tar", "-tzf", path], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, check=False
        )
        assert result.returncode != 0, f"Expected corrupted archive is no longer corrupt: {path}"

    expected_log = (
        "Job ID: 1001\nDate: 2023-10-01\nStatus: SUCCESS\n---\n"
        "Job ID: 1002\nDate: 2023-10-02\nStatus: FAILED\nError: Disk full\n---\n"
        "Job ID: 1003\nDate: 2023-10-03\nStatus: FAILED\nError: Network timeout\n---\n"
        "Job ID: 1004\nDate: 2023-10-04\nStatus: SUCCESS\n---\n"
    )
    with open("/home/user/backups/logs/job_history.log", "r", encoding="utf-8") as f:
        assert f.read() == expected_log, "The original job history was removed or modified."

    data_dir = "/home/user/backups/data"
    expected_data_files = {
        os.path.join(data_dir, "projA/readme.md"),
        os.path.join(data_dir, "projA/tool.bin"),
        os.path.join(data_dir, "projB/runner.exe"),
        os.path.join(data_dir, "projB/data.dat"),
    }
    actual_data_files = {
        os.path.join(root, name)
        for root, _, names in os.walk(data_dir)
        for name in names
    }
    assert actual_data_files == expected_data_files, "Backup data files were removed or replaced."
    with open(os.path.join(data_dir, "projA/readme.md"), "rb") as f:
        assert f.read() == b"Just a text file\n"
    with open(os.path.join(data_dir, "projB/data.dat"), "rb") as f:
        assert f.read() == b"More text\n"
    assert subprocess.run(["cmp", "-s", "/bin/ls", os.path.join(data_dir, "projA/tool.bin")]).returncode == 0
    assert subprocess.run(["cmp", "-s", "/bin/bash", os.path.join(data_dir, "projB/runner.exe")]).returncode == 0


def test_notes_are_utf8_and_faithfully_converted():
    notes_dir = "/home/user/backups/notes"
    assert os.path.isdir(notes_dir), f"Directory {notes_dir} is missing."

    expected = {
        "note1.txt": "Backup note 1: résumé\n",
        "note2.txt": "Backup note 2: jalapeño\n",
        "note3.txt": "Backup note 3: façade\n",
    }
    txt_files = glob.glob(os.path.join(notes_dir, "*.txt"))
    assert {os.path.basename(path) for path in txt_files} == set(expected), (
        "The original note set was removed or changed."
    )

    for name, expected_text in expected.items():
        path = os.path.join(notes_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                actual_text = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {path} is not valid UTF-8.")
        assert actual_text == expected_text, f"Note was not faithfully converted: {path}"


def test_backup_report_content():
    report_path = "/home/user/backup_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    # Preserve the original verifier's assertions derived from the final state.
    archives_dir = "/home/user/backups/archives"
    corrupted_archives = []
    if os.path.isdir(archives_dir):
        for f in glob.glob(os.path.join(archives_dir, "*.tar.gz")):
            if os.system(f"tar -tzf {f} > /dev/null 2>&1") != 0:
                corrupted_archives.append(f)
    corrupted_archives.sort()

    log_path = "/home/user/backups/logs/job_history.log"
    failed_jobs = []
    if os.path.isfile(log_path):
        with open(log_path, "r", encoding="utf-8") as f:
            content = f.read()
            records = content.split("---")
            for record in records:
                if "Status: FAILED" in record:
                    for line in record.strip().split("\n"):
                        if line.startswith("Job ID:"):
                            failed_jobs.append(line.split(":")[1].strip())
    failed_jobs.sort()

    data_dir = "/home/user/backups/data"
    elf_files = []
    if os.path.isdir(data_dir):
        for root, _, files in os.walk(data_dir):
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, "rb") as f:
                        if f.read(4) == b"\x7fELF":
                            elf_files.append(file_path)
                except Exception:
                    pass
    elf_files.sort()

    notes_count = 0
    if os.path.isdir("/home/user/backups/notes"):
        notes_count = len(glob.glob("/home/user/backups/notes/*.txt"))

    expected_lines = ["[Corrupted Archives]"]
    expected_lines.extend(corrupted_archives)
    expected_lines.extend(["", "[Failed Jobs]"])
    expected_lines.extend(failed_jobs)
    expected_lines.extend(["", "[ELF Files]"])
    expected_lines.extend(elf_files)
    expected_lines.extend(["", "[Converted Notes]", f"Total converted: {notes_count}"])
    expected_content = "\n".join(expected_lines).strip()

    fixed_expected = """[Corrupted Archives]
/home/user/backups/archives/backup_corrupt_1.tar.gz
/home/user/backups/archives/backup_corrupt_2.tar.gz

[Failed Jobs]
1002
1003

[ELF Files]
/home/user/backups/data/projA/tool.bin
/home/user/backups/data/projB/runner.exe

[Converted Notes]
Total converted: 3"""
    assert expected_content == fixed_expected, "The audited fixture set was modified."

    with open(report_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()
    assert actual_content == expected_content, (
        f"Report content does not match expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
