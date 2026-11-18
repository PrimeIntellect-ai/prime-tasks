#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os

CANONICAL_ARCHIVE_TEXT = """===DOC-START===
Author: Alice Smith
Date: 2023-01-01
Tags: public, api

This is the public API documentation.
It has multiple lines.
===DOC-END===
===DOC-START===
Author: Bob Jones
Date: 2023-01-02
Tags: internal, draft

This is secret internal documentation.
Do not publish!
===DOC-END===
===DOC-START===
Author: Charlie Brown
Date: 2023-01-03
Tags: PUBLIC, guide, setup

How to setup the project.

Step 1: Install.
Step 2: Run.
===DOC-END===
"""


def derive_expected_records():
    archive_path = "/home/user/doc_dumps/archive.rle"
    assert os.path.exists(archive_path), f"{archive_path} does not exist."

    with open(archive_path, "rb") as f:
        rle_bytes = f.read()

    assert len(rle_bytes) > 0, f"{archive_path} is empty."
    assert len(rle_bytes) % 2 == 0, f"{archive_path} has an odd number of bytes, invalid RLE format."

    decoded = "".join(
        chr(rle_bytes[i + 1]) * rle_bytes[i]
        for i in range(0, len(rle_bytes), 2)
    )
    assert decoded == CANONICAL_ARCHIVE_TEXT, "The source archive contents were modified."

    pieces = decoded.split("===DOC-START===\n")
    assert pieces[0] == "", "Unexpected text before the first record."

    records = []
    for piece in pieces[1:]:
        assert "===DOC-END===" in piece, "Record is missing its end marker."
        body, trailing = piece.split("===DOC-END===", 1)
        assert trailing == "\n", "Unexpected text after a record end marker."

        header_text, content = body.split("\n\n", 1)
        headers = header_text.split("\n")
        assert len(headers) == 3, "Record has malformed headers."
        assert headers[0].startswith("Author: ")
        assert headers[1].startswith("Date: ")
        assert headers[2].startswith("Tags: ")
        assert content.endswith("\n"), "Record content is not terminated before DOC-END."

        tags = [tag.strip().lower() for tag in headers[2][len("Tags: "):].split(",")]
        record = {
            "author": headers[0][len("Author: "):],
            "date": headers[1][len("Date: "):],
            "tags": tags,
            "content": content[:-1],
        }
        if "public" in tags:
            records.append(record)

    return records


def test_json_file_exists_and_valid():
    json_path = "/home/user/public_docs.json"
    assert os.path.exists(json_path), f"{json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not valid JSON."

    assert isinstance(data, list), "JSON root should be a list."
    assert len(data) == 2, f"Expected exactly 2 public records, got {len(data)}."

    # Check first record
    assert data[0].get("author") == "Alice Smith", "First record author is incorrect."
    assert data[0].get("date") == "2023-01-01", "First record date is incorrect."
    assert "public" in data[0].get("tags", []), "First record missing 'public' tag."
    assert data[0].get("content") == "This is the public API documentation.\nIt has multiple lines.", "First record content mismatch."

    # Check second record
    assert data[1].get("author") == "Charlie Brown", "Second record author is incorrect."
    assert data[1].get("date") == "2023-01-03", "Second record date is incorrect."
    assert "public" in data[1].get("tags", []), "Second record missing 'public' tag."
    assert data[1].get("content") == "How to setup the project.\n\nStep 1: Install.\nStep 2: Run.", "Second record content mismatch."


def test_json_exactly_matches_records_derived_from_archive():
    with open("/home/user/public_docs.json", "r") as f:
        data = json.load(f)

    expected = derive_expected_records()
    assert data == expected, "JSON records do not exactly match the public records in archive.rle."


def test_rle_file_exists_and_matches_json():
    rle_path = "/home/user/public_docs.rle"
    json_path = "/home/user/public_docs.json"

    assert os.path.exists(rle_path), f"{rle_path} does not exist."
    assert os.path.exists(json_path), f"{json_path} does not exist."

    with open(rle_path, "rb") as f:
        rle_bytes = f.read()

    assert len(rle_bytes) > 0, f"{rle_path} is empty."
    assert len(rle_bytes) % 2 == 0, f"{rle_path} has an odd number of bytes, invalid RLE format."

    decoded = ""
    for i in range(0, len(rle_bytes), 2):
        count = rle_bytes[i]
        char = chr(rle_bytes[i+1])
        decoded += char * count

    with open(json_path, "r") as f:
        expected_json_str = f.read()

    assert decoded == expected_json_str, "Decoded RLE content does not exactly match the contents of public_docs.json."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
