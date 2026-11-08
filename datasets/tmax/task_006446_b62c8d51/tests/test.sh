#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import subprocess
import unicodedata
import uuid
import pytest

OUTPUT = "/home/user/clean_transcript.json"
RAW = "/home/user/raw_transcript.log"
PROJECT = "/home/user/transcript_parser"


def test_clean_transcript_exists():
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} does not exist. Ensure your Rust program writes to this exact path."


def test_clean_transcript_content():
    assert os.path.isfile(OUTPUT), f"Cannot verify content: {OUTPUT} is missing."

    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"The file {OUTPUT} does not contain valid JSON. Error: {e}")

    assert isinstance(data, list), f"Expected a JSON array at the root, but found {type(data).__name__}."

    expected = [
        {"timestamp": "2023-11-01T14:05:00Z", "text": "Hello world! 🚀", "char_count": 14},
        {"timestamp": "2023-11-01T14:05:05Z", "text": "Bonjour le monde.", "char_count": 17},
        {"timestamp": "2023-11-01T14:05:10Z", "text": "مرحبا", "char_count": 5},
        {"timestamp": "2023-11-01T14:05:15Z", "text": "こんにちは", "char_count": 5},
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} objects in the JSON array, but found {len(data)}. Check your deduplication and filtering logic."

    for i, (actual_obj, expected_obj) in enumerate(zip(data, expected)):
        assert isinstance(actual_obj, dict), f"Item at index {i} is not a JSON object."
        actual_keys = set(actual_obj.keys())
        expected_keys = {"timestamp", "text", "char_count"}
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, found {actual_keys}."
        assert actual_obj["timestamp"] == expected_obj["timestamp"], f"Item at index {i} has incorrect timestamp. Expected '{expected_obj['timestamp']}', found '{actual_obj['timestamp']}'."
        assert actual_obj["text"] == expected_obj["text"], f"Item at index {i} has incorrect text. Expected '{expected_obj['text']}', found '{actual_obj['text']}'. Ensure correct tag removal, trimming, and NFC normalization."
        assert actual_obj["char_count"] == expected_obj["char_count"], f"Item at index {i} has incorrect char_count. Expected {expected_obj['char_count']}, found {actual_obj['char_count']}."


def derive_expected(raw_text):
    result = []
    previous = None
    timestamp_re = re.compile(r"^\[(?:(\d{4}-\d{2}-\d{2}) )?(\d{2}:\d{2}:\d{2})\]")
    for line in raw_text.splitlines():
        match = timestamp_re.match(line)
        assert match is not None, "Verifier generated an invalid fixture"
        date = match.group(1) or "2023-11-01"
        text = line[match.end():]
        text = re.sub(r"<[^>]*>", "", text)
        text = re.sub(r"\[[^\]]*\]", "", text)
        text = unicodedata.normalize("NFC", " ".join(text.split()))
        if not text or text == previous:
            continue
        result.append({
            "timestamp": f"{date}T{match.group(2)}Z",
            "text": text,
            "char_count": len(text),
        })
        previous = text
    return result


def test_rust_project_executes_on_fresh_input():
    assert os.path.isdir(PROJECT), f"Required Rust project {PROJECT} does not exist."
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest) and not os.path.islink(manifest), "The Rust project is missing a regular Cargo.toml file."
    rust_sources = [p for p in glob.glob(os.path.join(PROJECT, "**", "*.rs"), recursive=True)
                    if os.path.isfile(p) and not os.path.islink(p)]
    assert rust_sources, "The project contains no Rust source files."

    token = "case_" + uuid.uuid4().hex
    first = token + " Café"
    fixture = (
        f"[2024-02-03 01:02:03] <speaker-a>   {token}   Cafe\u0301 [noise]\n"
        f"[01:02:04] <speaker-b> {first}\n"
        "[01:02:05] <system> [applause]    \n"
        f"[2025-06-07 08:09:10] <speaker-c> مرحبا    {token} [music]\n"
        f"[08:09:11] [aside] {first}\n"
        f"[2026-12-13 14:15:16] <speaker-d> こんにちは 🚀 {token}\n"
    )
    expected = derive_expected(fixture)

    with open(RAW, "rb") as f:
        old_raw = f.read()
    old_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            old_output = f.read()

    try:
        with open(RAW, "w", encoding="utf-8") as f:
            f.write(fixture)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        try:
            proc = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", manifest],
                cwd=PROJECT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The Rust program did not finish within 180 seconds.")

        assert proc.returncode == 0, f"cargo run failed.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        assert os.path.isfile(OUTPUT), "Executing the Rust project did not create /home/user/clean_transcript.json."
        try:
            with open(OUTPUT, "r", encoding="utf-8") as f:
                actual = json.load(f)
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            pytest.fail(f"The Rust program produced invalid UTF-8 JSON on a fresh input: {e}")

        assert actual == expected, f"The Rust program produced incorrect output for a fresh input.\nExpected: {expected!r}\nActual: {actual!r}"
        for i, item in enumerate(actual):
            assert isinstance(item, dict), f"Fresh-output item {i} is not an object."
            assert set(item) == {"timestamp", "text", "char_count"}, f"Fresh-output item {i} has incorrect keys."
    finally:
        with open(RAW, "wb") as f:
            f.write(old_raw)
        if old_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
