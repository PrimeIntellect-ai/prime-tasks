#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
from collections import Counter

import pytest

WORKSPACE = "/home/user/workspace"
TRACKER = os.path.join(WORKSPACE, "tracker")
SOURCE = os.path.join(WORKSPACE, "tracker.c")
SNAP1 = os.path.join(WORKSPACE, "snapshot1.txt")
SNAP2 = os.path.join(WORKSPACE, "snapshot2.txt")


def parse_snapshot(path):
    records = {}
    with open(path, "r") as f:
        for number, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            assert line, f"Blank line in {path} at line {number}."
            try:
                filename, size, mtime = line.rsplit(" ", 2)
                size = int(size)
                mtime = int(mtime)
            except (ValueError, TypeError):
                pytest.fail(f"Malformed snapshot record in {path} at line {number}: {line!r}")
            assert os.path.isabs(filename), f"Snapshot path is not absolute: {filename!r}"
            assert filename not in records, f"Duplicate snapshot path in {path}: {filename}"
            records[filename] = (size, mtime)
    return records


def assert_record_matches_file(records, path):
    assert path in records, f"{path} is missing from the snapshot."
    st = os.stat(path)
    assert records[path] == (st.st_size, int(st.st_mtime)), (
        f"Incorrect size/mtime for {path}: got {records[path]}, "
        f"expected {(st.st_size, int(st.st_mtime))}"
    )


def exercise_tracker(executable):
    with tempfile.TemporaryDirectory(prefix="tracker-test-") as base:
        root = os.path.join(base, "root")
        local = os.path.join(root, "local")
        external = os.path.join(base, "external")
        os.makedirs(local)
        os.makedirs(external)

        root_file = os.path.join(root, "root.txt")
        local_file = os.path.join(local, "local.txt")
        external_file = os.path.join(external, "linked.txt")
        with open(root_file, "wb") as f:
            f.write(b"root-data\n")
        with open(local_file, "wb") as f:
            f.write(b"local-data\n")
        with open(external_file, "wb") as f:
            f.write(b"linked-data\n")

        # Multiple names for existing directories plus a genuine cycle. The
        # external directory is reachable only by following a directory symlink.
        os.symlink("local", os.path.join(root, "local_alias"))
        os.symlink(external, os.path.join(root, "external_link"))
        os.symlink(root, os.path.join(external, "back_to_root"))

        output = os.path.join(base, "snapshot.txt")
        result = subprocess.run(
            [executable, root + "/", output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        assert result.returncode == 0, (
            f"{executable} failed with status {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(output), f"{executable} did not create its output file."

        records = parse_snapshot(output)
        expected_files = [root_file, local_file, external_file]
        expected_ids = Counter((os.stat(p).st_dev, os.stat(p).st_ino) for p in expected_files)
        actual_ids = Counter()

        for path, metadata in records.items():
            try:
                st = os.stat(path)
            except OSError as exc:
                pytest.fail(f"Snapshot contains an unusable path {path!r}: {exc}")
            assert stat.S_ISREG(st.st_mode), f"Snapshot contains a non-regular file: {path}"
            assert metadata == (st.st_size, int(st.st_mtime)), (
                f"Incorrect metadata for {path}: got {metadata}, "
                f"expected {(st.st_size, int(st.st_mtime))}"
            )
            actual_ids[(st.st_dev, st.st_ino)] += 1

        assert actual_ids == expected_ids, (
            "Tracker did not follow all unvisited directory symlinks exactly once, "
            f"or revisited a directory inode. Got inode counts {actual_ids}; "
            f"expected {expected_ids}."
        )


def test_tracker_executable():
    executable_path = "/home/user/workspace/tracker"
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing."
    st = os.stat(executable_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."


def test_source_uses_directory_device_and_inode_tracking():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    source = open(SOURCE, "r").read()
    for token in ("dev_t", "ino_t", "st_dev", "st_ino"):
        assert re.search(r"\b" + re.escape(token) + r"\b", source), (
            f"tracker.c does not use required directory identity field/type {token}."
        )

    with tempfile.TemporaryDirectory(prefix="tracker-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "tracker")
        result = subprocess.run(
            ["gcc", SOURCE, "-O2", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            text=True,
        )
        assert result.returncode == 0, f"tracker.c does not compile: {result.stderr}"
        exercise_tracker(rebuilt)


def test_submitted_tracker_handles_inode_cycles():
    exercise_tracker(TRACKER)


def test_snapshots_exist_and_finite():
    snap1 = "/home/user/workspace/snapshot1.txt"
    snap2 = "/home/user/workspace/snapshot2.txt"

    assert os.path.isfile(snap1), f"Snapshot file {snap1} is missing."
    assert os.path.isfile(snap2), f"Snapshot file {snap2} is missing."

    size1 = os.path.getsize(snap1)
    size2 = os.path.getsize(snap2)

    assert size1 < 100 * 1024, f"{snap1} is too large ({size1} bytes). The infinite loop might not be fixed."
    assert size2 < 100 * 1024, f"{snap2} is too large ({size2} bytes). The infinite loop might not be fixed."

    assert size1 > 0, f"{snap1} is empty."
    assert size2 > 0, f"{snap2} is empty."


def test_snapshot_contents_and_metadata():
    first = parse_snapshot(SNAP1)
    second = parse_snapshot(SNAP2)

    config = "/home/user/config_root/app1/config.json"
    settings = "/home/user/config_root/app2/settings.conf"
    new_config = "/home/user/config_root/app1/new_config.txt"

    assert set(first) == {config, settings}, f"Unexpected baseline snapshot paths: {sorted(first)}"
    assert set(second) == {config, settings, new_config}, (
        f"Unexpected secondary snapshot paths: {sorted(second)}"
    )

    assert_record_matches_file(first, config)
    assert_record_matches_file(second, config)
    assert_record_matches_file(second, settings)
    assert_record_matches_file(second, new_config)

    assert first[settings][0] == len(b"LOG_LEVEL=info\n"), (
        "The baseline snapshot does not describe settings.conf before DEBUG=true was appended."
    )
    assert first[settings][1] <= second[settings][1], (
        "The baseline settings.conf timestamp is later than the secondary timestamp."
    )


def test_configuration_changes():
    settings_path = "/home/user/config_root/app2/settings.conf"
    assert os.path.isfile(settings_path), f"{settings_path} is missing."
    with open(settings_path, "r") as f:
        content = f.read()
    assert "DEBUG=true" in content, f"'DEBUG=true' was not appended to {settings_path}."

    new_config_path = "/home/user/config_root/app1/new_config.txt"
    assert os.path.isfile(new_config_path), f"{new_config_path} is missing."
    with open(new_config_path, "r") as f:
        content = f.read().strip()
    assert content == "version=2", f"{new_config_path} does not contain the correct text."


def test_diff_report():
    report_path = "/home/user/diff_report.txt"
    assert os.path.isfile(report_path), f"Diff report {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/config_root/app1/new_config.txt",
        "/home/user/config_root/app2/settings.conf"
    ]

    assert lines == expected_lines, f"Contents of {report_path} do not match the expected sorted diff. Got: {lines}"

    first = parse_snapshot(SNAP1)
    second = parse_snapshot(SNAP2)
    derived = sorted(
        path for path, metadata in second.items()
        if path not in first or first[path] != metadata
    )
    assert lines == derived, (
        f"Diff report was not derived correctly from the two snapshots: expected {derived}, got {lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
