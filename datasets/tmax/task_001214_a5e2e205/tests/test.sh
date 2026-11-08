#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import tarfile

FINAL_TARBALL = "/home/user/final_docs.tar.gz"
EXTRACTED_DIR = "/home/user/extracted"
SOURCE = "/home/user/legacy_docs.txt"


def expected_documents():
    with open(SOURCE, "rb") as f:
        lines = f.read().splitlines(keepends=True)

    documents = {}
    i = 0
    while i < len(lines):
        header = lines[i].rstrip(b"\r\n")
        match = re.fullmatch(br"===FILE:(.+)===", header)
        assert match, f"Malformed source header at line {i + 1}: {header!r}"
        original_name = match.group(1).decode("utf-8")
        i += 1

        content = []
        while i < len(lines) and lines[i].rstrip(b"\r\n") != b"===EOF===":
            content.append(lines[i])
            i += 1
        assert i < len(lines), f"Missing EOF marker for {original_name}"
        i += 1

        renamed = re.fullmatch(r"Draft_v[0-9]+_(.+)", original_name)
        assert renamed, f"Unexpected legacy filename: {original_name}"
        final_name = renamed.group(1)
        assert final_name not in documents, f"Duplicate renamed filename: {final_name}"
        documents[final_name] = b"".join(content)

    return documents


def test_final_tarball_exists():
    assert os.path.exists(FINAL_TARBALL), f"The final archive {FINAL_TARBALL} does not exist."
    assert os.path.isfile(FINAL_TARBALL), f"{FINAL_TARBALL} is not a file."
    assert not os.path.islink(FINAL_TARBALL), f"{FINAL_TARBALL} must not be a symlink."


def test_final_tarball_contents():
    assert os.path.exists(FINAL_TARBALL), f"The final archive {FINAL_TARBALL} does not exist."
    expected = expected_documents()

    with tarfile.open(FINAL_TARBALL, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        # Preserve the original checks for required names and removed prefixes.
        for expected_name in {"intro.md", "api_reference.md", "troubleshooting.md"}:
            assert expected_name in names, f"Expected file '{expected_name}' is missing from the tarball."
        for name in names:
            assert not name.startswith("Draft_"), f"File '{name}' in tarball still has the 'Draft_' prefix."

        assert len(names) == len(set(names)), "The tarball contains duplicate member names."
        assert set(names) == set(expected), (
            f"Tarball members differ from source-derived files: got {names}, "
            f"expected {sorted(expected)}"
        )

        for member in members:
            assert member.isfile(), f"Tar member '{member.name}' is not a regular file."
            assert member.name == os.path.basename(member.name), (
                f"Tar member '{member.name}' contains a directory path."
            )
            stream = tar.extractfile(member)
            assert stream is not None
            actual = stream.read()
            assert actual == expected[member.name], f"Content of {member.name} does not match the source."

        troubleshooting = tar.extractfile("troubleshooting.md").read().decode("utf-8")
        assert "Have you tried turning it off and on again?" in troubleshooting, (
            f"Content of troubleshooting.md is incorrect. Got: {troubleshooting}"
        )


def test_extracted_directory_exists():
    assert os.path.exists(EXTRACTED_DIR), f"The directory {EXTRACTED_DIR} does not exist."
    assert os.path.isdir(EXTRACTED_DIR), f"{EXTRACTED_DIR} is not a directory."

    expected = expected_documents()
    actual_names = set(os.listdir(EXTRACTED_DIR))
    assert actual_names == set(expected), (
        f"Extracted directory contents differ from source-derived files: "
        f"got {sorted(actual_names)}, expected {sorted(expected)}"
    )

    for name, expected_content in expected.items():
        path = os.path.join(EXTRACTED_DIR, name)
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f"Extracted path '{name}' is not a regular file."
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Extracted content of {name} does not match the source."


def test_final_archive_was_atomically_installed():
    archive_stat = os.stat(FINAL_TARBALL, follow_symlinks=False)
    assert archive_stat.st_ctime_ns > archive_stat.st_mtime_ns, (
        "The final archive metadata is not consistent with creating it at a temporary path "
        "and then atomically moving it into place."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
