#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import uuid
import zipfile

import pytest

REPORT_PATH = Path("/home/user/archive_report.json")
SCRIPT_PATH = Path("/home/user/process_datasets.sh")
CONFIG_PATH = Path("/home/user/dataset_config.ini")
LOG_PATH = Path("/home/user/submission_logs.txt")


def test_report_exists():
    assert REPORT_PATH.exists(), f"The report file {REPORT_PATH} was not found. Did the script run and generate it?"
    assert REPORT_PATH.is_file(), f"{REPORT_PATH} is not a file."


def test_report_content_and_structure():
    with REPORT_PATH.open("r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_keys = {"valid_and_safe", "checksum_failed", "zip_slip_detected"}
    assert set(report_data.keys()) == expected_keys, f"The JSON report keys {set(report_data.keys())} do not match the expected keys {expected_keys}."

    expected_valid = ["alpha_data.tar.gz", "epsilon_data.zip"]
    expected_failed = ["gamma_data.tar.gz"]
    expected_slip = ["beta_data.zip", "delta_data.tar.gz"]

    assert report_data["valid_and_safe"] == expected_valid, (
        f"Expected 'valid_and_safe' to be {expected_valid}, but got {report_data['valid_and_safe']}. "
        "Ensure arrays are sorted alphabetically and files are correctly classified."
    )
    assert report_data["checksum_failed"] == expected_failed, (
        f"Expected 'checksum_failed' to be {expected_failed}, but got {report_data['checksum_failed']}. "
        "Ensure arrays are sorted alphabetically and files are correctly classified."
    )
    assert report_data["zip_slip_detected"] == expected_slip, (
        f"Expected 'zip_slip_detected' to be {expected_slip}, but got {report_data['zip_slip_detected']}. "
        "Ensure arrays are sorted alphabetically and files are correctly classified."
    )


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_zz_script_executes_and_processes_dynamic_archives():
    assert SCRIPT_PATH.exists(), f"Required script {SCRIPT_PATH} does not exist."
    assert SCRIPT_PATH.is_file(), f"{SCRIPT_PATH} is not a regular file."
    assert SCRIPT_PATH.stat().st_size > 0, f"{SCRIPT_PATH} is empty."

    token = uuid.uuid4().hex
    archive_dir = Path(f"/home/user/datasets_verifier_{token}")
    dynamic_report = Path(f"/home/user/archive_report_verifier_{token}.json")
    safe_payload = f"payload_{token}"
    extraction_marker = Path(f"/home/user/extracted_{token}")
    stripped_absolute_marker = Path(f"/home/user/home/user/extracted_{token}")

    names = [
        f"{uuid.uuid4().hex}.zip",
        f"{uuid.uuid4().hex}.tar.gz",
        f"{uuid.uuid4().hex}.zip",
        f"{uuid.uuid4().hex}.tar.gz",
        f"{uuid.uuid4().hex}.zip",
    ]
    safe_zip, safe_tar, slip_zip, slip_tar, bad_checksum = names

    old_config = CONFIG_PATH.read_bytes()
    old_log = LOG_PATH.read_bytes()
    old_report = REPORT_PATH.read_bytes()

    try:
        archive_dir.mkdir(mode=0o777)
        os.chmod(archive_dir, 0o777)

        with zipfile.ZipFile(archive_dir / safe_zip, "w") as zf:
            zf.writestr(f"{safe_payload}/data.txt", b"safe zip data")

        with tarfile.open(archive_dir / safe_tar, "w:gz") as tf:
            data = b"safe tar data"
            info = tarfile.TarInfo(f"{safe_payload}/table.csv")
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

        with zipfile.ZipFile(archive_dir / slip_zip, "w") as zf:
            zf.writestr(f"../../{token}/escape.txt", b"unsafe")

        with tarfile.open(archive_dir / slip_tar, "w:gz") as tf:
            data = b"must not be extracted"
            info = tarfile.TarInfo(str(extraction_marker))
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

        # This archive is also unsafe, but its deliberately wrong expected hash
        # must take precedence and classify it only as checksum_failed.
        with zipfile.ZipFile(archive_dir / bad_checksum, "w") as zf:
            zf.writestr("../checksum_precedence.txt", b"bad hash")

        actual_hashes = {name: sha256(archive_dir / name) for name in names}
        expected_hashes = dict(actual_hashes)
        expected_hashes[bad_checksum] = "0" * 64

        records = []
        for i, name in enumerate(reversed(names)):
            records.append(
                "[Submission]\n"
                f"Dataset: {name}\n"
                f"Submitter: Verifier{i}\n"
                f"SHA256: {expected_hashes[name]}"
            )

        CONFIG_PATH.write_text(
            "[settings]\n"
            f"archive_directory={archive_dir}\n"
            f"report_output={dynamic_report}\n"
        )
        LOG_PATH.write_text("\n\n".join(records) + "\n")
        dynamic_report.unlink(missing_ok=True)
        extraction_marker.unlink(missing_ok=True)
        shutil.rmtree(stripped_absolute_marker.parent.parent, ignore_errors=True)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", str(SCRIPT_PATH)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert dynamic_report.is_file(), (
            "The executed script did not read report_output from dataset_config.ini "
            f"and create {dynamic_report}."
        )

        try:
            report_data = json.loads(dynamic_report.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"The dynamically generated report is not valid JSON: {exc}")

        expected = {
            "valid_and_safe": sorted([safe_zip, safe_tar]),
            "checksum_failed": [bad_checksum],
            "zip_slip_detected": sorted([slip_zip, slip_tar]),
        }
        assert set(report_data.keys()) == set(expected.keys())
        assert report_data == expected, (
            f"Dynamic archive classifications were incorrect. Expected {expected}, got {report_data}."
        )

        assert {p.name for p in archive_dir.iterdir()} == set(names), (
            "The archive directory was modified or archive contents were extracted."
        )
        assert not extraction_marker.exists(), "An absolute-path archive member was extracted."
        assert not stripped_absolute_marker.exists(), "An archive member was extracted under the working directory."
        assert not (Path("/home/user") / safe_payload).exists(), "A safe archive was extracted instead of only inspected."
        assert {name: sha256(archive_dir / name) for name in names} == actual_hashes, (
            "One or more input archives were modified."
        )
    finally:
        CONFIG_PATH.write_bytes(old_config)
        LOG_PATH.write_bytes(old_log)
        REPORT_PATH.write_bytes(old_report)
        dynamic_report.unlink(missing_ok=True)
        extraction_marker.unlink(missing_ok=True)
        shutil.rmtree(archive_dir, ignore_errors=True)
        shutil.rmtree(Path("/home/user") / safe_payload, ignore_errors=True)
        shutil.rmtree(stripped_absolute_marker.parent.parent, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
