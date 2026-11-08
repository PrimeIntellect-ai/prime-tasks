#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import tarfile
from pathlib import Path

HOME = Path("/home/user")
ARCHIVE = HOME / "incremental.tar.gz"
INCOMING = HOME / "incoming.tar.gz"
BASELINE = HOME / "baseline"
STAGING = HOME / "staging"
RULES = HOME / "rules.json"

CANONICAL_INCOMING = {
    "API_v1.md": b"API V1 Content - UPDATED\n",
    "UserGuide_v1.md": b"User Guide Content\n",
    "API_v2.md": b"API V2 Content\n",
    "README.txt": b"Readme content\n",
}
CANONICAL_BASELINE = {
    "Reference_API_v1.md": b"API V1 Content\n",
    "Manual_UserGuide_v1.md": b"User Guide Content\n",
    "README.txt": b"Readme content\n",
}
CANONICAL_RULES = {
    "API_": "Reference_API_",
    "UserGuide_": "Manual_UserGuide_",
}


def read_regular_tar_files(path, mode):
    with tarfile.open(path, mode) as tar:
        members = tar.getmembers()
        assert all(m.isfile() for m in members), "Archive must contain only regular files."
        names = [m.name for m in members]
        assert len(names) == len(set(names)), "Archive contains duplicate filenames."
        result = {}
        for member in members:
            extracted = tar.extractfile(member)
            assert extracted is not None
            result[member.name] = extracted.read()
        return members, result


def renamed_name(name, rules):
    for old_prefix, new_prefix in rules.items():
        if name.startswith(old_prefix):
            return new_prefix + name[len(old_prefix):]
    return name


def test_inputs_and_staging_are_correct():
    assert INCOMING.is_file(), f"Input archive {INCOMING} is missing."
    _, incoming_files = read_regular_tar_files(INCOMING, "r:gz")
    assert incoming_files == CANONICAL_INCOMING, "The supplied incoming archive was altered."

    with RULES.open("r", encoding="utf-8") as f:
        rules = json.load(f)
    assert rules == CANONICAL_RULES, "The supplied rename rules were altered."

    baseline_files = {
        str(path.relative_to(BASELINE)): path.read_bytes()
        for path in BASELINE.rglob("*")
        if path.is_file()
    }
    assert baseline_files == CANONICAL_BASELINE, "The supplied baseline was altered."

    expected_staging = {
        renamed_name(name, rules): content
        for name, content in incoming_files.items()
    }
    assert STAGING.is_dir(), f"Staging directory {STAGING} does not exist."
    staging_entries = list(STAGING.rglob("*"))
    assert all(path.is_file() and not path.is_symlink() for path in staging_entries), \
        "Staging must contain only the renamed regular files."
    actual_staging = {
        str(path.relative_to(STAGING)): path.read_bytes()
        for path in staging_entries
    }
    assert actual_staging == expected_staging, \
        "Staging does not exactly contain the extracted and renamed incoming files."


def test_incremental_archive_exists():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"File {ARCHIVE} is not a valid tar archive."


def test_incremental_archive_contents():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist."

    with RULES.open("r", encoding="utf-8") as f:
        rules = json.load(f)
    _, incoming_files = read_regular_tar_files(INCOMING, "r:gz")
    renamed = {
        renamed_name(name, rules): content
        for name, content in incoming_files.items()
    }
    baseline = {
        str(path.relative_to(BASELINE)): path.read_bytes()
        for path in BASELINE.rglob("*")
        if path.is_file()
    }
    expected = {
        name: content
        for name, content in renamed.items()
        if name not in baseline or baseline[name] != content
    }

    with tarfile.open(ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        files = [m for m in members if m.isfile()]

        # Preserve the original concrete checks.
        assert len(files) == 2, f"Expected exactly 2 files in the archive, found {len(files)}."
        assert len(members) == len(files), "The archive contains non-file entries."
        for f in files:
            assert "/" not in f.name, \
                f"File '{f.name}' in archive contains directory paths, but should be at the root."
        names = [f.name for f in files]
        assert "Reference_API_v1.md" in names, "Reference_API_v1.md is missing from the archive."
        assert "Reference_API_v2.md" in names, "Reference_API_v2.md is missing from the archive."
        assert len(names) == len(set(names)), "The archive contains duplicate filenames."

        with tar.extractfile("Reference_API_v1.md") as f1:
            content1 = f1.read().decode("utf-8")
            assert "API V1 Content - UPDATED" in content1, \
                "Content of Reference_API_v1.md is incorrect."
            assert content1.encode("utf-8") == expected["Reference_API_v1.md"]

        with tar.extractfile("Reference_API_v2.md") as f2:
            content2 = f2.read().decode("utf-8")
            assert "API V2 Content" in content2, \
                "Content of Reference_API_v2.md is incorrect."
            assert content2.encode("utf-8") == expected["Reference_API_v2.md"]

        actual = {}
        for member in files:
            extracted = tar.extractfile(member)
            assert extracted is not None
            actual[member.name] = extracted.read()
        assert actual == expected, \
            "Incremental archive does not exactly match the new and modified renamed files."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
