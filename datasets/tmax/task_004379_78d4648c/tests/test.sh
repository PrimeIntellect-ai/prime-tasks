#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import random
import secrets
import stat
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

CONFIG_PATH = "/home/user/config.json"
FILTER_SCRIPT = "/home/user/dataset_filter.py"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"


def test_config_generated_correctly():
    assert os.path.isfile(CONFIG_PATH), f"Missing generated configuration file: {CONFIG_PATH}"

    with open(CONFIG_PATH, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Configuration file {CONFIG_PATH} is not valid JSON.")

    assert "max_depth" in config, "Missing 'max_depth' in config.json"
    assert "max_files" in config, "Missing 'max_files' in config.json"

    assert config["max_depth"] == 5, f"Expected max_depth to be 5, got {config['max_depth']}"
    assert config["max_files"] == 42, f"Expected max_files to be 42, got {config['max_files']}"


def test_filter_script_exists():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing filter script: {FILTER_SCRIPT}"


def test_filter_script_behavior():
    assert os.path.isfile(FILTER_SCRIPT), "Filter script missing, cannot test behavior."

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]

    clean_failed = []
    evil_failed = []

    for c_file in clean_files:
        result = subprocess.run(["python3", FILTER_SCRIPT, c_file], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(c_file))

    for e_file in evil_files:
        result = subprocess.run(["python3", FILTER_SCRIPT, e_file], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(e_file))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_on_fresh_randomized_archives():
    assert os.path.isfile(FILTER_SCRIPT), "Filter script missing, cannot test behavior."
    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
    max_depth = config["max_depth"]
    max_files = config["max_files"]

    # Each entry is (kind, archive_name, contents_or_link_target).
    def regular(name):
        return ("file", name, os.urandom(random.randint(0, 192)))

    def symlink(name, target):
        return ("symlink", name, target)

    with tempfile.TemporaryDirectory(prefix="archive-check-") as work:
        cases = []

        def write_archive(fmt, entries, expected):
            suffix = ".zip" if fmt == "zip" else ".tar.gz"
            path = os.path.join(work, secrets.token_hex(16) + suffix)
            if fmt == "zip":
                with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                    for kind, name, value in entries:
                        if kind == "file":
                            archive.writestr(name, value)
                        else:
                            info = zipfile.ZipInfo(name)
                            info.create_system = 3
                            info.external_attr = (stat.S_IFLNK | 0o777) << 16
                            archive.writestr(info, value.encode("utf-8"))
            else:
                with tarfile.open(path, "w:gz") as archive:
                    for kind, name, value in entries:
                        info = tarfile.TarInfo(name=name)
                        if kind == "file":
                            info.size = len(value)
                            archive.addfile(info, io.BytesIO(value))
                        else:
                            info.type = tarfile.SYMTYPE
                            info.linkname = value
                            archive.addfile(info)
            cases.append((path, expected))

        for fmt in ("zip", "tar"):
            root = "d" + secrets.token_hex(5)

            # Ordinary safe archive with a randomized number of members.
            safe_count = random.randint(1, max(1, max_files - 1))
            write_archive(fmt, [regular(f"{root}/{secrets.token_hex(5)}_{i}") for i in range(safe_count)], 0)

            # The exact file-count boundary is valid; any randomized excess is not.
            write_archive(fmt, [regular(f"{root}/{secrets.token_hex(4)}_{i}") for i in range(max_files)], 0)
            excess = max_files + random.randint(1, 4)
            write_archive(fmt, [regular(f"{root}/{secrets.token_hex(4)}_{i}") for i in range(excess)], 1)

            # Unsafe member names must be detected from archive metadata.
            write_archive(fmt, [regular("/" + secrets.token_hex(12))], 1)
            write_archive(fmt, [regular(f"{root}/part/../../{secrets.token_hex(8)}")], 1)

            # A direct in-root symlink is safe.
            target = secrets.token_hex(8)
            write_archive(fmt, [regular(f"{root}/{target}"), symlink(f"{root}/current", target)], 0)

            # A chain exactly at the configured limit is safe.
            entries = [regular(f"{root}/target")]
            for i in range(max_depth):
                destination = f"link{i + 1}" if i + 1 < max_depth else "target"
                entries.append(symlink(f"{root}/link{i}", destination))
            write_archive(fmt, entries, 0)

            # One additional link exceeds the configured depth.
            entries = [regular(f"{root}/target")]
            for i in range(max_depth + 1):
                destination = f"link{i + 1}" if i < max_depth else "target"
                entries.append(symlink(f"{root}/link{i}", destination))
            write_archive(fmt, entries, 1)

            # Cycles and both relative and absolute escapes are unsafe.
            write_archive(fmt, [symlink(f"{root}/a", "b"), symlink(f"{root}/b", "a")], 1)
            write_archive(fmt, [symlink(f"{root}/pointer", "../../" + secrets.token_hex(8))], 1)
            write_archive(fmt, [symlink(f"{root}/pointer", "/" + secrets.token_hex(8))], 1)

        # Paths and execution order carry no clean/evil labels.
        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            try:
                result = subprocess.run(
                    ["python3", FILTER_SCRIPT, path],
                    capture_output=True,
                    timeout=8,
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual}")

        if failures:
            pytest.fail("Fresh archive checks failed: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
