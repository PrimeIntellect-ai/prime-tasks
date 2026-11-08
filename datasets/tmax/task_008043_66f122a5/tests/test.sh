#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

ARCHIVE_PATH = "/home/user/incremental_update.tar.gz"
LEGACY_ROOT = Path("/home/user/legacy_backups")
RESTORED_ROOT = Path("/home/user/restored")
REFERENCE_PATH = Path("/home/user/last_backup.ref")


def source_files():
    """Derive expected data, types, and mtimes from the supplied nested archives."""
    result = {}
    zip_paths = sorted(LEGACY_ROOT.rglob("*.zip"))
    assert zip_paths, "No source zip archives were found."

    for zip_path in zip_paths:
        with zipfile.ZipFile(zip_path) as zf:
            tar_names = [name for name in zf.namelist() if name.lower().endswith(".tar")]
            assert tar_names, f"No tar archive found inside {zip_path}."
            for tar_name in tar_names:
                with zf.open(tar_name) as nested_tar_file:
                    tar_bytes = nested_tar_file.read()
                with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as nested_tar:
                    for member in nested_tar.getmembers():
                        if not member.isfile():
                            continue
                        name = member.name
                        assert not name.startswith("/")
                        assert ".." not in PurePosixPath(name).parts
                        extracted = nested_tar.extractfile(member)
                        assert extracted is not None
                        assert name not in result, f"Duplicate source data path: {name}"
                        result[name] = {
                            "data": extracted.read(),
                            "mtime": member.mtime,
                        }

    assert result, "No data files were found in the nested source archives."
    return result


def normalized_archive_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name


def test_incremental_update_archive_exists_and_valid():
    archive_path = ARCHIVE_PATH
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."


def test_incremental_update_archive_contents():
    archive_path = ARCHIVE_PATH
    assert os.path.isfile(archive_path), "Archive is missing, cannot check contents."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            members = tar.getnames()
    except tarfile.ReadError:
        assert False, f"Failed to read {archive_path} as a gzipped tar archive."

    # Preserve the original exact member-name assertion.
    cleaned_members = set(m.lstrip("./") for m in members)
    cleaned_members.discard("")
    expected_files = {"file2.txt", "file3.txt"}
    assert cleaned_members == expected_files, (
        "Archive contents do not match expected incremental files.\n"
        f"Expected: {expected_files}\n"
        f"Got: {cleaned_members}"
    )


def test_extraction_contents_mtimes_and_incremental_payload():
    expected_all = source_files()
    reference_mtime = REFERENCE_PATH.stat().st_mtime
    expected_new = {
        name: metadata
        for name, metadata in expected_all.items()
        if metadata["mtime"] > reference_mtime
    }
    assert set(expected_new) == {"file2.txt", "file3.txt"}

    # Verify that every source data file was actually restored, with its original
    # contents and mtime. Both flat and structured staging layouts are accepted.
    assert RESTORED_ROOT.is_dir(), f"Missing staging directory {RESTORED_ROOT}"
    restored_files = [path for path in RESTORED_ROOT.rglob("*") if path.is_file()]
    for source_name, metadata in expected_all.items():
        candidates = []
        for path in restored_files:
            relative = path.relative_to(RESTORED_ROOT).as_posix()
            if relative == source_name or relative.endswith("/" + source_name):
                candidates.append(path)
        assert candidates, f"Source data file {source_name} was not extracted under {RESTORED_ROOT}."
        assert any(
            path.read_bytes() == metadata["data"]
            and abs(path.stat().st_mtime - metadata["mtime"]) <= 1.0
            for path in candidates
        ), f"No restored copy of {source_name} has the original contents and mtime."

    with tarfile.open(ARCHIVE_PATH, "r:gz") as final_tar:
        members = final_tar.getmembers()
        normalized = []
        for member in members:
            assert not member.name.startswith("/"), "Archive contains an absolute path."
            name = normalized_archive_name(member.name)
            assert name and ".." not in PurePosixPath(name).parts, (
                f"Archive contains an unsafe path: {member.name}"
            )
            normalized.append(name)

        assert len(normalized) == len(expected_new), (
            "Archive contains duplicate or extra member entries."
        )
        assert set(normalized) == set(expected_new), (
            f"Expected dynamically derived newer files {set(expected_new)}, got {set(normalized)}"
        )

        for member, name in zip(members, normalized):
            expected = expected_new[name]
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            payload = final_tar.extractfile(member)
            assert payload is not None
            assert payload.read() == expected["data"], (
                f"Archive member {member.name} has incorrect contents."
            )
            assert abs(member.mtime - expected["mtime"]) <= 1.0, (
                f"Archive member {member.name} does not preserve the source mtime."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
