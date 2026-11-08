#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import stat
import subprocess
import tarfile
import tempfile

import pytest

DOCS_DIR = '/home/user/docs_raw'
SCRIPT_PATH = '/home/user/process_docs.sh'
ARCHIVE_PATH = '/home/user/final_docs.cgz'


def expected_sources():
    expected = {}
    for i in range(1, 51):
        if i % 5 in (0, 2):
            content = (
                f"STATUS: FINAL\n"
                f"Date: 2023-10-0{i}\n"
                f"[HEADER] Introduction Section {i}\n"
                f"This is the final text for document {i}.\n"
                f"[HEADER] Conclusion\n"
                f"End of document.\n"
            )
        else:
            content = (
                f"STATUS: DRAFT\n"
                f"Date: 2023-10-0{i}\n"
                f"[HEADER] Draft Section {i}\n"
                f"This is draft text. Needs revision.\n"
            )
        expected[f'doc_{i}.txt'] = content.encode()
    return expected


def assert_sources_unchanged():
    expected = expected_sources()
    actual_names = sorted(f for f in os.listdir(DOCS_DIR) if f.endswith('.txt'))
    assert actual_names == sorted(expected), "Original .txt filenames were changed."
    for name, wanted in expected.items():
        with open(os.path.join(DOCS_DIR, name), 'rb') as f:
            actual = f.read()
        assert actual == wanted, f"Original file {name} was modified."


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."
    assert_sources_unchanged()

    if os.path.lexists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert_sources_unchanged()


def test_script_exists_and_executable():
    script_path = '/home/user/process_docs.sh'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_original_files_untouched():
    docs_dir = '/home/user/docs_raw'
    assert os.path.isdir(docs_dir), f"Directory {docs_dir} is missing."
    files = [f for f in os.listdir(docs_dir) if f.endswith('.txt')]
    assert len(files) == 50, f"Expected 50 original .txt files, found {len(files)}. Original files may have been deleted."
    assert_sources_unchanged()


def test_archive_exists_and_header():
    archive_path = '/home/user/final_docs.cgz'
    assert os.path.exists(archive_path), f"Archive {archive_path} not found."

    with open(archive_path, 'rb') as f:
        header = f.read(14)
        assert header == b'DOCARCHIVE_V1\n', f"Invalid custom header. Expected b'DOCARCHIVE_V1\\n', got {header}"


def test_archive_contents():
    archive_path = '/home/user/final_docs.cgz'
    assert os.path.exists(archive_path), f"Archive {archive_path} not found."

    with open(archive_path, 'rb') as f:
        f.seek(14)
        gz_data = f.read()

    expected_txt = expected_sources()
    expected_md = {}
    for txt_name, raw in expected_txt.items():
        if b'STATUS: FINAL' not in raw:
            continue
        converted = b''.join(
            b'# ' + line[len(b'[HEADER] '):] if line.startswith(b'[HEADER] ') else line
            for line in raw.splitlines(keepends=True)
        )
        expected_md[txt_name[:-4] + '.md'] = converted

    with tempfile.TemporaryDirectory() as tmpdir:
        gz_path = os.path.join(tmpdir, 'payload.tar.gz')
        with open(gz_path, 'wb') as f:
            f.write(gz_data)

        try:
            with tarfile.open(gz_path, 'r:gz') as tar:
                seen = set()
                for member in tar.getmembers():
                    normalized = member.name
                    while normalized.startswith('./'):
                        normalized = normalized[2:]
                    if not normalized.endswith('.md') or '/' in normalized:
                        continue
                    assert member.isfile(), f"Archive member {member.name} is not a regular Markdown file."
                    assert normalized not in seen, f"Duplicate Markdown member {normalized} in archive."
                    seen.add(normalized)
                    source = tar.extractfile(member)
                    assert source is not None, f"Could not read archive member {member.name}."
                    with open(os.path.join(tmpdir, normalized), 'wb') as out:
                        out.write(source.read())
        except AssertionError:
            raise
        except Exception as e:
            raise AssertionError(f"Failed to decompress and extract tarball: {e}")

        extracted_files = [f for f in os.listdir(tmpdir) if f.endswith('.md')]
        assert len(extracted_files) == 20, f"Expected 20 .md files in the archive, found {len(extracted_files)}."
        assert set(extracted_files) == set(expected_md), (
            f"Archive Markdown filenames do not match the FINAL source files. "
            f"Expected {sorted(expected_md)}, found {sorted(extracted_files)}."
        )

        for md_file in extracted_files:
            with open(os.path.join(tmpdir, md_file), 'r') as f:
                content = f.read()
                assert "STATUS: FINAL" in content, f"File {md_file} is missing 'STATUS: FINAL'."
                assert "[HEADER]" not in content, f"File {md_file} still contains '[HEADER]'."
                assert "\n# " in content or content.startswith("# "), f"File {md_file} does not contain the replaced '# ' header."
            with open(os.path.join(tmpdir, md_file), 'rb') as f:
                actual = f.read()
            assert actual == expected_md[md_file], (
                f"File {md_file} is not the exact required conversion of its source .txt file."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
