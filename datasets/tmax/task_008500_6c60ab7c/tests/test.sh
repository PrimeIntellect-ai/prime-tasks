#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import csv
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile
import tempfile

import pytest

BASE_DIR = "/home/user/backups"
EXPECTED_TARGETS = ["node_alpha", "node_gamma"]
EXPECTED_CSV = {
    "node_alpha": b"file1.tmp,tmp,1048576,100\nfile2.log,log,5000,120\nfile3.cache,cache,2048,50\nfile4.cache,cache,5000000,95\n",
    "node_gamma": b"a.tmp,tmp,2000000,200\nb.cache,cache,150000,80\n",
}


def calculate_total(contents):
    total = 0
    for content in contents:
        reader = csv.reader(io.StringIO(content.decode("utf-8")))
        for row in reader:
            if len(row) < 4:
                continue
            try:
                size = int(row[2])
                days = int(row[3])
            except ValueError:
                continue
            if days > 90 and row[1] in ("tmp", "cache"):
                total += size
    return total


EXPECTED_TOTAL = calculate_total(EXPECTED_CSV.values())


def get_expected_targets():
    config_path = "/home/user/backups/storage_policy.ini"
    assert os.path.isfile(config_path), f"Missing {config_path}"
    config = configparser.ConfigParser()
    config.read(config_path)
    assert "Policy" in config, "Missing [Policy] section in storage_policy.ini"
    assert "target_dirs" in config["Policy"], "Missing target_dirs in [Policy]"
    targets = [d.strip() for d in config["Policy"]["target_dirs"].split(",") if d.strip()]
    assert targets == EXPECTED_TARGETS, \
        f"storage_policy.ini target_dirs was modified: expected {EXPECTED_TARGETS}, found {targets}"
    return list(EXPECTED_TARGETS)


def compute_expected_reclaimable_bytes():
    # Expectations are immutable rather than being derived from agent-writable inputs.
    return EXPECTED_TOTAL


def test_policy_source_archives_and_extraction():
    assert get_expected_targets() == EXPECTED_TARGETS

    for target, expected_content in EXPECTED_CSV.items():
        tar_path = os.path.join(BASE_DIR, target, "data.tar.gz")
        assert os.path.isfile(tar_path), f"Missing archive {tar_path}"
        with tarfile.open(tar_path, "r:gz") as tar:
            member = tar.getmember("usage.csv")
            assert member.isfile(), f"usage.csv in {tar_path} is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == expected_content, f"Original usage.csv content changed in {tar_path}"

        csv_path = os.path.join(BASE_DIR, target, "usage.csv")
        assert os.path.isfile(csv_path) and not os.path.islink(csv_path), f"Missing extracted {csv_path}"
        with open(csv_path, "rb") as f:
            assert f.read() == expected_content, f"Extracted content mismatch for {csv_path}"

    assert not os.path.exists(os.path.join(BASE_DIR, "node_alpha", "dummy.txt")), \
        "dummy.txt must not be extracted"
    assert not os.path.exists(os.path.join(BASE_DIR, "node_gamma", "notes.md")), \
        "notes.md must not be extracted"
    assert not os.path.exists(os.path.join(BASE_DIR, "node_beta", "usage.csv")), \
        "The non-target node_beta must be ignored"


def _reported_total(stdout, expected):
    text = stdout.decode("utf-8", errors="replace")
    numbers = re.findall(r"(?<!\d)\d+(?!\d)", text)
    if numbers and int(numbers[-1]) == expected:
        return True

    manifest_path = "/home/user/reclaim_manifest.json"
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return set(data) == {"reclaimable_bytes"} and data["reclaimable_bytes"] == expected
        except (OSError, ValueError, TypeError):
            return False
    return False


def _exercise_analyzer(binary, synthetic):
    csv_paths = {target: os.path.join(BASE_DIR, target, "usage.csv") for target in EXPECTED_TARGETS}
    originals = {}
    manifest_path = "/home/user/reclaim_manifest.json"
    manifest_original = None
    manifest_existed = os.path.isfile(manifest_path)

    for target, path in csv_paths.items():
        with open(path, "rb") as f:
            originals[target] = f.read()

    if manifest_existed:
        with open(manifest_path, "rb") as f:
            manifest_original = f.read()

    expected = calculate_total(synthetic.values())
    try:
        for target, content in synthetic.items():
            with open(csv_paths[target], "wb") as f:
                f.write(content)
        if os.path.lexists(manifest_path):
            os.unlink(manifest_path)

        result = subprocess.run(
            [binary], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=False
        )
        assert result.returncode == 0, \
            f"{binary} exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
        assert _reported_total(result.stdout, expected), \
            f"{binary} did not report or write the calculated total {expected}"
    finally:
        for target, content in originals.items():
            with open(csv_paths[target], "wb") as f:
                f.write(content)
        if os.path.lexists(manifest_path):
            os.unlink(manifest_path)
        if manifest_existed:
            with open(manifest_path, "wb") as f:
                f.write(manifest_original)


def test_analyzer_c_exists_and_runs():
    source = "/home/user/analyzer.c"
    binary = "/home/user/analyzer"
    assert os.path.isfile(source) and not os.path.islink(source), \
        "The C source file /home/user/analyzer.c is missing or is not a regular file."
    assert os.path.isfile(binary) and not os.path.islink(binary), \
        "The compiled executable /home/user/analyzer is missing or is not a regular file."
    assert os.access(binary, os.X_OK), f"{binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable"

    rebuilt = "/tmp/analyzer_from_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False
    )
    assert compile_result.returncode == 0, \
        f"analyzer.c does not compile: {compile_result.stderr.decode(errors='replace')}"

    installed_case = {
        "node_alpha": b"one.tmp,tmp,11,91\ntwo.cache,cache,7,90\nthree.log,log,900,200\n",
        "node_gamma": b"four.cache,cache,13,100\n",
    }
    rebuilt_case = {
        "node_alpha": b"a.cache,cache,101,500\nb.tmp,tmp,19,1\n",
        "node_gamma": b"c.tmp,tmp,37,91\nd.cache,cache,5,200\n",
    }
    _exercise_analyzer(binary, installed_case)
    _exercise_analyzer(rebuilt, rebuilt_case)


def test_reclaim_manifest_json():
    manifest_path = "/home/user/reclaim_manifest.json"
    assert os.path.isfile(manifest_path), f"Missing {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{manifest_path} is not valid JSON.")

    assert "reclaimable_bytes" in data, f"Key 'reclaimable_bytes' missing in {manifest_path}"
    assert set(data) == {"reclaimable_bytes"}, \
        f"{manifest_path} must contain exactly the reclaimable_bytes key"
    assert type(data["reclaimable_bytes"]) is int, "reclaimable_bytes must be a JSON integer"

    expected_bytes = compute_expected_reclaimable_bytes()
    assert data["reclaimable_bytes"] == expected_bytes, \
        f"Expected reclaimable_bytes to be {expected_bytes}, but got {data['reclaimable_bytes']}"


def test_reclaim_data_tar_gz():
    tar_path = "/home/user/reclaim_data.tar.gz"
    assert os.path.isfile(tar_path), f"Missing {tar_path}"

    expected_targets = get_expected_targets()
    expected_members = set(f"{target}/usage.csv" for target in expected_targets)

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            members = tar.getmembers()
            names = [member.name for member in members]
            actual_files = set(member.name for member in members if not member.isdir())

            assert actual_files == expected_members, \
                f"Archive contents mismatch. Expected files: {expected_members}, Found: {actual_files}"
            assert len(names) == len(expected_members), "Archive contains directories, duplicates, or extra entries"

            for target in expected_targets:
                name = f"{target}/usage.csv"
                matches = [member for member in members if member.name == name]
                assert len(matches) == 1, f"Expected exactly one {name} member"
                assert matches[0].isfile(), f"{name} is not a regular file"
                f = tar.extractfile(matches[0])
                assert f is not None
                assert f.read() == EXPECTED_CSV[target], f"Content mismatch for archive member {name}"
    except tarfile.ReadError:
        pytest.fail(f"{tar_path} is not a valid gzip-compressed tar archive.")


def test_reclaim_data_sha256():
    tar_path = "/home/user/reclaim_data.tar.gz"
    sha_path = "/home/user/reclaim_data.sha256"

    assert os.path.isfile(tar_path), f"Missing {tar_path} needed for checksum verification."
    assert os.path.isfile(sha_path), f"Missing {sha_path}"

    hasher = hashlib.sha256()
    with open(tar_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    expected_hash = hasher.hexdigest()

    with open(sha_path, "r") as f:
        content = f.read().strip()

    actual_hash = content.split()[0] if content else ""
    assert actual_hash == expected_hash, \
        f"Checksum mismatch. Expected {expected_hash}, but found {actual_hash} in {sha_path}"
    assert re.fullmatch(r"[0-9a-fA-F]{64}\s+[ *]/home/user/reclaim_data\.tar\.gz", content), \
        f"{sha_path} is not in standard sha256sum output format"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
