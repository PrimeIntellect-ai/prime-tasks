#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import gzip
import secrets
import subprocess
import pytest

OUTPUT_FILE = "/home/user/consolidated.b64gz"
SCRIPT_FILE = "/home/user/consolidate_docs.sh"
DOC_ROOT = "/home/user/legacy_docs"

EXPECTED_HEADERS = [
    "===/home/user/legacy_docs/folderA/file1.txt===",
    "===/home/user/legacy_docs/folderB/file2.txt===",
    "===/home/user/legacy_docs/folderB/subfolder/file3.txt===",
    "===/home/user/legacy_docs/link_file.txt==="
]


def decode_source(data):
    if data.startswith(b"\xff\xfe"):
        return data[2:].decode("utf-16le")
    if data.startswith(b"\xfe\xff"):
        return data[2:].decode("utf-16be")

    odd = data[1::2]
    if odd and odd.count(0) / len(odd) > 0.30:
        return data.decode("utf-16le")

    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("iso-8859-1")


def discover_expected():
    expected = {}
    for directory, dirnames, filenames in os.walk(DOC_ROOT, followlinks=False):
        for name in filenames:
            path = os.path.join(directory, name)
            if name.endswith(".txt") and os.path.isfile(path):
                with open(path, "rb") as source:
                    text = decode_source(source.read())
                expected[path] = text.replace("AcmeCorp", "ZenithInc")
    return expected


BASELINE_EXPECTED = discover_expected()


def execute_script():
    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "timeout", "20", "bash", SCRIPT_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=25,
    )
    assert result.returncode == 0, (
        f"Script failed or timed out with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def get_decoded_content():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, "r") as f:
        b64_content = f.read().strip()

    try:
        gzipped_data = base64.b64decode(b64_content)
    except Exception as e:
        pytest.fail(f"Failed to base64 decode the output file: {e}")

    try:
        uncompressed_data = gzip.decompress(gzipped_data)
    except Exception as e:
        pytest.fail(f"Failed to gzip decompress the decoded data: {e}")

    try:
        return uncompressed_data.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"Uncompressed data is not valid UTF-8: {e}")


def extract_records(text):
    lines = text.splitlines(keepends=True)
    records = {}
    current_path = None
    body = []
    header_pattern = re.compile(r"^===(/home/user/legacy_docs/.*\.txt)===$")

    for line in lines:
        candidate = line[:-1] if line.endswith("\n") else line
        if candidate.endswith("\r"):
            candidate = candidate[:-1]
        match = header_pattern.fullmatch(candidate)
        if match:
            assert line.endswith("\n"), f"Header is not a complete header line: {candidate!r}"
            if current_path is not None:
                assert current_path not in records, f"Duplicate header for {current_path}"
                records[current_path] = "".join(body)
            current_path = match.group(1)
            body = []
        else:
            assert current_path is not None, "Decoded output contains text before the first header."
            body.append(line)

    if current_path is not None:
        assert current_path not in records, f"Duplicate header for {current_path}"
        records[current_path] = "".join(body)
    return records


def assert_exact_output(expected):
    text = get_decoded_content()
    records = extract_records(text)
    assert set(records) == set(expected), (
        f"Output paths differ from discovered .txt files. "
        f"Expected {sorted(expected)}, got {sorted(records)}"
    )
    for path, expected_body in expected.items():
        assert records[path] == expected_body, f"Processed content for {path} is incorrect."


def test_00_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."


def test_01_execute_script():
    execute_script()


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."


def test_headers_present():
    text_content = get_decoded_content()
    for header in EXPECTED_HEADERS:
        assert header in text_content, f"Expected header {header} not found in the decoded output."

    header_count = sum(
        1 for line in text_content.splitlines()
        if line.startswith("===") and line.endswith("===")
    )
    assert header_count == 4, f"Expected exactly 4 headers, but found {header_count}."


def test_acmecorp_replaced():
    text_content = get_decoded_content()
    assert "AcmeCorp" not in text_content, "'AcmeCorp' was found in the output. It should have been replaced."


def test_zenithinc_count():
    text_content = get_decoded_content()
    expected_count = sum(body.count("ZenithInc") for body in BASELINE_EXPECTED.values())
    count = text_content.count("ZenithInc")
    assert count == expected_count, (
        f"Expected 'ZenithInc' to appear exactly {expected_count} times, but found it {count} times."
    )


def test_exact_baseline_contents():
    assert_exact_output(BASELINE_EXPECTED)


def test_zz_dynamic_traversal_encoding_and_symlink():
    token = secrets.token_hex(12)
    challenge_dir = os.path.join(DOC_ROOT, "verify_" + token)
    nested_dir = os.path.join(challenge_dir, "nested")
    os.makedirs(nested_dir)

    utf8_path = os.path.join(challenge_dir, "utf8_" + token + ".txt")
    utf16_path = os.path.join(nested_dir, "utf16_" + token + ".txt")
    latin1_path = os.path.join(nested_dir, "latin1_" + token + ".txt")
    link_path = os.path.join(challenge_dir, "link_" + token + ".txt")

    with open(utf8_path, "wb") as f:
        f.write(("dynamic " + token + " AcmeCorp snowman \u2603\n").encode("utf-8"))
    with open(utf16_path, "wb") as f:
        f.write(("UTF16 " + token + " AcmeCorp rockets\n").encode("utf-16le"))
    with open(latin1_path, "wb") as f:
        f.write(("caf\u00e9 " + token + " AcmeCorp archive\n").encode("iso-8859-1"))
    os.symlink(utf8_path, link_path)

    expected = discover_expected()
    execute_script()
    assert_exact_output(expected)
    assert "AcmeCorp" not in get_decoded_content()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
