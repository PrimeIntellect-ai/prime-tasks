#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import shutil
import stat
import subprocess
import tarfile
import uuid
import zipfile

import pytest

SCRIPT = "/home/user/curate_artifacts.py"
STAGING = "/home/user/staging_repo"
EXTRACTED = "/home/user/extracted_staging"
LOG = "/home/user/corrupted.log"
RELEASE = "/home/user/curated_release.tar.gz"


def clean_outputs():
    shutil.rmtree(EXTRACTED, ignore_errors=True)
    for path in (LOG, RELEASE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def source_expectations():
    corrupted = []
    extracted = {}

    archives = []
    for root, _, files in os.walk(STAGING):
        for name in files:
            if name.endswith(".zip") or name.endswith(".tar.gz"):
                archives.append(os.path.join(root, name))

    for path in sorted(archives):
        try:
            if path.endswith(".zip"):
                if not zipfile.is_zipfile(path):
                    raise zipfile.BadZipFile(path)
                with zipfile.ZipFile(path) as archive:
                    assert archive.testzip() is None
                    members = []
                    for info in archive.infolist():
                        if not info.is_dir():
                            members.append((info.filename, archive.read(info)))
            else:
                members = []
                with tarfile.open(path, "r:gz") as archive:
                    for member in archive.getmembers():
                        if member.isfile():
                            stream = archive.extractfile(member)
                            assert stream is not None
                            members.append((member.name, stream.read()))

            for name, data in members:
                normalized = os.path.normpath(name.lstrip("/"))
                assert normalized != ".." and not normalized.startswith("../")
                extracted[normalized] = data
        except (OSError, tarfile.TarError, zipfile.BadZipFile, EOFError):
            corrupted.append(os.path.abspath(path))

    targets = {}
    for relative, data in extracted.items():
        if relative.endswith(".bin") and len(data) > 100000:
            flat_name = os.path.basename(relative)
            assert flat_name not in targets, "Test inputs unexpectedly contain a flattened-name collision"
            targets[flat_name] = data

    return sorted(corrupted), extracted, targets


def assert_pipeline_matches_sources():
    expected_corrupt, expected_extracted, expected_targets = source_expectations()

    assert os.path.isdir(EXTRACTED), f"{EXTRACTED} directory was not created or is not a directory."
    for relative, expected_data in expected_extracted.items():
        output = os.path.join(EXTRACTED, relative)
        assert os.path.isfile(output), f"Extracted file is missing: {output}"
        with open(output, "rb") as stream:
            assert stream.read() == expected_data, f"Extracted bytes differ from source archive for {relative}"

    assert os.path.exists(LOG), f"{LOG} does not exist."
    with open(LOG, "r") as stream:
        actual_corrupt = [line.strip() for line in stream if line.strip()]
    assert actual_corrupt == expected_corrupt

    assert os.path.exists(RELEASE), f"{RELEASE} does not exist."
    with tarfile.open(RELEASE, "r:gz") as archive:
        files = [member for member in archive.getmembers() if member.isfile()]
        assert sorted(member.name for member in files) == sorted(expected_targets)
        for member in files:
            assert "/" not in member.name and "\\" not in member.name
            assert member.size > 100000
            stream = archive.extractfile(member)
            assert stream is not None
            assert stream.read() == expected_targets[member.name], (
                f"Curated member {member.name} does not contain the bytes from its source archive"
            )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.lexists(SCRIPT), f"{SCRIPT} does not exist."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
    clean_outputs()
    run_script()


def test_corrupted_log():
    log_path = "/home/user/corrupted.log"
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "/home/user/staging_repo/batch1/broken.tar.gz",
        "/home/user/staging_repo/batch2/bad_data.zip"
    ]

    assert lines == expected, f"Contents of {log_path} are incorrect. Expected {expected}, got {lines}."


def test_curated_release_tarball():
    tar_path = "/home/user/curated_release.tar.gz"
    assert os.path.exists(tar_path), f"{tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            members = tar.getmembers()
            file_names = sorted([m.name for m in members if m.isfile()])

            expected_names = ["large_v1.bin", "large_v2.bin", "large_v3.bin"]
            assert file_names == expected_names, f"Tarball does not contain the exact expected files. Expected {expected_names}, got {file_names}."

            for m in members:
                if m.isfile():
                    assert m.size > 100000, f"File {m.name} in tarball has size {m.size}, which is not strictly greater than 100,000 bytes."
                    assert "/" not in m.name and "\\" not in m.name, f"File {m.name} is not at the root level of the tarball."
    except tarfile.ReadError:
        pytest.fail(f"{tar_path} could not be read as a gzip-compressed tarball.")


def test_extracted_staging_directory():
    staging_path = "/home/user/extracted_staging"
    assert os.path.isdir(staging_path), f"{staging_path} directory was not created or is not a directory."


def test_outputs_contain_source_archive_bytes():
    assert_pipeline_matches_sources()


def test_script_handles_fresh_unseen_archives():
    token = uuid.uuid4().hex
    probe_zip = os.path.join(STAGING, "batch2", f"probe_{token}.zip")
    probe_bad = os.path.join(STAGING, "batch1", f"corrupt_{token}.tar.gz")
    target_name = f"fresh_{token}.bin"
    nested_name = f"probe_{token}/nested/{target_name}"
    small_name = f"probe_{token}/nested/small_{token}.bin"
    target_data = os.urandom(120001)
    small_data = os.urandom(99999)

    with zipfile.ZipFile(probe_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(nested_name, target_data)
        archive.writestr(small_name, small_data)
    with open(probe_bad, "wb") as stream:
        stream.write(os.urandom(257))

    try:
        clean_outputs()
        run_script()

        with open(LOG, "r") as stream:
            lines = [line.strip() for line in stream if line.strip()]
        expected_log = sorted([
            "/home/user/staging_repo/batch1/broken.tar.gz",
            "/home/user/staging_repo/batch2/bad_data.zip",
            os.path.abspath(probe_bad),
        ])
        assert lines == expected_log

        extracted_target = os.path.join(EXTRACTED, *nested_name.split("/"))
        extracted_small = os.path.join(EXTRACTED, *small_name.split("/"))
        with open(extracted_target, "rb") as stream:
            assert stream.read() == target_data
        with open(extracted_small, "rb") as stream:
            assert stream.read() == small_data

        with tarfile.open(RELEASE, "r:gz") as archive:
            names = sorted(member.name for member in archive.getmembers() if member.isfile())
            assert names == sorted(["large_v1.bin", "large_v2.bin", "large_v3.bin", target_name])
            member = archive.getmember(target_name)
            stream = archive.extractfile(member)
            assert stream is not None
            assert stream.read() == target_data
            assert os.path.basename(small_name) not in names
    finally:
        for path in (probe_zip, probe_bad):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        clean_outputs()
        run_script()

    assert_pipeline_matches_sources()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
