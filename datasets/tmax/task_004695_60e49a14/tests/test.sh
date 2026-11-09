#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import gzip
import struct
import hashlib
import glob
import random
import pytest

BACKUPS_DIR = "/home/user/backups"
MANIFEST_PATH = "/home/user/manifest.json"
FILE_COUNT = 55


def original_records():
    """Reconstruct the immutable logical corpus created during setup."""
    rng = random.Random(42)
    records = {}
    for i in range(FILE_COUNT):
        timestamp = 1620000000 + i * 3600
        keys = [f"key_{rng.randint(1, 100)}" for _ in range(rng.randint(3, 10))]
        filename = f"state_{timestamp}.wal.gz"
        content = struct.pack('<q', timestamp) + ','.join(keys).encode('utf-8')
        records[filename] = {
            "content": content,
            "keys": tuple(sorted(set(keys))),
        }
    return records


def get_expected_tuples():
    import walparser

    records = original_records()
    expected_paths = {
        os.path.join(BACKUPS_DIR, filename) for filename in records
    }
    actual_paths = set(glob.glob(os.path.join(BACKUPS_DIR, "*.wal.gz")))

    assert actual_paths == expected_paths, (
        "The original 55 WAL files must all be physically renamed to their "
        "timestamp-based state_*.wal.gz names, with no backup_*.wal.gz files "
        "missing or left behind"
    )

    expected_tuples = set()
    for filename, record in records.items():
        filepath = os.path.join(BACKUPS_DIR, filename)

        with gzip.open(filepath, 'rb') as f:
            uncompressed = f.read()
        assert uncompressed == record["content"], (
            f"WAL file {filename} does not contain the corresponding original corpus data"
        )

        # Exercise the installed vendored package on every renamed WAL and ensure
        # its results agree with the immutable corpus.
        with gzip.open(filepath, 'rb') as f:
            parsed_data = walparser.parse_stream(f)
        parsed_keys = tuple(sorted({
            item['key'] for item in parsed_data
            if isinstance(item, dict) and 'key' in item
        }))
        assert parsed_keys == record["keys"], f"walparser returned incorrect keys for {filename}"

        hasher = hashlib.sha256()
        with open(filepath, 'rb') as f:
            hasher.update(f.read())
        expected_tuples.add((filename, hasher.hexdigest(), record["keys"]))

    return expected_tuples


def test_manifest_f1_score():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"

    try:
        import walparser
    except ImportError:
        pytest.fail("walparser package is not installed. Agent failed to install it.")

    try:
        with open(MANIFEST_PATH, 'r') as f:
            manifest = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON")

    assert isinstance(manifest, dict), "Manifest must be a JSON dictionary"

    expected_tuples = get_expected_tuples()
    assert len(expected_tuples) > 0, "No valid WAL files found to generate expected tuples"

    agent_tuples = set()
    for filename, data in manifest.items():
        if not isinstance(data, dict):
            continue
        checksum = data.get('checksum', '')
        keys = data.get('keys', [])
        agent_tuples.add((filename, checksum, tuple(sorted(keys))))

    true_positives = len(agent_tuples.intersection(expected_tuples))

    precision = true_positives / len(agent_tuples) if agent_tuples else 0.0
    recall = true_positives / len(expected_tuples) if expected_tuples else 0.0

    if precision + recall == 0:
        f1_score = 0.0
    else:
        f1_score = 2 * precision * recall / (precision + recall)

    assert f1_score >= 0.95, (
        f"F1 score {f1_score:.4f} is below the threshold of 0.95. "
        f"Precision: {precision:.4f}, Recall: {recall:.4f}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
