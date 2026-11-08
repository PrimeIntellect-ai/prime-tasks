#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import py_compile
import re
import struct
import subprocess
import tempfile
import zlib
from html.parser import HTMLParser

import pytest

FINAL_DOCZ_PATH = "/home/user/final.docz"
CONFIG_PATH = "/home/user/build_config.json"
PACK_SCRIPT_PATH = "/home/user/pack_docs.py"
SQFS_PATH = "/home/user/docs_data.sqfs"
SIZE_THRESHOLD = 4500
EXPECTED_CONFIG = {f"doc_{i}.ldoc": f"folder/doc_{i}.md" for i in range(5)}


@pytest.fixture(scope="session", autouse=True)
def run_pack_script():
    assert os.path.exists(PACK_SCRIPT_PATH), f"Missing script: {PACK_SCRIPT_PATH}"
    assert os.path.isfile(PACK_SCRIPT_PATH), f"Not a file: {PACK_SCRIPT_PATH}"
    py_compile.compile(PACK_SCRIPT_PATH, doraise=True)
    result = subprocess.run(
        ["python3", PACK_SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pack_docs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout[-2000:]}\n"
        f"stderr:\n{result.stderr[-2000:]}"
    )


def test_final_docz_exists_and_size():
    assert os.path.exists(FINAL_DOCZ_PATH), f"Missing file: {FINAL_DOCZ_PATH}"
    assert os.path.isfile(FINAL_DOCZ_PATH), f"Not a file: {FINAL_DOCZ_PATH}"

    size = os.path.getsize(FINAL_DOCZ_PATH)
    assert size <= SIZE_THRESHOLD, f"File size {size} exceeds threshold of {SIZE_THRESHOLD} bytes. Ensure you are compressing the concatenated payload at once with zlib level 9."


class SourceHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text = []
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "a":
            href = dict(attrs).get("href")
            if href is not None:
                self.links.append(href)

    def handle_data(self, data):
        if data.strip():
            self.text.append(data.strip())


def normalize_space(value):
    return " ".join(value.split())


def markdown_visible_text(markdown_text, expected_href):
    found_links = []
    link_pattern = re.compile(
        r"\[([^\]]+)\]\(\s*<?(https?://[^\s)>]+)>?(?:\s+[\"'][^\"']*[\"'])?\s*\)"
    )

    def replace_link(match):
        found_links.append(match.group(2))
        return match.group(1)

    text = link_pattern.sub(replace_link, markdown_text)
    assert expected_href in found_links, f"Missing Markdown link to {expected_href}"
    assert not re.search(r"<\s*/?\s*[A-Za-z][^>]*>", text), "Decoded HTML tags were not converted to Markdown"

    lines = []
    for line in text.splitlines():
        if re.fullmatch(r"\s*(?:=+|-+)\s*", line):
            continue
        line = re.sub(r"^\s{0,3}#{1,6}\s+", "", line)
        line = re.sub(r"\s+#+\s*$", "", line)
        line = re.sub(r"^\s*>\s?", "", line)
        line = re.sub(r"^\s*(?:[-+*]|\d+[.)])\s+", "", line)
        lines.append(line)
    text = "\n".join(lines)
    text = re.sub(r"[`*_~]", "", text)
    text = re.sub(r"\\([\\`*_{}\[\]()#+.!-])", r"\1", text)
    return normalize_space(text)


def load_decoded_sources():
    decoded = {}
    with tempfile.TemporaryDirectory() as temp_dir:
        result = subprocess.run(
            ["unsquashfs", "-no-progress", "-d", temp_dir, SQFS_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Failed to extract docs_data.sqfs: {result.stderr}"

        for i, filename in enumerate(EXPECTED_CONFIG):
            path = os.path.join(temp_dir, filename)
            assert os.path.isfile(path), f"Missing source document in SquashFS: {filename}"
            with open(path, "rb") as f:
                encoded = f.read()
            compressed = bytes(byte ^ 0x5A for byte in base64.b64decode(encoded, validate=True))
            html = zlib.decompress(compressed).decode("utf-8")
            expected_html = (
                f"<h1>Doc {i}</h1>\n"
                f"<p>This is legacy doc {i} with some repetitive text. repetitive text. repetitive text.</p>\n"
                "<a href='http://example.com'>Link</a>"
            )
            assert html == expected_html, f"Decoded source content is unexpected for {filename}"
            decoded[filename] = html
    return decoded


def test_final_docz_format_and_content():
    assert os.path.exists(FINAL_DOCZ_PATH), f"Missing file: {FINAL_DOCZ_PATH}"
    assert os.path.exists(CONFIG_PATH), f"Missing config file: {CONFIG_PATH}"

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        config = json.load(f)
    assert config == EXPECTED_CONFIG, "build_config.json was altered or does not contain the expected document mapping"
    expected_logical_paths = set(config.values())

    with open(FINAL_DOCZ_PATH, "rb") as f:
        data = f.read()

    assert len(data) >= 8, "File is too small to contain header."

    magic = data[0:4]
    assert magic == b"DOCZ", f"Invalid magic string: expected b'DOCZ', got {magic}"

    index_size = struct.unpack("<I", data[4:8])[0]
    assert len(data) >= 8 + index_size, "File is too small to contain the JSON index specified by the header."

    json_bytes = data[8:8 + index_size]
    try:
        index_str = json_bytes.decode("utf-8")
        index = json.loads(index_str)
    except Exception as e:
        pytest.fail(f"Failed to parse JSON index: {e}")

    assert isinstance(index, dict), "JSON index must be a dictionary"
    assert set(index.keys()) == expected_logical_paths, f"Index keys do not match expected logical paths. Expected {expected_logical_paths}, got {set(index.keys())}"

    compressed_payload = data[8 + index_size:]
    try:
        decompressor = zlib.decompressobj()
        payload = decompressor.decompress(compressed_payload) + decompressor.flush()
        assert decompressor.eof, "Compressed payload is truncated"
        assert not decompressor.unused_data, "Unexpected bytes follow the zlib payload"
        assert not decompressor.unconsumed_tail, "Compressed payload was not fully consumed"
    except Exception as e:
        pytest.fail(f"Failed to decompress payload: {e}")

    decoded_sources = load_decoded_sources()
    source_for_logical_path = {logical: decoded_sources[source] for source, logical in config.items()}

    next_offset = 0
    extracted_documents = []
    for logical_path, location in index.items():
        assert isinstance(location, list) and len(location) == 2, f"Invalid index entry for {logical_path}"
        offset, length = location
        assert type(offset) is int and type(length) is int, f"Offset and length for {logical_path} must be integers"
        assert offset >= 0, f"Invalid offset for {logical_path}"
        assert length > 0, f"Invalid length for {logical_path}"
        assert offset + length <= len(payload), f"Offset and length for {logical_path} exceed payload size"
        assert offset == next_offset, f"Payload slice for {logical_path} is not contiguous or in JSON index order"

        extracted_content = payload[offset:offset + length]
        try:
            markdown_text = extracted_content.decode("utf-8")
        except UnicodeDecodeError:
            pytest.fail(f"Content for {logical_path} is not valid UTF-8.")

        parser = SourceHTMLParser()
        parser.feed(source_for_logical_path[logical_path])
        assert parser.links == ["http://example.com"]
        expected_text = normalize_space(" ".join(parser.text))
        actual_text = markdown_visible_text(markdown_text, parser.links[0])
        assert actual_text == expected_text, (
            f"Markdown content for {logical_path} does not match its decoded .ldoc source. "
            f"Expected visible text {expected_text!r}, got {actual_text!r}"
        )

        title = parser.text[0]
        has_atx_heading = re.search(rf"(?m)^\s{{0,3}}#{{1,6}}\s+{re.escape(title)}(?:\s+#+)?\s*$", markdown_text)
        has_setext_heading = re.search(rf"(?m)^\s*{re.escape(title)}\s*\n\s*(?:=+|-+)\s*$", markdown_text)
        assert has_atx_heading or has_setext_heading, f"The h1 element for {logical_path} was not converted to a Markdown heading"

        extracted_documents.append(extracted_content)
        next_offset = offset + length

    assert next_offset == len(payload), "Payload contains unindexed or trailing uncompressed data"
    assert len(set(extracted_documents)) == len(extracted_documents), "Different documents must not reuse the same payload content"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
