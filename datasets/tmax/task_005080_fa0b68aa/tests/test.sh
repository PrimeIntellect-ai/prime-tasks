#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import urllib.error
import urllib.request

import pytest

PROCESSED_DIR = "/home/user/processed_docs"
MANIFEST_PATH = os.path.join(PROCESSED_DIR, "manifest.txt")
EXPECTED_TOTAL = 12000


def get_indexer_score():
    url = "http://localhost:9001/score"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Indexer Sink metrics endpoint at {url}: {e}")
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON response from {url}: {e}")

    assert "score" in data, f"Response from {url} missing 'score' key. Got: {data}"
    score = float(data["score"])
    assert score >= 0.95, (
        f"Score {score:.4f} is below the required threshold of 0.95. Data: {data}"
    )
    return score


def expected_lines():
    lines = {
        f"DOC_LINE: active_{i} This is a line of documentation."
        for i in range(1, 9001)
    }
    for archive_number in (1, 3, 5):
        lines.update(
            f"DOC_LINE: legacy_{archive_number}_{i} Legacy doc line."
            for i in range(1, 1001)
        )
    return lines


def test_processed_chunks_manifest_and_streaming():
    score = get_indexer_score()

    assert os.path.isdir(PROCESSED_DIR), f"Directory missing: {PROCESSED_DIR}"
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"

    chunk_re = re.compile(r"^chunk_(\d{4})\.md$")
    disk_chunks = sorted(
        name for name in os.listdir(PROCESSED_DIR) if chunk_re.fullmatch(name)
    )
    assert disk_chunks, "No chunk_*.md files were generated"

    expected_names = [f"chunk_{i:04d}.md" for i in range(1, len(disk_chunks) + 1)]
    assert disk_chunks == expected_names, (
        "Chunk filenames must form a contiguous sequence beginning with chunk_0001.md"
    )

    with open(MANIFEST_PATH, "r", encoding="utf-8") as manifest:
        manifest_lines = manifest.readlines()
    assert manifest_lines, "Manifest file is empty. It should contain checksums and filenames."

    manifest_entries = {}
    manifest_re = re.compile(r"^([0-9a-fA-F]{64})  (chunk_\d{4}\.md)\s*$")
    for line in manifest_lines:
        match = manifest_re.fullmatch(line)
        assert match, f"Invalid manifest line format: {line.rstrip()}"
        checksum, filename = match.groups()
        assert filename not in manifest_entries, f"Duplicate manifest entry for {filename}"
        manifest_entries[filename] = checksum.lower()

    assert sorted(manifest_entries) == disk_chunks, (
        "Manifest must contain exactly one entry for every generated chunk"
    )

    allowed = expected_lines()
    stored_lines = []
    for filename in disk_chunks:
        path = os.path.join(PROCESSED_DIR, filename)
        assert os.path.isfile(path), f"Chunk file listed in manifest is missing: {path}"
        payload = open(path, "rb").read()
        assert payload.endswith(b"\n"), f"Chunk contains a partial final line: {filename}"

        actual_checksum = hashlib.sha256(payload).hexdigest()
        assert manifest_entries[filename] == actual_checksum, (
            f"Incorrect SHA256 checksum for {filename}"
        )

        try:
            lines = payload.decode("utf-8").splitlines()
        except UnicodeDecodeError as e:
            pytest.fail(f"Chunk is not valid UTF-8: {filename}: {e}")
        assert len(lines) == 500, f"{filename} has {len(lines)} lines instead of exactly 500"
        stored_lines.extend(lines)

    assert len(stored_lines) == len(set(stored_lines)), (
        "Generated chunks contain duplicate documentation identifiers/lines"
    )
    invalid = set(stored_lines) - allowed
    assert not invalid, f"Chunks contain fabricated or corrupted lines, for example: {next(iter(invalid), '')}"

    stored_score = len(stored_lines) / EXPECTED_TOTAL
    assert stored_score >= 0.95, (
        f"Only {len(stored_lines)} of {EXPECTED_TOTAL} valid source lines were stored"
    )
    assert abs(score - stored_score) < 1e-9, (
        f"Indexer score {score:.6f} does not correspond to the {len(stored_lines)} valid lines "
        "present in the completed chunks"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
