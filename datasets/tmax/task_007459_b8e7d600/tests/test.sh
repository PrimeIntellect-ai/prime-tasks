#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import random
import secrets
import shutil
import subprocess
import tarfile
import tempfile

import pytest


def test_filter_executable_exists():
    executable_path = "/home/user/filter"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."

    source_path = "/home/user/filter.c"
    assert os.path.isfile(source_path), f"C source {source_path} does not exist."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."


def _random_filter_case():
    levels = ["INFO", "DEBUG", "WARNING", "ERROR", "CRITICAL", "INFO", "ERROR"]
    random.SystemRandom().shuffle(levels)
    records = []
    expected = []
    for index, level in enumerate(levels):
        record = (
            "BEGIN_RECORD\n"
            f"ID: {secrets.randbelow(900000) + 100000 + index}\n"
            f"LEVEL: {level}\n"
            f"MESSAGE: dynamic-{secrets.token_hex(12)}-{index}\n"
            "END_RECORD\n"
        )
        records.append(record)
        if level in ("ERROR", "CRITICAL"):
            expected.append(record)
    return "".join(records), "".join(expected)


def _assert_filter_behavior(executable):
    input_text, expected = _random_filter_case()
    result = subprocess.run(
        [executable],
        input=input_text.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert result.stdout.decode(errors="strict").strip() == expected.strip(), (
        "Filter did not retain exactly the ERROR and CRITICAL records on dynamic input."
    )


def test_filter_behavior_and_source():
    _assert_filter_behavior("/home/user/filter")
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "filter-from-source")
        compile_result = subprocess.run(
            ["gcc", "/home/user/filter.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert compile_result.returncode == 0, compile_result.stderr.decode(errors="replace")
        _assert_filter_behavior(rebuilt)


def test_processed_log1():
    expected = (
        "BEGIN_RECORD\n"
        "ID: 102\n"
        "LEVEL: ERROR\n"
        "MESSAGE: Disk space low\n"
        "END_RECORD"
    )
    path = "/home/user/data/processed_logs/log1.log"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected, f"Content of {path} is incorrect. Expected ERROR record only."


def test_processed_log2():
    expected = (
        "BEGIN_RECORD\n"
        "ID: 201\n"
        "LEVEL: CRITICAL\n"
        "MESSAGE: Kernel panic\n"
        "END_RECORD"
    )
    path = "/home/user/data/processed_logs/log2.log"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected, f"Content of {path} is incorrect. Expected CRITICAL record only."


def _independent_filter(data):
    lines = data.decode("utf-8").splitlines(keepends=True)
    output = []
    current = []
    in_record = False
    for line in lines:
        if line.rstrip("\r\n") == "BEGIN_RECORD":
            assert not in_record
            in_record = True
            current = [line]
        elif in_record:
            current.append(line)
            if line.rstrip("\r\n") == "END_RECORD":
                level_lines = [x.rstrip("\r\n") for x in current if x.startswith("LEVEL: ")]
                assert len(level_lines) == 1
                if level_lines[0] in ("LEVEL: ERROR", "LEVEL: CRITICAL"):
                    output.extend(current)
                current = []
                in_record = False
    assert not in_record
    return "".join(output).strip()


def test_all_gzip_inputs_were_processed_correctly():
    gz_paths = sorted(glob.glob("/home/user/data/raw_logs/*.gz"))
    assert gz_paths, "No gzip input logs were found."
    for gz_path in gz_paths:
        output_name = os.path.basename(gz_path)[:-3] + ".log"
        output_path = os.path.join("/home/user/data/processed_logs", output_name)
        assert os.path.isfile(output_path), f"{output_path} does not exist."
        with gzip.open(gz_path, "rb") as f:
            expected = _independent_filter(f.read())
        with open(output_path, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == expected, f"{output_path} does not match its compressed input."


def _normalized(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def test_incremental_backup():
    tar_path = "/home/user/data/inc_backup.tar"
    assert os.path.isfile(tar_path), f"Backup archive {tar_path} does not exist."

    try:
        with tarfile.open(tar_path, "r") as tar:
            members = tar.getmembers()
            names = tar.getnames()

            # Check that the archived paths are relative to processed_logs/
            assert any("processed_logs/log1.log" in name for name in names), "processed_logs/log1.log is missing from the incremental backup."
            assert any("processed_logs/log2.log" in name for name in names), "processed_logs/log2.log is missing from the incremental backup."

            # Ensure the old log is not included, as it was in the base backup
            assert not any("old_log.log" in name for name in names), "processed_logs/old_log.log should NOT be in the incremental backup."

            normalized = {_normalized(member.name): member for member in members}
            regular_names = {_normalized(member.name) for member in members if member.isfile()}
            assert regular_names == {"processed_logs/log1.log", "processed_logs/log2.log"}, (
                f"Unexpected regular files in incremental archive: {sorted(regular_names)}"
            )
            for name in sorted(regular_names):
                archived = tar.extractfile(normalized[name])
                assert archived is not None
                with open(os.path.join("/home/user/data", name), "rb") as current:
                    assert archived.read() == current.read(), f"Archived content of {name} is incorrect."

            assert any(
                _normalized(member.name) == "processed_logs" and member.type == tarfile.GNUTYPE_DUMPDIR
                for member in members
            ), "Archive lacks GNU incremental directory metadata."
    except tarfile.ReadError:
        pytest.fail(f"Could not read {tar_path} as a valid tar archive.")


def test_existing_snapshot_was_updated_by_incremental_backup():
    snapshot = "/home/user/data/snapshot.snar"
    assert os.path.isfile(snapshot), f"Snapshot file {snapshot} does not exist."

    data_dir = "/home/user/data"
    processed_dir = os.path.join(data_dir, "processed_logs")
    probe_name = f"snapshot_probe_{secrets.token_hex(8)}.log"
    probe_path = os.path.join(processed_dir, probe_name)

    with tempfile.TemporaryDirectory() as td:
        snapshot_copy = os.path.join(td, "snapshot.snar")
        probe_tar = os.path.join(td, "probe.tar")
        shutil.copy2(snapshot, snapshot_copy)
        try:
            with open(probe_path, "w", encoding="utf-8") as f:
                f.write("snapshot probe\n")
            result = subprocess.run(
                ["tar", "-cg", snapshot_copy, "-C", data_dir, "-f", probe_tar, "processed_logs"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                check=False,
            )
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            with tarfile.open(probe_tar, "r") as tar:
                regular = {_normalized(m.name) for m in tar.getmembers() if m.isfile()}
            assert f"processed_logs/{probe_name}" in regular, "Updated snapshot did not detect a new file."
            assert "processed_logs/old_log.log" not in regular
            assert "processed_logs/log1.log" not in regular
            assert "processed_logs/log2.log" not in regular
        finally:
            if os.path.exists(probe_path):
                os.remove(probe_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
