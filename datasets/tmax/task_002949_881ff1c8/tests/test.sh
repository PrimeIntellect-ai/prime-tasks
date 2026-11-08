#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import pytest

ARTIFACT_DIR = "/home/user/artifacts"
INCOMING_MANIFEST = os.path.join(ARTIFACT_DIR, "incoming_manifest.log")
UTF8_MANIFEST = os.path.join(ARTIFACT_DIR, "manifest_utf8.log")
CURATED_TAR = "/home/user/curated_artifacts.tar"
FINAL_LIST = "/home/user/final_list.txt"

EXPECTED_MAPPING = {
    "bin_A192.tar.gz": "auth-service-1.0.tar.gz",
    "bin_B834.tar.gz": "payment-gateway-2.1.tar.gz",
    "bin_C771.tar.gz": "ui-components-3.4.tar.gz",
}
EXPECTED_FILES = set(EXPECTED_MAPPING.values())


def original_archive_bytes():
    result = subprocess.run(
        ["tar", "-czf", "-", "-T", "/dev/null"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout


def test_manifest_utf8_exists_and_encoding():
    assert os.path.isfile(UTF8_MANIFEST), f"Manifest file {UTF8_MANIFEST} does not exist."

    try:
        with open(UTF8_MANIFEST, "rb") as f:
            content = f.read()
            decoded_content = content.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"{UTF8_MANIFEST} is not valid UTF-8 encoded.")

    expected_strings = [
        "[Artifact]",
        "Temp-Name: bin_A192.tar.gz",
        "Real-Name: auth-service-1.0.tar.gz",
        "Temp-Name: bin_B834.tar.gz",
        "Real-Name: payment-gateway-2.1.tar.gz",
        "Temp-Name: bin_C771.tar.gz",
        "Real-Name: ui-components-3.4.tar.gz",
    ]
    for s in expected_strings:
        assert s in decoded_content, f"Expected string '{s}' not found in decoded UTF-8 manifest."

    with open(INCOMING_MANIFEST, "rb") as f:
        expected_utf8 = f.read().decode("utf-16le").encode("utf-8")
    assert content == expected_utf8, "manifest_utf8.log is not an exact UTF-8 conversion of incoming_manifest.log."

    records = re.findall(
        r"\[Artifact\]\r?\n"
        r"Temp-Name: ([^\r\n]+)\r?\n"
        r"Real-Name: ([^\r\n]+)\r?\n"
        r"Timestamp: ([^\r\n]+)",
        decoded_content,
    )
    parsed_mapping = {temp: real for temp, real, _timestamp in records}
    assert parsed_mapping == EXPECTED_MAPPING, f"Parsed manifest mapping {parsed_mapping} is incorrect."


def test_renamed_archives_exist_and_preserve_original_bytes():
    expected_bytes = original_archive_bytes()
    expected_files = [
        "auth-service-1.0.tar.gz",
        "payment-gateway-2.1.tar.gz",
        "ui-components-3.4.tar.gz",
    ]
    for name in expected_files:
        path = os.path.join(ARTIFACT_DIR, name)
        assert os.path.isfile(path), f"Renamed archive {path} does not exist. Renaming might have failed."
        with open(path, "rb") as f:
            actual_bytes = f.read()
        assert actual_bytes == expected_bytes, f"Renamed archive {path} does not preserve the original archive bytes."
        try:
            with tarfile.open(path, "r:gz") as archive:
                assert archive.getmembers() == [], f"{path} is not the original valid empty gzip-compressed tar archive."
        except (tarfile.ReadError, EOFError):
            pytest.fail(f"Renamed archive {path} is not a valid gzip-compressed tar archive.")

    for old_name in EXPECTED_MAPPING:
        assert not os.path.exists(os.path.join(ARTIFACT_DIR, old_name)), f"Original path {old_name} still exists; it was not renamed."


def test_curated_artifacts_tar():
    assert os.path.isfile(CURATED_TAR), f"Tar archive {CURATED_TAR} does not exist."

    expected_files = {
        "auth-service-1.0.tar.gz",
        "payment-gateway-2.1.tar.gz",
        "ui-components-3.4.tar.gz",
    }

    try:
        with tarfile.open(CURATED_TAR, "r") as tar:
            members = tar.getnames()
            member_objects = tar.getmembers()
            assert set(members) == expected_files, f"Tar archive contents {members} do not exactly match expected files {expected_files} at the root."
            assert len(members) == len(expected_files), "Tar archive contains duplicate members."
            for member in member_objects:
                assert member.isfile(), f"Tar member {member.name} is not a regular file."
                assert "/" not in member.name, f"Tar member {member.name} is not at the archive root."
                archived_bytes = tar.extractfile(member).read()
                with open(os.path.join(ARTIFACT_DIR, member.name), "rb") as f:
                    disk_bytes = f.read()
                assert archived_bytes == disk_bytes, f"Tar member {member.name} does not contain the renamed archive bytes."
                assert archived_bytes == original_archive_bytes(), f"Tar member {member.name} does not preserve the original archive bytes."
    except tarfile.ReadError:
        pytest.fail(f"File {CURATED_TAR} is not a valid tar archive.")


def test_final_list_txt():
    assert os.path.isfile(FINAL_LIST), f"List file {FINAL_LIST} does not exist."

    with open(FINAL_LIST, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "auth-service-1.0.tar.gz",
        "payment-gateway-2.1.tar.gz",
        "ui-components-3.4.tar.gz",
    ]

    assert lines == expected_lines, f"Contents of {FINAL_LIST} do not match the expected sorted list of artifacts."

    with tarfile.open(CURATED_TAR, "r") as tar:
        actual_sorted_members = sorted(tar.getnames())
    assert lines == actual_sorted_members, "final_list.txt is not the sorted listing of curated_artifacts.tar."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
