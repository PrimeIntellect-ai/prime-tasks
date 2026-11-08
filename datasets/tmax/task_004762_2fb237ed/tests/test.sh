#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import tarfile

EXPECTED_METRICS_BYTES = b'''[
  {"id": 101, "value": 42.5, "status": "active"},
  {"id": 102, "value": 89.1, "status": "pending"},
  {"id": 103, "value": 12.0, "status": "error"}
]
'''
EXPECTED_DOC_BYTES = b"Document 1\n"


def test_symlink_deleted():
    loop_symlink = "/home/user/data/docs/logs/archive"
    assert not os.path.lexists(loop_symlink), f"The looping symlink {loop_symlink} was not deleted."


def test_archive_exists_and_dereferenced():
    archive_path = "/home/user/backup.tar.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} does not exist."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            # Preserve the original archive assertions.
            metrics_member = None
            for member in tar.getmembers():
                if member.name.endswith("data/metrics.json"):
                    metrics_member = member
                    break

            assert metrics_member is not None, "data/metrics.json was not found in the archive."
            assert metrics_member.isreg(), "data/metrics.json in the archive is not a regular file (symlinks were not dereferenced)."

            members = tar.getmembers()
            metric_candidates = []
            for member in members:
                name = member.name.rstrip("/")
                suffix = "data/metrics.json"
                if name.endswith(suffix):
                    prefix = name[:-len(suffix)]
                    if not prefix or prefix.endswith("/"):
                        metric_candidates.append((member, prefix))

            assert len(metric_candidates) == 1, "The archive must contain exactly one data/metrics.json tree."
            metrics_member, root_prefix = metric_candidates[0]

            expected_names = {
                root_prefix + "data": "dir",
                root_prefix + "data/docs": "dir",
                root_prefix + "data/docs/logs": "dir",
                root_prefix + "data/docs/doc1.txt": "file",
                root_prefix + "data/metrics.json": "file",
            }

            by_name = {}
            for member in members:
                normalized = member.name.rstrip("/")
                by_name.setdefault(normalized, []).append(member)
                assert not member.issym(), f"Symlink {member.name} was stored without dereferencing."

            for name, expected_type in expected_names.items():
                matches = by_name.get(name, [])
                assert len(matches) == 1, f"Required archive member {name} is missing or duplicated."
                member = matches[0]
                if expected_type == "dir":
                    assert member.isdir(), f"Required archive member {name} is not a directory."
                else:
                    assert member.isreg(), f"Required archive member {name} is not a regular file."

            archived_metrics = tar.extractfile(by_name[root_prefix + "data/metrics.json"][0])
            archived_doc = tar.extractfile(by_name[root_prefix + "data/docs/doc1.txt"][0])
            assert archived_metrics is not None
            assert archived_doc is not None
            assert archived_metrics.read() == EXPECTED_METRICS_BYTES, "Archived metrics.json content is incorrect."
            assert archived_doc.read() == EXPECTED_DOC_BYTES, "Archived docs/doc1.txt content is incorrect."
    except tarfile.ReadError:
        assert False, f"{archive_path} is not a valid gzip compressed tarball."


def test_csv_correct():
    csv_path = "/home/user/metrics.csv"
    assert os.path.isfile(csv_path), f"The CSV file {csv_path} does not exist."

    expected_csv = [
        "id,value,status",
        "101,42.5,active",
        "102,89.1,pending",
        "103,12.0,error"
    ]

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_csv, f"The contents of {csv_path} do not match the expected CSV format and data."

    with tarfile.open("/home/user/backup.tar.gz", "r:gz") as tar:
        candidates = [m for m in tar.getmembers() if m.name.rstrip("/").endswith("data/metrics.json") and m.isreg()]
        assert len(candidates) == 1
        extracted = tar.extractfile(candidates[0])
        assert extracted is not None
        metrics = json.loads(extracted.read().decode("utf-8"))

    with open(csv_path, "r", newline="") as f:
        rows = list(csv.reader(f))

    expected_rows = [["id", "value", "status"]] + [
        [str(item["id"]), str(item["value"]), item["status"]] for item in metrics
    ]
    assert rows == expected_rows, "metrics.csv was not correctly produced from the metrics stored in the archive."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
