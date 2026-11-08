#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import xml.etree.ElementTree as ET
import hashlib
import zipfile
import tarfile
import tempfile
from collections import Counter
import pytest

PROCESSED_DIR = "/home/user/processed"
SUMMARY_FILE = "/home/user/summary.json"
SOURCE_ARCHIVE = "/home/user/research_data.zip"
REQUIRED_FILES = {"metadata.xml", "sensors.csv", "data.bin"}

# Immutable description of the raw files contained in the supplied dataset.
EXPECTED_FILES = {
    ("Alpha_Dir", "metadata.xml"): b"<trial>\n  <id>Alpha_01</id>\n  <valid>true</valid>\n  <binary_offset>10</binary_offset>\n  <binary_length>16</binary_length>\n</trial>",
    ("Alpha_Dir", "sensors.csv"): b"timestamp,value\n1,10.5\n2,20.5\n3,30.0\n",
    ("Alpha_Dir", "data.bin"): b"A" * 10 + b"B" * 16 + b"C" * 10,
    ("Beta_Dir", "metadata.xml"): b"<trial>\n  <id>Beta_02</id>\n  <valid>false</valid>\n  <binary_offset>0</binary_offset>\n  <binary_length>5</binary_length>\n</trial>",
    ("Beta_Dir", "sensors.csv"): b"timestamp,value\n1,99.9\n",
    ("Beta_Dir", "data.bin"): b"X" * 20,
    ("Gamma_Dir", "metadata.xml"): b"<trial>\n  <id>Gamma_03</id>\n  <valid>true</valid>\n  <binary_offset>5</binary_offset>\n  <binary_length>8</binary_length>\n</trial>",
    ("Gamma_Dir", "sensors.csv"): b"timestamp,value\n1,100.1\n2,100.2\n",
    ("Gamma_Dir", "data.bin"): b"Y" * 5 + b"Z" * 8 + b"W" * 5,
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory_from_expected():
    return Counter((name, digest(data)) for (_, name), data in EXPECTED_FILES.items())


def bundle_signatures_from_expected():
    bundles = Counter()
    for dirname in {key[0] for key in EXPECTED_FILES}:
        bundles[tuple(digest(EXPECTED_FILES[(dirname, name)]) for name in sorted(REQUIRED_FILES))] += 1
    return bundles


def filesystem_inventory(root):
    result = Counter()
    for current, dirs, files in os.walk(root):
        for dirname in dirs:
            assert not os.path.islink(os.path.join(current, dirname)), "Extracted directories must not be symbolic links"
        for name in files:
            path = os.path.join(current, name)
            assert not os.path.islink(path), f"Extracted file must not be a symbolic link: {path}"
            with open(path, "rb") as f:
                result[(name, digest(f.read()))] += 1
    return result


def filesystem_bundle_signatures(root):
    bundles = Counter()
    for current, dirs, files in os.walk(root):
        if REQUIRED_FILES.issubset(set(files)):
            signature = []
            for name in sorted(REQUIRED_FILES):
                with open(os.path.join(current, name), "rb") as f:
                    signature.append(digest(f.read()))
            bundles[tuple(signature)] += 1
    return bundles


def recursively_extract(archive, destination):
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(destination)

    while True:
        archives = []
        for current, dirs, files in os.walk(destination):
            for name in files:
                if name.endswith(".zip") or name.endswith(".tar.gz"):
                    archives.append(os.path.join(current, name))
        if not archives:
            return
        for path in sorted(archives):
            parent = os.path.dirname(path)
            if path.endswith(".zip"):
                with zipfile.ZipFile(path) as zf:
                    zf.extractall(parent)
            else:
                with tarfile.open(path, "r:gz") as tf:
                    tf.extractall(parent)
            os.remove(path)


def expected_summary_from_immutable_data():
    result = []
    for dirname in sorted({key[0] for key in EXPECTED_FILES}):
        root = ET.fromstring(EXPECTED_FILES[(dirname, "metadata.xml")])
        if root.find("valid").text.strip().lower() != "true":
            continue
        trial_id = root.find("id").text.strip()
        offset = int(root.find("binary_offset").text.strip())
        length = int(root.find("binary_length").text.strip())
        rows = EXPECTED_FILES[(dirname, "sensors.csv")].decode().strip().splitlines()[1:]
        values = [float(row.split(",")[1]) for row in rows if row.strip()]
        binary = EXPECTED_FILES[(dirname, "data.bin")]
        result.append({
            "trial_id": trial_id,
            "average_reading": round(sum(values) / len(values), 2) if values else 0.0,
            "data_hash": digest(binary[offset:offset + length]),
        })
    return sorted(result, key=lambda item: item["trial_id"])


def test_processed_directory_exists_and_clean():
    """Test that the processed directory exists and contains no intermediate archives."""
    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist. Did you extract the archive?"

    # Check for intermediate archives
    for root, dirs, files in os.walk(PROCESSED_DIR):
        for file in files:
            assert not file.endswith(".zip"), f"Found intermediate zip file which should have been deleted: {os.path.join(root, file)}"
            assert not file.endswith(".tar.gz"), f"Found intermediate tar.gz file which should have been deleted: {os.path.join(root, file)}"


def test_processed_files_match_supplied_dataset():
    """Require the processed tree to contain exactly the raw files from the supplied archive."""
    assert os.path.isfile(SOURCE_ARCHIVE), f"Supplied archive is missing: {SOURCE_ARCHIVE}"
    with tempfile.TemporaryDirectory() as extracted:
        recursively_extract(SOURCE_ARCHIVE, extracted)
        source_inventory = filesystem_inventory(extracted)
        source_bundles = filesystem_bundle_signatures(extracted)

    # Validate the source semantically against immutable setup data, so replacing the
    # agent-writable source archive cannot redefine the expected result.
    assert source_inventory == inventory_from_expected(), "The supplied archive's data was altered"
    assert source_bundles == bundle_signatures_from_expected(), "The supplied archive's trial layout was altered"

    assert filesystem_inventory(PROCESSED_DIR) == source_inventory, "Processed files do not exactly match the supplied dataset"
    assert filesystem_bundle_signatures(PROCESSED_DIR) == source_bundles, "Trial files were not extracted into the correct trial directories"


def test_summary_json_exists_and_valid():
    """Test that the summary.json file is created and is a valid JSON array."""
    assert os.path.isfile(SUMMARY_FILE), f"Summary file {SUMMARY_FILE} does not exist."
    try:
        with open(SUMMARY_FILE, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {SUMMARY_FILE} is not a valid JSON.")

    assert isinstance(data, list), f"JSON root must be an array, got {type(data).__name__}"


def test_summary_json_content():
    """Test that the summary.json contains the correctly computed data for valid trials."""
    expected = []

    # Dynamically compute expected results from the extracted files if available
    if os.path.isdir(PROCESSED_DIR):
        for root, dirs, files in os.walk(PROCESSED_DIR):
            if {"metadata.xml", "sensors.csv", "data.bin"}.issubset(set(files)):
                tree = ET.parse(os.path.join(root, "metadata.xml"))
                xml_root = tree.getroot()
                trial_id = xml_root.find("id").text.strip()
                valid = xml_root.find("valid").text.strip().lower() == "true"

                if not valid:
                    continue

                offset = int(xml_root.find("binary_offset").text.strip())
                length = int(xml_root.find("binary_length").text.strip())

                with open(os.path.join(root, "sensors.csv"), "r") as f:
                    lines = f.read().strip().split('\n')

                values = [float(line.split(',')[1]) for line in lines[1:] if line.strip()]
                avg = round(sum(values) / len(values), 2) if values else 0.0

                with open(os.path.join(root, "data.bin"), "rb") as f:
                    f.seek(offset)
                    chunk = f.read(length)

                expected.append({
                    "trial_id": trial_id,
                    "average_reading": avg,
                    "data_hash": hashlib.sha256(chunk).hexdigest()
                })

    expected.sort(key=lambda x: x["trial_id"])

    # Fallback to absolute truth if extraction failed or was incomplete (prevents false positives)
    if len(expected) != 2:
        expected = [
            {
                "trial_id": "Alpha_01",
                "average_reading": 20.33,
                "data_hash": "10ed805175e110b48b7f8dc721e2850982df4cc10b64af5d40a8309df58bbaea"
            },
            {
                "trial_id": "Gamma_03",
                "average_reading": 100.15,
                "data_hash": "a86241c09ebc713b946ebde4aa81395b066f1b3e4fce9d34e9e4f04e12e3e579"
            }
        ]

    assert os.path.isfile(SUMMARY_FILE), f"Cannot test content, {SUMMARY_FILE} is missing."
    with open(SUMMARY_FILE, "r") as f:
        actual = json.load(f)

    assert len(actual) == len(expected), f"Expected {len(expected)} valid trials in summary, got {len(actual)}"

    for i, (exp, act) in enumerate(zip(expected, actual)):
        assert act.get("trial_id") == exp["trial_id"], f"Mismatch in trial_id at index {i}. Expected {exp['trial_id']}, got {act.get('trial_id')}"
        assert act.get("average_reading") == exp["average_reading"], f"Mismatch in average_reading for {exp['trial_id']}. Expected {exp['average_reading']}, got {act.get('average_reading')}"
        assert act.get("data_hash") == exp["data_hash"], f"Mismatch in data_hash for {exp['trial_id']}. Expected {exp['data_hash']}, got {act.get('data_hash')}"


def test_summary_matches_supplied_dataset_independently():
    """Check the report against immutable source data, not agent-controlled processed files."""
    with open(SUMMARY_FILE, "r") as f:
        actual = json.load(f)
    assert actual == expected_summary_from_immutable_data(), "Summary does not match the supplied dataset"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
