#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

EXPECTED_FILES = {
    "2023-01-15_sensorA.csv": {"year": "2023", "month": "01", "sensor": "sensorA"},
    "2023-02-20_sensorB.json": {"year": "2023", "month": "02", "sensor": "sensorB"},
    "2022-11-05_sensorA.json": {"year": "2022", "month": "11", "sensor": "sensorA"},
    "2023-01-16_sensorC.csv": {"year": "2023", "month": "01", "sensor": "sensorC"},
    "2022-12-25_sensorB.csv": {"year": "2022", "month": "12", "sensor": "sensorB"},
    "2022-12-26_sensorA.csv": {"year": "2022", "month": "12", "sensor": "sensorA"},
}

def test_summary_log():
    log_path = "/home/user/summary.log"
    assert os.path.exists(log_path), f"Log file missing: {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "6", f"Expected summary.log to contain '6', got '{content}'"

def test_clean_datasets_structure():
    clean_dir = "/home/user/clean_datasets"
    assert os.path.exists(clean_dir), f"Directory missing: {clean_dir}"

    found_files = []
    for root, dirs, files in os.walk(clean_dir):
        for file in files:
            found_files.append(os.path.join(root, file))

    assert len(found_files) == len(EXPECTED_FILES), f"Expected exactly {len(EXPECTED_FILES)} files in clean_datasets, found {len(found_files)}: {found_files}"

    for filename, meta in EXPECTED_FILES.items():
        expected_path = os.path.join(clean_dir, meta["year"], meta["month"], filename)
        assert os.path.exists(expected_path), f"Expected file missing: {expected_path}"
        assert os.path.isfile(expected_path), f"Not a file: {expected_path}"

def test_sensor_views_symlinks():
    views_dir = "/home/user/sensor_views"
    clean_dir = "/home/user/clean_datasets"
    assert os.path.exists(views_dir), f"Directory missing: {views_dir}"

    found_links = []
    for root, dirs, files in os.walk(views_dir):
        for file in files:
            found_links.append(os.path.join(root, file))

    assert len(found_links) == len(EXPECTED_FILES), f"Expected exactly {len(EXPECTED_FILES)} symlinks in sensor_views, found {len(found_links)}"

    for filename, meta in EXPECTED_FILES.items():
        link_path = os.path.join(views_dir, meta["sensor"], filename)
        expected_target = os.path.join(clean_dir, meta["year"], meta["month"], filename)

        assert os.path.exists(link_path), f"Symlink missing: {link_path}"
        assert os.path.islink(link_path), f"Path is not a symlink: {link_path}"

        target = os.readlink(link_path)
        assert target == expected_target, f"Symlink {link_path} points to {target}, expected absolute path {expected_target}"

def test_final_archive():
    archive_path = "/home/user/final_dataset.tar.gz"
    assert os.path.exists(archive_path), f"Final archive missing: {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"Not a valid tar file: {archive_path}"

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()

        # Check that the archive contains the clean_datasets folder at its root
        # This means paths should start with clean_datasets/ or ./clean_datasets/
        valid_prefixes = ("clean_datasets", "./clean_datasets")
        has_clean_datasets = any(name.startswith(valid_prefixes) for name in names)
        assert has_clean_datasets, f"Archive does not contain 'clean_datasets' folder at root. Contents: {names}"

        # Check that all expected files are in the archive
        for filename, meta in EXPECTED_FILES.items():
            expected_suffix = f"{meta['year']}/{meta['month']}/{filename}"
            found = any(name.endswith(expected_suffix) for name in names)
            assert found, f"Expected file ending with {expected_suffix} not found in archive."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
