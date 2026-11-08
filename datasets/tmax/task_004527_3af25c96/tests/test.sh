#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import glob
import io
import gzip
import tarfile
import zipfile
import subprocess
import tempfile
from collections import Counter, defaultdict
import pytest

SOURCE_ARCHIVE = "/home/user/legacy_logs.tar"


def record_signature(records):
    """Represent a log file's records as an order-independent, duplicate-aware value."""
    rows = Counter(
        (item["timestamp"], item["level"], item["module"], item["message"])
        for item in records
    )
    return tuple(sorted(rows.items()))


def expected_outputs():
    """Derive the expected ERROR records directly from the supplied nested archive."""
    expected = defaultdict(list)

    with tarfile.open(SOURCE_ARCHIVE, "r") as tf:
        zip_members = sorted(
            member for member in tf.getmembers()
            if member.isfile() and member.name.endswith(".zip")
        )
        assert len(zip_members) == 2, f"Expected 2 server ZIP files, found {len(zip_members)}"

        for zip_member in zip_members:
            extracted = tf.extractfile(zip_member)
            assert extracted is not None, f"Could not read {zip_member.name}"
            with zipfile.ZipFile(io.BytesIO(extracted.read())) as zf:
                gz_names = sorted(name for name in zf.namelist() if name.endswith(".gz"))
                assert len(gz_names) == 3, f"Expected 3 gzip logs in {zip_member.name}, found {len(gz_names)}"

                for gz_name in gz_names:
                    text = gzip.decompress(zf.read(gz_name)).decode("utf-8")
                    records = []
                    for line in text.splitlines():
                        parts = line.split("|", 3)
                        assert len(parts) == 4, f"Malformed source line in {zip_member.name}/{gz_name}"
                        timestamp, level, module, message = parts
                        if level == "ERROR":
                            records.append({
                                "timestamp": timestamp,
                                "level": level,
                                "module": module,
                                "message": message,
                            })

                    output_name = os.path.basename(gz_name[:-3]) + "_errors.json"
                    expected[output_name].append(record_signature(records))

    return expected


def test_multipart_zip_exists():
    """Check that the multi-part zip files exist."""
    zip_path = "/home/user/archive_out/error_logs.zip"
    z01_path = "/home/user/archive_out/error_logs.z01"

    assert os.path.exists(zip_path), f"Expected multi-part zip file not found at {zip_path}"
    assert os.path.exists(z01_path), f"Expected multi-part split file not found at {z01_path}"


def test_zip_contents_and_json_format():
    """Reassemble the multi-part zip and verify its JSON against the source logs."""
    zip_path = "/home/user/archive_out/error_logs.zip"
    assert os.path.exists(zip_path), "Base zip file missing, cannot proceed with extraction."

    with tempfile.TemporaryDirectory() as tmpdir:
        single_zip = os.path.join(tmpdir, "single.zip")

        result = subprocess.run(
            ["zip", "-s", "0", zip_path, "--out", single_zip],
            cwd="/home/user/archive_out",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert result.returncode == 0, f"Failed to reassemble multi-part zip: {result.stderr.decode()}"

        extract_dir = os.path.join(tmpdir, "extracted")
        os.makedirs(extract_dir)
        result = subprocess.run(
            ["unzip", single_zip, "-d", extract_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert result.returncode == 0, f"Failed to extract reassembled zip: {result.stderr.decode()}"

        json_files = glob.glob(os.path.join(extract_dir, "**", "*_errors.json"), recursive=True)
        assert len(json_files) == 6, f"Expected exactly 6 JSON files, but found {len(json_files)}."

        expected = expected_outputs()
        expected_names = Counter({name: len(values) for name, values in expected.items()})
        actual_names = Counter(os.path.basename(path) for path in json_files)
        assert actual_names == expected_names, (
            f"Incorrect output filenames/counts. Expected {expected_names}, got {actual_names}."
        )

        expected_keys = {"timestamp", "level", "module", "message"}
        actual_signatures = defaultdict(list)

        for jf in json_files:
            with open(jf, "r") as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    pytest.fail(f"File {jf} contains invalid JSON.")

            assert isinstance(data, list), f"JSON root in {jf} must be an array."

            for i, item in enumerate(data):
                assert isinstance(item, dict), f"Item at index {i} in {jf} is not an object."
                assert set(item.keys()) == expected_keys, (
                    f"Incorrect keys in item {i} of {jf}. Expected {expected_keys}, got {set(item.keys())}."
                )
                assert item["level"] == "ERROR", (
                    f"Non-ERROR level found in item {i} of {jf}: {item['level']}"
                )

            actual_signatures[os.path.basename(jf)].append(record_signature(data))

        for output_name, expected_signatures in expected.items():
            assert Counter(actual_signatures[output_name]) == Counter(expected_signatures), (
                f"Records in {output_name} do not exactly match the ERROR records in the source archive."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
