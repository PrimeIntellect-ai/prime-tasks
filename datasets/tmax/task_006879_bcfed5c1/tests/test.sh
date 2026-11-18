#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import secrets
import subprocess
import unicodedata
from pathlib import Path

import pytest


def test_clean_reviews_jsonl_exists():
    file_path = "/home/user/clean_reviews.jsonl"
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."


def test_clean_reviews_jsonl_content():
    file_path = "/home/user/clean_reviews.jsonl"

    expected = [
        {"id": "A1B2C3D4", "lang": "en", "score": 5, "content": "Great product!"},
        {"id": "A1B2C3D7", "lang": "es", "score": 4, "content": "Me gusta \ufffd el producto"},
        {"id": "A1B2C3D8", "lang": "fr", "score": 3, "content": "Très bien"},
        {"id": "X9Y8Z7W6", "lang": "ko", "score": 2, "content": "각"}
    ]

    actual = []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
                actual.append(parsed)
            except json.JSONDecodeError as e:
                pytest.fail(f"Invalid JSON on line {line_num} of {file_path}: {e}")

    assert len(actual) == len(expected), f"Expected {len(expected)} records in the output, but got {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Record mismatch at index {i}.\nExpected: {exp}\nGot: {act}"


def test_rust_release_cli_processes_fresh_input():
    project = Path("/home/user/dataset_cleaner")
    manifest = project / "Cargo.toml"
    binary = project / "target/release/dataset_cleaner"

    assert project.is_dir(), "The dataset_cleaner Rust project is missing."
    assert manifest.is_file(), "Cargo.toml is missing from the dataset_cleaner project."
    assert binary.is_file(), "The release-mode dataset_cleaner binary is missing."
    assert os.access(binary, os.X_OK), "The release-mode dataset_cleaner binary is not executable."
    assert binary.read_bytes()[:4] == b"\x7fELF", "The release artifact is not a native executable."

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert metadata_run.returncode == 0, f"Invalid Rust project: {metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    packages = [p for p in metadata["packages"] if p["name"] == "dataset_cleaner"]
    assert packages, "Cargo package must be named dataset_cleaner."
    bin_targets = [
        t for p in packages for t in p["targets"]
        if "bin" in t.get("kind", []) and t.get("name") == "dataset_cleaner"
    ]
    assert bin_targets, "The project must define a dataset_cleaner binary target."
    for target in bin_targets:
        source = Path(target["src_path"])
        assert source.is_file() and source.suffix == ".rs" and source.stat().st_size > 0

    nonce = secrets.token_hex(6)
    ids = [secrets.token_hex(4).upper() for _ in range(9)]
    nfd_text = "Cafe\u0301-" + nonce
    hangul_nfd = "\u1100\u1161\u11a8-" + nonce

    raw = b"".join([
        f"{ids[0]},en,5,  fresh-{nonce}  \n".encode(),
        f"{ids[1]},es,4,byte-".encode() + b"\xff" + f"-{nonce}\n".encode(),
        f"{ids[2]},fr,3,{nfd_text}\n".encode("utf-8"),
        f"{ids[3]},ko,2,  {hangul_nfd}  \n".encode("utf-8"),
        f"{ids[4][:-1]},en,5,bad-id\n".encode(),
        f"{ids[5]},EN,5,bad-language\n".encode(),
        f"{ids[6]},de,0,bad-rating\n".encode(),
        f"{ids[7]},it,not-an-int,bad-rating\n".encode(),
        f"{ids[8]},ja,1,     \n".encode(),
    ])
    expected = [
        {"id": ids[0], "lang": "en", "score": 5, "content": f"fresh-{nonce}"},
        {"id": ids[1], "lang": "es", "score": 4, "content": f"byte-\ufffd-{nonce}"},
        {"id": ids[2], "lang": "fr", "score": 3, "content": unicodedata.normalize("NFC", nfd_text)},
        {"id": ids[3], "lang": "ko", "score": 2, "content": unicodedata.normalize("NFC", hangul_nfd)},
    ]

    input_path = Path("/home/user/raw_reviews.csv")
    output_path = Path("/home/user/clean_reviews.jsonl")
    original_input = input_path.read_bytes()
    original_output = output_path.read_bytes()

    try:
        input_path.write_bytes(raw)
        if output_path.exists():
            output_path.unlink()

        run = subprocess.run(
            [str(binary)],
            cwd=project,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run.returncode == 0, (
            f"dataset_cleaner failed on fresh input with exit code {run.returncode}. "
            f"stderr: {run.stderr.decode('utf-8', errors='replace')}"
        )
        assert output_path.is_file(), "Running the release CLI did not create clean_reviews.jsonl."

        actual = []
        with output_path.open("r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError as e:
                    pytest.fail(f"Invalid JSON from release CLI on line {line_num}: {e}")
        assert actual == expected, f"Release CLI produced incorrect output.\nExpected: {expected}\nGot: {actual}"
    finally:
        input_path.write_bytes(original_input)
        output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
