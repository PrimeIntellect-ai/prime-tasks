#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import subprocess
import tarfile
import zipfile

import pytest

EXPECTED = {
    1: b"Welcome to the system documentation.\n",
    2: b"Chapter 1: Installation involves extracting files.\n",
    3: b"Chapter 2: Configuration requires setting environment variables.\n",
}


def encode_rle(data):
    out = bytearray()
    if not data:
        return bytes(out)
    current = data[0]
    count = 1
    for value in data[1:]:
        if value == current and count < 255:
            count += 1
        else:
            out.extend((count, (current + 5) % 256))
            current = value
            count = 1
    out.extend((count, (current + 5) % 256))
    return bytes(out)


def files_named(name):
    matches = []
    for root, dirs, files in os.walk("/home/user"):
        if name in files:
            matches.append(os.path.join(root, name))
    return matches


def run_decoder(executable, encoded, tmp_path, tag):
    input_path = tmp_path / f"{tag}.rle"
    output_path = tmp_path / f"{tag}.out"
    input_path.write_bytes(encoded)
    result = subprocess.run(
        [str(executable), str(input_path), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Decoder failed for {tag}: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert output_path.is_file(), f"Decoder did not create its output for {tag}"
    return output_path.read_bytes()


def test_final_docs_exists_and_content():
    """Test that final_docs.txt exists and has the correct content."""
    final_docs_path = "/home/user/final_docs.txt"
    assert os.path.isfile(final_docs_path), f"File not found: {final_docs_path}"

    expected_content = (
        "Welcome to the system documentation.\n"
        "Chapter 1: Installation involves extracting files.\n"
        "Chapter 2: Configuration requires setting environment variables.\n"
    )

    with open(final_docs_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == expected_content, "The content of final_docs.txt does not match the expected output."
    assert os.fsencode(content) == b"".join(EXPECTED[i] for i in sorted(EXPECTED))


def test_decoder_exists_and_executable():
    """Test that the C source and executable exist."""
    c_source = "/home/user/decoder.c"
    executable = "/home/user/decoder"

    assert os.path.isfile(c_source), f"C source file not found: {c_source}"
    assert os.path.isfile(executable), f"Executable not found: {executable}"
    assert os.access(executable, os.X_OK), f"File is not executable: {executable}"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "decoder is not a compiled native executable"


def test_decoder_source_compiles_and_both_binaries_decode(tmp_path):
    rebuilt = tmp_path / "decoder_from_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "/home/user/decoder.c", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        f"decoder.c does not compile: stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )

    vectors = [
        b"",
        b"a",
        b"aaabccccccZ\n",
        bytes(range(128)),
        b"x" * 300 + b"y" * 255 + b"z" * 2,
    ]
    for binary in ("/home/user/decoder", rebuilt):
        for index, plain in enumerate(vectors):
            actual = run_decoder(binary, encode_rle(plain), tmp_path, f"{binary.name if hasattr(binary, 'name') else 'submitted'}_{index}")
            assert actual == plain, f"{binary} decoded test vector {index} incorrectly"


def test_archive_and_renamed_rle_files():
    archive_path = "/home/user/docs_archive.tar.gz"
    assert os.path.isfile(archive_path), f"File not found: {archive_path}"

    archived = {}
    with tarfile.open(archive_path, "r:gz") as outer:
        zip_members = [m for m in outer.getmembers() if m.isfile() and m.name.endswith(".zip")]
        assert len(zip_members) == 2, "The outer archive must contain the two nested zip files"
        for member in zip_members:
            extracted = outer.extractfile(member)
            assert extracted is not None
            with zipfile.ZipFile(io.BytesIO(extracted.read())) as nested:
                for name in nested.namelist():
                    if not name.endswith("/"):
                        archived[os.path.basename(name)] = nested.read(name)

    for doc_id, plain in EXPECTED.items():
        old_name = f"DOC_{doc_id:03d}_OLD.txt.rle"
        new_name = f"doc_{doc_id:03d}_new.txt.rle"
        expected_encoded = encode_rle(plain)
        assert old_name in archived, f"Nested archive is missing {old_name}"
        assert archived[old_name] == expected_encoded, f"Archived data for {old_name} is incorrect"
        matches = files_named(new_name)
        assert matches, f"Renamed encoded file {new_name} was not found"
        assert any(open(path, "rb").read() == expected_encoded for path in matches), (
            f"No extracted {new_name} has the expected encoded content"
        )


def test_intermediate_files_exist():
    """Test that the intermediate decoded text files exist somewhere in /home/user."""
    expected_files = ["doc_001_new.txt", "doc_002_new.txt", "doc_003_new.txt"]
    found_files = {f: False for f in expected_files}

    for root, dirs, files in os.walk("/home/user"):
        for file in files:
            if file in found_files:
                found_files[file] = True

    for f, found in found_files.items():
        assert found, f"Intermediate file {f} was not found in /home/user or its subdirectories."

    for doc_id, expected_content in EXPECTED.items():
        name = f"doc_{doc_id:03d}_new.txt"
        matches = files_named(name)
        assert any(open(path, "rb").read() == expected_content for path in matches), (
            f"No intermediate file named {name} has the correctly decoded content"
        )


def test_submitted_decoder_on_extracted_inputs(tmp_path):
    for doc_id, expected_content in EXPECTED.items():
        encoded_name = f"doc_{doc_id:03d}_new.txt.rle"
        matches = files_named(encoded_name)
        assert matches, f"Missing {encoded_name}"
        output = run_decoder(
            "/home/user/decoder",
            open(matches[0], "rb").read(),
            tmp_path,
            f"actual_{doc_id:03d}",
        )
        assert output == expected_content, f"Submitted decoder failed on {encoded_name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
