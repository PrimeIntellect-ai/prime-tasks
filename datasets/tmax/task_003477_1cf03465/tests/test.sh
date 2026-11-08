#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile

RAW_ARCHIVE = "/home/user/raw_docs.tar.gz"
ORGANIZED = "/home/user/organized_docs"
FINAL_ARCHIVE = "/home/user/final_docs.tar.gz"


def expected_outputs():
    text = {}
    binary = {}
    modified = 0

    with tarfile.open(RAW_ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            source = tar.extractfile(member).read()
            basename = os.path.basename(member.name)
            lowered = basename.lower()

            if lowered.endswith((".txt", ".md")):
                assert basename not in text, f"Duplicate source filename: {basename}"
                transformed = source.replace(b"AcmeCorp", b"ZenithInc")
                if transformed != source:
                    modified += 1
                text[basename] = transformed
            elif lowered.endswith((".bin", ".dat")) and source[:4] == b"BDOC":
                assert basename not in binary, f"Duplicate source filename: {basename}"
                binary[basename] = source

    return text, binary, modified


EXPECTED_TEXT, EXPECTED_BINARY, MODIFIED_COUNT = expected_outputs()


def test_processing_log_contents():
    log_path = "/home/user/processing_log.txt"
    assert os.path.isfile(log_path), f"Log file missing at {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "Text files modified: 2\nValid binary files: 2"
    assert content == expected_content, (
        f"Log file content incorrect. Expected:\n{expected_content}\nGot:\n{content}"
    )
    derived_content = (
        f"Text files modified: {MODIFIED_COUNT}\n"
        f"Valid binary files: {len(EXPECTED_BINARY)}"
    )
    assert content == derived_content


def test_organized_directory_exact_contents():
    assert os.path.isdir(ORGANIZED), f"Missing directory: {ORGANIZED}"
    text_dir = os.path.join(ORGANIZED, "text")
    binary_dir = os.path.join(ORGANIZED, "binary")
    assert os.path.isdir(text_dir), f"Missing directory: {text_dir}"
    assert os.path.isdir(binary_dir), f"Missing directory: {binary_dir}"

    assert set(os.listdir(ORGANIZED)) == {"text", "binary"}
    assert set(os.listdir(text_dir)) == set(EXPECTED_TEXT)
    assert set(os.listdir(binary_dir)) == set(EXPECTED_BINARY)

    for basename, expected in EXPECTED_TEXT.items():
        path = os.path.join(text_dir, basename)
        assert os.path.isfile(path) and not os.path.islink(path)
        with open(path, "rb") as f:
            assert f.read() == expected, f"Incorrect transformed contents in {path}"

    for basename, expected in EXPECTED_BINARY.items():
        path = os.path.join(binary_dir, basename)
        assert os.path.isfile(path) and not os.path.islink(path)
        with open(path, "rb") as f:
            actual = f.read()
        assert actual[:4] == b"BDOC", f"Invalid binary header in {path}"
        assert actual == expected, f"Binary bytes were not preserved in {path}"


def test_final_docs_tarball_exists_and_valid():
    assert os.path.isfile(FINAL_ARCHIVE), f"Final tarball missing at {FINAL_ARCHIVE}"
    assert tarfile.is_tarfile(FINAL_ARCHIVE), f"File {FINAL_ARCHIVE} is not a valid tar archive"


def archive_regular_files():
    found = {}
    with tarfile.open(FINAL_ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            assert member.isfile() or member.isdir(), (
                f"Unexpected non-file archive member: {member.name}"
            )
            if not member.isfile():
                continue

            normalized = member.name.rstrip("/")
            basename = os.path.basename(normalized)
            parent = os.path.basename(os.path.dirname(normalized))
            key = (parent, basename)
            assert key not in found, f"Duplicate archive member for {parent}/{basename}"
            found[key] = tar.extractfile(member).read()
    return found


def test_final_docs_tarball_contents():
    with tarfile.open(FINAL_ARCHIVE, "r:gz") as tar:
        names = tar.getnames()
        text_files = [n for n in names if n.endswith(".txt") or n.endswith(".md")]
        binary_files = [n for n in names if n.endswith(".bin") or n.endswith(".dat")]

        text_basenames = {os.path.basename(n) for n in text_files}
        binary_basenames = {os.path.basename(n) for n in binary_files}

        assert text_basenames == {"file1.txt", "file2.md", "file3.txt"}, f"Text files in archive incorrect: {text_basenames}"
        assert binary_basenames == {"legacy1.bin", "legacy3.bin"}, f"Binary files in archive incorrect: {binary_basenames}"

        for f in text_files:
            assert os.path.basename(os.path.dirname(f)) == "text", f"Text file {f} not in a 'text' directory"
        for f in binary_files:
            assert os.path.basename(os.path.dirname(f)) == "binary", f"Binary file {f} not in a 'binary' directory"

    actual = archive_regular_files()
    expected = {
        **{("text", name): data for name, data in EXPECTED_TEXT.items()},
        **{("binary", name): data for name, data in EXPECTED_BINARY.items()},
    }
    assert set(actual) == set(expected), f"Archive regular-file set incorrect: {set(actual)}"
    for key, expected_bytes in expected.items():
        assert actual[key] == expected_bytes, f"Incorrect archived contents for {key[0]}/{key[1]}"


def test_text_files_transformation():
    with tarfile.open(FINAL_ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile() and (member.name.endswith(".txt") or member.name.endswith(".md")):
                content = tar.extractfile(member).read().decode("utf-8")
                assert "AcmeCorp" not in content, f"File {member.name} still contains 'AcmeCorp'"
                if os.path.basename(member.name) in ["file1.txt", "file3.txt"]:
                    assert "ZenithInc" in content, f"File {member.name} does not contain 'ZenithInc' as expected"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
