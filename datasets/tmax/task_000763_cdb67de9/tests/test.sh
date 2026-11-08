#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tarfile
import tempfile
import pytest

EXECUTABLE = "/home/user/backup_filter"
RAW_DATA = "/home/user/raw_data"
SAFE_DATA = "/home/user/safe_data"
TARBALL = "/home/user/backup.tar.gz"


def policy_result(content):
    return 1 if content.startswith(b"EVIL") or b"DO_NOT_BACKUP" in content else 0


def expected_safe_files():
    expected = {}
    for filename in os.listdir(RAW_DATA):
        filepath = os.path.join(RAW_DATA, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "rb") as f:
            content = f.read()
        if policy_result(content) == 0:
            expected[filename + ".safe"] = content
    return expected


def test_backup_filter_executable():
    """Check if the backup_filter program exists, is executable, and is a compiled binary."""
    assert os.path.isfile(EXECUTABLE), f"Missing executable at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backup_filter is not an ELF executable"


def test_backup_filter_evil_corpus():
    """Check if the backup_filter correctly rejects evil files."""
    evil_dir = "/app/verifier_corpus/evil"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory at {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "Evil corpus directory is empty"

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, timeout=5)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_files)}")


def test_backup_filter_clean_corpus():
    """Check if the backup_filter correctly accepts clean files."""
    clean_dir = "/app/verifier_corpus/clean"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory at {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "Clean corpus directory is empty"

    rejected_files = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, timeout=5)
        if result.returncode != 0:
            rejected_files.append(os.path.basename(filepath))

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean files rejected: {', '.join(rejected_files)}")


def test_backup_filter_generated_inputs():
    """Exercise the executable on fresh, unpredictably named binary inputs."""
    cases = [
        b"",
        b"EVIL" + os.urandom(37),
        b"EVIL",
        os.urandom(17) + b"DO_NOT_BACKUP" + os.urandom(29),
        b"\x00\xffEVIL" + os.urandom(19),
        b"evil" + os.urandom(23),
        b"DO_NOT_BACKUQ" + os.urandom(31),
        os.urandom(8191) + b"DO_NOT_BACKUP" + os.urandom(11),
    ]

    for _ in range(24):
        kind = secrets.randbelow(4)
        before = os.urandom(secrets.randbelow(5000) + 1)
        after = os.urandom(secrets.randbelow(3000))
        if kind == 0:
            content = b"EVIL" + before + after
        elif kind == 1:
            content = before + b"DO_NOT_BACKUP" + after
        elif kind == 2:
            content = before + b"EVIL" + after
        else:
            content = before + b"DO_NOT_BACKU" + after
        cases.append(content)

    with tempfile.TemporaryDirectory(prefix="filter-check-") as tempdir:
        failures = []
        for content in cases:
            name = secrets.token_hex(18)
            path = os.path.join(tempdir, name)
            with open(path, "wb") as f:
                f.write(content)
            expected = policy_result(content)
            result = subprocess.run([EXECUTABLE, path], capture_output=True, timeout=5)
            if result.returncode != expected:
                failures.append(f"{name}: expected {expected}, got {result.returncode}")
        assert not failures, "Generated-input failures: " + "; ".join(failures)


def test_backup_tarball_exists_and_valid():
    """Check if the backup tarball exists and is a valid gzip-compressed tarball."""
    assert os.path.isfile(TARBALL), f"Missing backup tarball at {TARBALL}"
    assert tarfile.is_tarfile(TARBALL), f"File at {TARBALL} is not a valid tarball"

    with open(TARBALL, 'rb') as f:
        magic = f.read(2)
        assert magic == b'\x1f\x8b', f"File at {TARBALL} is not gzip compressed"


def test_backup_tarball_contents():
    """Check if the tarball contains the correctly renamed safe files."""
    assert os.path.isfile(TARBALL), f"Missing backup tarball at {TARBALL}"
    assert os.path.isdir(RAW_DATA), f"Missing raw data directory at {RAW_DATA}"

    expected_safe_files = set(expected_safe_files_dict.keys())

    with tarfile.open(TARBALL, "r:gz") as tar:
        tar_members = tar.getnames()

    tar_basenames = {os.path.basename(m) for m in tar_members if not m.endswith('/')}
    missing_files = expected_safe_files - tar_basenames
    extra_files = tar_basenames - expected_safe_files

    error_msgs = []
    if missing_files:
        error_msgs.append(f"Missing safe files in tarball: {', '.join(missing_files)}")
    if extra_files:
        error_msgs.append(f"Unexpected files in tarball: {', '.join(extra_files)}")
    if error_msgs:
        pytest.fail("; ".join(error_msgs))


# Snapshot expected names and bytes when the tests are loaded.
expected_safe_files_dict = expected_safe_files()


def test_safe_data_files_and_contents():
    """Verify safe_data contains exact copies of all and only safe raw files."""
    assert os.path.isdir(SAFE_DATA), f"Missing safe data directory at {SAFE_DATA}"
    actual_names = {
        name for name in os.listdir(SAFE_DATA)
        if os.path.isfile(os.path.join(SAFE_DATA, name))
    }
    assert actual_names == set(expected_safe_files_dict), (
        f"safe_data names differ: expected {sorted(expected_safe_files_dict)}, got {sorted(actual_names)}"
    )
    for name, expected_content in expected_safe_files_dict.items():
        with open(os.path.join(SAFE_DATA, name), "rb") as f:
            assert f.read() == expected_content, f"safe_data file {name} is not an exact copy"


def test_backup_tarball_file_contents():
    """Verify each archived safe file occurs once, is regular, and has exact source bytes."""
    with tarfile.open(TARBALL, "r:gz") as tar:
        file_members = [m for m in tar.getmembers() if not m.isdir()]
        by_basename = {}
        for member in file_members:
            by_basename.setdefault(os.path.basename(member.name), []).append(member)

        assert set(by_basename) == set(expected_safe_files_dict), (
            f"Archived file names differ: expected {sorted(expected_safe_files_dict)}, got {sorted(by_basename)}"
        )
        for name, expected_content in expected_safe_files_dict.items():
            members = by_basename[name]
            assert len(members) == 1, f"Archived file {name} occurs {len(members)} times"
            member = members[0]
            assert member.isfile(), f"Archived entry {name} is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Cannot read archived file {name}"
            assert extracted.read() == expected_content, f"Archived file {name} has incorrect contents"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
