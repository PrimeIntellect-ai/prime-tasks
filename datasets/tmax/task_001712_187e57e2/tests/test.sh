#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import runpy
import sys
import tarfile
import zipfile


def expected_document():
    with tarfile.open('/home/user/docs.tar.gz', mode='r:gz') as archive:
        members = [m for m in archive.getmembers() if os.path.basename(m.name) == 'project.zip' and m.isfile()]
        assert len(members) == 1, "docs.tar.gz must contain exactly one project.zip file."
        nested = archive.extractfile(members[0])
        assert nested is not None
        zip_bytes = nested.read()

    with zipfile.ZipFile(io.BytesIO(zip_bytes), mode='r') as project:
        names = sorted(name for name in project.namelist() if name.endswith('.txt') and not name.endswith('/'))
        return '\n'.join(project.read(name).decode('utf-8') for name in names)


def test_script_exists_and_atomic_write():
    script_path = '/home/user/build_docs.py'
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    with open(script_path, 'r', encoding='utf-8') as f:
        script_content = f.read()

    # Retain the original atomic-write assertion.
    has_atomic = any(func in script_content for func in ['os.replace', 'os.rename', 'shutil.move'])
    assert has_atomic, "Atomic write logic (os.replace, os.rename, or shutil.move) is missing in the script."


def test_execute_script_and_atomic_behavior():
    script_path = '/home/user/build_docs.py'
    final_path = os.path.abspath('/home/user/final_doc.md')
    expected = expected_document()

    # A pre-existing destination ensures the script must atomically replace it.
    with open(final_path, 'w', encoding='utf-8') as f:
        f.write('stale destination that must be replaced')

    rename_events = []
    direct_writes = []

    def audit(event, args):
        if event == 'os.rename' and len(args) >= 2:
            src, dst = args[0], args[1]
            if isinstance(dst, (str, bytes, os.PathLike)):
                dst_path = os.path.abspath(os.fsdecode(dst))
                if dst_path == final_path:
                    rename_events.append((os.path.abspath(os.fsdecode(src)), dst_path))
        elif event == 'open' and len(args) >= 2:
            path, mode = args[0], args[1]
            if isinstance(path, (str, bytes, os.PathLike)):
                path = os.path.abspath(os.fsdecode(path))
                if path == final_path and isinstance(mode, str) and any(c in mode for c in 'wax+'):
                    direct_writes.append((path, mode))

    sys.addaudithook(audit)

    # Extraction APIs are forbidden: both archives must remain in memory.
    forbidden = lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("Archive contents were extracted to disk."))
    old_tar_extract = tarfile.TarFile.extract
    old_tar_extractall = tarfile.TarFile.extractall
    old_zip_extract = zipfile.ZipFile.extract
    old_zip_extractall = zipfile.ZipFile.extractall
    tarfile.TarFile.extract = forbidden
    tarfile.TarFile.extractall = forbidden
    zipfile.ZipFile.extract = forbidden
    zipfile.ZipFile.extractall = forbidden

    stdout = io.StringIO()
    old_argv = sys.argv
    try:
        sys.argv = [script_path]
        with contextlib.redirect_stdout(stdout):
            runpy.run_path(script_path, run_name='__main__')
    finally:
        sys.argv = old_argv
        tarfile.TarFile.extract = old_tar_extract
        tarfile.TarFile.extractall = old_tar_extractall
        zipfile.ZipFile.extract = old_zip_extract
        zipfile.ZipFile.extractall = old_zip_extractall

    assert not direct_writes, "The script wrote directly to final_doc.md instead of replacing it atomically."
    assert rename_events, "The script did not atomically rename/move a temporary file to final_doc.md."
    assert any(src != dst for src, dst in rename_events), "The atomic rename source must be a temporary file."
    assert stdout.getvalue().strip() == str(len(expected)), "The script did not print the exact expected character count."


def test_final_doc_content():
    doc_path = '/home/user/final_doc.md'
    assert os.path.exists(doc_path), f"The final document {doc_path} does not exist."
    assert os.path.isfile(doc_path), f"{doc_path} is not a file."

    with open(doc_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Retain the original content and ordering assertions.
    assert "# API Documentation" in content, "final_doc.md is missing API Documentation."
    assert "# Introduction" in content, "final_doc.md is missing Introduction."
    assert "# Setup Instructions" in content, "final_doc.md is missing Setup Instructions."
    idx_api = content.find("# API")
    idx_intro = content.find("# Introduction")
    idx_setup = content.find("# Setup")
    assert idx_api < idx_intro < idx_setup, "The contents are not concatenated in alphabetical order of their filenames."

    assert content == expected_document(), "final_doc.md does not exactly match all sorted .txt files from the nested archive."


def test_char_count_file():
    count_path = '/home/user/char_count.txt'
    doc_path = '/home/user/final_doc.md'

    assert os.path.exists(count_path), f"The character count file {count_path} does not exist."
    assert os.path.isfile(count_path), f"{count_path} is not a file."
    assert os.path.exists(doc_path), f"Cannot verify char count because {doc_path} is missing."

    with open(doc_path, 'r', encoding='utf-8') as f:
        actual_content_len = len(f.read())
    with open(count_path, 'r', encoding='utf-8') as f:
        count_str = f.read().strip()

    assert count_str.isdigit(), "The content of char_count.txt is not a valid integer."
    assert int(count_str) == actual_content_len, f"Expected character count {actual_content_len}, but got {count_str} in char_count.txt."
    assert int(count_str) == len(expected_document()), "char_count.txt does not contain the archive-derived character count."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
