#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tarfile
from io import BytesIO
from pathlib import Path


def test_process_datasets_script_exists():
    path = "/home/user/process_datasets.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."


def test_processing_log_contents():
    path = "/home/user/processing.log"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    expected_lines = [
        "PROCESSED: dataset_alpha.tar.gz - EpiGen - L-101",
        "SKIPPED: dataset_malicious.tar.gz - ILLEGAL PATHS",
        "PROCESSED: dataset_gamma.tar.gz - Proteomics - L-303"
    ]

    for line in expected_lines:
        assert line in content, f"Expected log line '{line}' not found in {path}. Content:\n{content}"


def test_dataset_alpha_processed_correctly():
    path = "/home/user/organized/EpiGen/L-101/data1.tsv"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "PAT-REDACTED" in content, f"'PAT-REDACTED' not found in {path}."
    assert "PAT-1234" not in content, f"Unredacted ID 'PAT-1234' found in {path}."
    assert "PAT-5678" not in content, f"Unredacted ID 'PAT-5678' found in {path}."


def test_dataset_gamma_processed_correctly():
    path = "/home/user/organized/Proteomics/L-303/samples.tsv"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "PAT-REDACTED" in content, f"'PAT-REDACTED' not found in {path}."
    assert "PAT-9999" not in content, f"Unredacted ID 'PAT-9999' found in {path}."


def test_malicious_dataset_skipped():
    evil_path = "/tmp/evil.txt"
    assert not os.path.exists(evil_path), f"Malicious file {evil_path} was extracted!"

    organized_dir = "/home/user/organized/Transcriptomics"
    assert not os.path.exists(organized_dir), f"Directory {organized_dir} should not exist, as the dataset was malicious."


def _add_bytes(archive, name, data):
    payload = data.encode("utf-8")
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    info.mode = 0o644
    archive.addfile(info, BytesIO(payload))


def test_z_script_executes_and_handles_additional_archives():
    script = Path("/home/user/process_datasets.sh")
    assert script.is_file(), f"Script {script} does not exist."
    assert stat.S_ISREG(script.lstat().st_mode), f"{script} is not a regular file."

    syntax = subprocess.run(
        ["bash", "-n", str(script)], text=True, capture_output=True, timeout=10
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax:\n{syntax.stderr}"

    token = secrets.token_hex(6)
    project = f"Project{token}"
    lab = f"LAB-{token}"
    traversal_project = f"Traversal{token}"
    absolute_project = f"Absolute{token}"

    safe_name = f"new study {token}.tar.gz"
    traversal_name = f"traversal {token}.tar.gz"
    absolute_name = f"absolute {token}.tar.gz"

    incoming = Path("/home/user/incoming")
    organized = Path("/home/user/organized")
    log = Path("/home/user/processing.log")

    shutil.rmtree(incoming, ignore_errors=True)
    shutil.rmtree(organized, ignore_errors=True)
    incoming.mkdir(parents=True, mode=0o777)
    organized.mkdir(parents=True, mode=0o777)
    log.write_text("")
    os.chmod(incoming, 0o777)
    os.chmod(organized, 0o777)
    os.chmod(log, 0o666)

    patient_a = f"PAT-{secrets.randbelow(9000) + 1000:04d}"
    patient_b = f"PAT-{secrets.randbelow(9000) + 1000:04d}"
    while patient_b == patient_a:
        patient_b = f"PAT-{secrets.randbelow(9000) + 1000:04d}"

    first_tsv = f"Sample\tPatient\tNote\nA\t{patient_a}\tkeep\nB\t{patient_b}\t{patient_a}\n"
    second_tsv = f"Subject\tValue\n{patient_b}\t42\n"
    expected_first = re.sub(r"PAT-[0-9]{4}", "PAT-REDACTED", first_tsv)
    expected_second = re.sub(r"PAT-[0-9]{4}", "PAT-REDACTED", second_tsv)

    with tarfile.open(incoming / safe_name, "w:gz") as archive:
        root = f"package {token}"
        _add_bytes(archive, f"{root}/metadata.conf", f"Project={project}\nLabCode={lab}\n")
        _add_bytes(archive, f"{root}/data file.tsv", first_tsv)
        _add_bytes(archive, f"{root}/nested/more.tsv", second_tsv)
        _add_bytes(archive, f"{root}/nested/notes.txt", patient_a + "\n")

    traversal_escape = Path(f"/tmp/traversal_escape_{token}.txt")
    absolute_escape = Path(f"/tmp/absolute_escape_{token}.txt")
    traversal_escape.unlink(missing_ok=True)
    absolute_escape.unlink(missing_ok=True)

    with tarfile.open(incoming / traversal_name, "w:gz") as archive:
        _add_bytes(archive, "payload/metadata.conf", f"Project={traversal_project}\nLabCode=BAD-{token}\n")
        _add_bytes(archive, "payload/data.tsv", patient_a + "\n")
        _add_bytes(archive, f"nested/../../../../../../tmp/traversal_escape_{token}.txt", "escaped\n")

    with tarfile.open(incoming / absolute_name, "w:gz") as archive:
        _add_bytes(archive, "payload/metadata.conf", f"Project={absolute_project}\nLabCode=BAD-{token}\n")
        _add_bytes(archive, "payload/data.tsv", patient_b + "\n")
        _add_bytes(archive, str(absolute_escape), "escaped\n")

    result = subprocess.run(
        ["bash", str(script)],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )

    output_dir = organized / project / lab
    first_output = output_dir / "data file.tsv"
    second_output = output_dir / "more.tsv"
    assert first_output.is_file(), (
        f"Missing dynamically generated output {first_output}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert second_output.is_file(), f"Missing dynamically generated output {second_output}."
    assert first_output.read_text() == expected_first
    assert second_output.read_text() == expected_second
    assert not re.search(r"PAT-[0-9]{4}", first_output.read_text())
    assert not re.search(r"PAT-[0-9]{4}", second_output.read_text())

    assert not traversal_escape.exists(), "A traversal member escaped the extraction directory."
    assert not absolute_escape.exists(), "An absolute-path member escaped the extraction directory."
    assert not (organized / traversal_project).exists(), "Traversal archive was organized instead of skipped."
    assert not (organized / absolute_project).exists(), "Absolute-path archive was organized instead of skipped."

    actual_lines = log.read_text().splitlines()
    expected_lines = [
        f"PROCESSED: {safe_name} - {project} - {lab}",
        f"SKIPPED: {traversal_name} - ILLEGAL PATHS",
        f"SKIPPED: {absolute_name} - ILLEGAL PATHS",
    ]
    assert sorted(actual_lines) == sorted(expected_lines), (
        f"Unexpected processing log. Expected exactly {expected_lines}, got {actual_lines}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
