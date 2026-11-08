#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import tarfile
import pytest

RESTORED_ARCHIVE = "/home/user/restored_backups.tar.gz"
BACKUP_ARCHIVES = [
    "/home/user/backups/backup_01.dat",
    "/home/user/backups/backup_02.dat",
    "/home/user/backups/backup_03.dat",
]

EXPECTED_FILES = {
    "Alpha77.log": "ID: Alpha77",
    "Bravo88.log": "ID: Bravo88",
    "Charlie99.log": "ID: Charlie99",
}

EXPECTED_CONTENTS = {
    "Alpha77.log": "ID: Alpha77\nSystem status: normal\n",
    "Bravo88.log": "ID: Bravo88\nSystem status: warning\n",
    "Charlie99.log": "ID: Charlie99\nSystem status: critical\n",
}


def derive_expected_from_repaired_backups():
    derived = {}

    for path in BACKUP_ARCHIVES:
        assert os.path.isfile(path), f"Missing source backup: {path}"

        with open(path, "rb") as backup_file:
            assert backup_file.read(4) == b"\x1f\x8b\x08\x00", \
                f"{path} does not have the repaired gzip header."

        try:
            with tarfile.open(path, "r:gz") as tar:
                members = tar.getmembers()
                assert members, f"{path} contains no log files."
                assert all(member.isfile() for member in members), \
                    f"{path} contains a non-file member."

                for member in members:
                    extracted = tar.extractfile(member)
                    assert extracted is not None, \
                        f"Could not read {member.name} from {path}."
                    raw = extracted.read()
                    try:
                        text = raw.decode("utf-16le")
                    except UnicodeDecodeError:
                        pytest.fail(f"{member.name} in {path} is not valid UTF-16LE.")

                    lines = text.splitlines()
                    assert lines, f"{member.name} in {path} is empty."
                    match = re.fullmatch(r"ID: (.+)", lines[0])
                    assert match, \
                        f"Invalid ID line in {member.name} from {path}: {lines[0]!r}"
                    output_name = match.group(1) + ".log"
                    assert output_name not in derived, \
                        f"Duplicate restored filename derived from backups: {output_name}"
                    derived[output_name] = text
        except tarfile.ReadError:
            pytest.fail(f"{path} is not a valid repaired gzip-compressed tarball.")

    # Ensure the source archives themselves still contain the complete original data.
    assert derived == EXPECTED_CONTENTS, \
        f"Repaired backups do not contain the expected complete logs: {derived!r}"
    return derived


def test_restored_archive_exists():
    """Check if the restored archive exists."""
    assert os.path.isfile(RESTORED_ARCHIVE), f"{RESTORED_ARCHIVE} does not exist."


def test_restored_archive_is_valid_tar_gz():
    """Check if the restored archive is a valid gzip-compressed tarball."""
    assert os.path.isfile(RESTORED_ARCHIVE), f"{RESTORED_ARCHIVE} does not exist."
    assert tarfile.is_tarfile(RESTORED_ARCHIVE), \
        f"{RESTORED_ARCHIVE} is not a valid tar archive."

    try:
        with tarfile.open(RESTORED_ARCHIVE, "r:gz"):
            pass
    except tarfile.ReadError:
        pytest.fail(f"{RESTORED_ARCHIVE} is not a valid gzip-compressed tarball.")


def test_source_backups_were_repaired():
    """Verify every supplied .dat archive was repaired and remains extractable."""
    derive_expected_from_repaired_backups()


def test_restored_archive_contents():
    """Check exact filenames, full contents, encoding, and archive layout."""
    assert os.path.isfile(RESTORED_ARCHIVE), f"{RESTORED_ARCHIVE} does not exist."
    expected_contents = derive_expected_from_repaired_backups()

    try:
        with tarfile.open(RESTORED_ARCHIVE, "r:gz") as tar:
            members = tar.getmembers()

            actual_filenames = []
            for member in members:
                assert member.isfile(), \
                    f"Archive contains non-file member: {member.name}"
                name = member.name.lstrip('./')
                assert '/' not in name, \
                    f"File {name} is not at the root level of the archive."
                actual_filenames.append(name)

            assert len(actual_filenames) == len(EXPECTED_FILES), \
                f"Archive must contain exactly {len(EXPECTED_FILES)} files."
            assert len(actual_filenames) == len(set(actual_filenames)), \
                "Archive contains duplicate filenames."
            assert set(actual_filenames) == set(EXPECTED_FILES.keys()), \
                f"Archive contains incorrect files. Expected {set(EXPECTED_FILES.keys())}, found {set(actual_filenames)}"

            for filename, expected_first_line in EXPECTED_FILES.items():
                member = next(
                    m for m in members if m.name.lstrip('./') == filename
                )
                extracted = tar.extractfile(member)
                assert extracted is not None, \
                    f"Could not read {filename} from archive."
                raw_content = extracted.read()

                try:
                    text_content = raw_content.decode('utf-8')
                except UnicodeDecodeError:
                    pytest.fail(f"File {filename} is not valid UTF-8 encoded.")

                lines = text_content.splitlines()
                assert len(lines) > 0, f"File {filename} is empty."
                assert lines[0] == expected_first_line, \
                    f"First line of {filename} is '{lines[0]}', expected '{expected_first_line}'"

                expected_text = expected_contents[filename]
                assert text_content == expected_text, \
                    f"File {filename} does not contain the complete restored log."
                assert raw_content == expected_text.encode("utf-8"), \
                    f"File {filename} is not the exact UTF-8 conversion of its source log."

    except tarfile.ReadError:
        pytest.fail(f"Failed to read {RESTORED_ARCHIVE}.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
