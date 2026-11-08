#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import stat
import tarfile


def test_final_state():
    archive_dir = "/home/user/archive"
    source_archive = os.path.join(archive_dir, "legacy_docs.tar.gz")
    updated_archive = os.path.join(archive_dir, "updated_docs.tar.gz")
    temp_updated_archive = os.path.join(archive_dir, "updated_docs.tar.gz.tmp")

    # 1. The final file must exist and be a regular file, not a symlink.
    assert os.path.isfile(updated_archive), f"The final archive {updated_archive} does not exist."
    assert stat.S_ISREG(os.lstat(updated_archive).st_mode), f"{updated_archive} is not a regular file."

    # 2. The temporary file must NOT exist.
    assert not os.path.exists(temp_updated_archive), f"The temporary file {temp_updated_archive} should have been renamed/removed."

    # No extracted files or directories may remain in the archive workspace.
    assert set(os.listdir(archive_dir)) == {"legacy_docs.tar.gz", "updated_docs.tar.gz"}, \
        "Unexpected files or directories found in the archive workspace; the archive must not be extracted to disk."

    # Validate that the supplied source still has its complete expected contents.
    expected_names = {f"./doc_{i:03d}.md" for i in range(1, 101)}
    source_names = []
    with tarfile.open(source_archive, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile():
                source_names.append(member.name)
                f = tar.extractfile(member)
                assert f is not None
                number = int(member.name.removeprefix("./doc_").removesuffix(".md")) if member.name in expected_names else -1
                expected_content = (
                    f"This is document {number:03d} for AcmeCorp. Welcome to AcmeCorp.\n"
                    "AcmeCorp provides excellent solutions.\n"
                ).encode()
                assert f.read() == expected_content, f"The supplied source member {member.name} was modified."
            else:
                assert member.isdir() and member.name in {".", "./"}, f"Unexpected source member {member.name}."

    assert len(source_names) == 100, "The supplied source archive does not contain exactly 100 files."
    assert set(source_names) == expected_names, "The supplied source archive's file set was modified."

    # The complete uncompressed tar stream must be exactly the source stream with
    # AcmeCorp replaced by NovaCorp. This preserves every member, header, and byte
    # not involved in the requested replacement.
    with gzip.open(source_archive, "rb") as f:
        source_stream = f.read()
    with gzip.open(updated_archive, "rb") as f:
        updated_stream = f.read()

    assert source_stream.count(b"AcmeCorp") == 300, "The supplied source stream was modified."
    expected_stream = source_stream.replace(b"AcmeCorp", b"NovaCorp")
    assert updated_stream == expected_stream, \
        "The updated archive is not the complete source tar stream with only the requested replacement applied."

    # 3. Extracting/reading should yield valid files and correct content.
    nova_corp_count = 0
    file_count = 0

    try:
        with tarfile.open(updated_archive, 'r:gz') as tar:
            for member in tar.getmembers():
                if member.isfile():
                    file_count += 1
                    f = tar.extractfile(member)
                    content = f.read().decode('utf-8', errors='replace')

                    # 4. Searching for old name should return 0 results.
                    assert "AcmeCorp" not in content, f"Found 'AcmeCorp' in {member.name} inside the updated archive. It should be replaced."

                    # Count new name occurrences.
                    nova_corp_count += content.count("NovaCorp")
    except tarfile.TarError as e:
        assert False, f"Failed to read {updated_archive} as a gzip-compressed tar archive: {e}"

    assert file_count > 0, "The updated archive contains no files."

    # 5. Searching for new name should return > 0 results.
    assert nova_corp_count > 0, "Could not find 'NovaCorp' in the updated archive. Replacement may have failed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
