#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

import pytest
import requests

BACKUPS = Path('/home/user/docs_backup')
QUARANTINE = Path('/home/user/quarantine')
EXTRACTED = Path('/home/user/extracted_docs')
BASE_URL = 'http://127.0.0.1:8080'


def get(path, **kwargs):
    try:
        return requests.get(BASE_URL + path, timeout=2, **kwargs)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to {BASE_URL + path}: {e}')


def test_archive_integrity_and_quarantine():
    quarantine_file = QUARANTINE / 'backup_2.tar'
    assert quarantine_file.is_file(), f'Malicious archive was not moved to {quarantine_file}'
    assert not (BACKUPS / 'backup_2.tar').exists(), 'Malicious archive remains in docs_backup'
    assert not Path('/etc/pwned').exists(), 'The traversal payload was extracted to /etc/pwned'

    with tarfile.open(quarantine_file, 'r') as archive:
        members = archive.getmembers()
        assert [m.name for m in members] == ['../../../etc/pwned']
        assert members[0].isfile()
        assert archive.extractfile(members[0]).read() == b'Pwned'

    expected_archives = {
        'backup_0.tar': {
            'docs/intro.txt': b'Base doc\n',
            'docs/old.HTM': b'<html>Old html</html>\n',
        },
        'backup_1.tar': {'docs/new.txt': b'New doc\n'},
        'backup_3.tar': {
            'docs/final.txt': b'Final doc\n',
            'docs/bad_doc.txt': b'Corrupted doc\n',
        },
    }
    for archive_name, expected_files in expected_archives.items():
        archive_path = BACKUPS / archive_name
        assert archive_path.is_file(), f'Safe archive is missing: {archive_path}'
        with tarfile.open(archive_path, 'r') as archive:
            actual_files = {
                member.name: archive.extractfile(member).read()
                for member in archive.getmembers()
                if member.isfile()
            }
        assert actual_files == expected_files, f'Archive contents changed: {archive_path}'


def test_complete_extracted_state():
    expected = {
        'docs/intro.txt': b'Base doc\n',
        'docs/old.html': b'<html>Old html</html>\n',
        'docs/new.txt': b'New doc\n',
        'docs/final.txt': b'Final doc\n',
    }
    for relative, contents in expected.items():
        path = EXTRACTED / relative
        assert path.is_file(), f'Expected reconstructed document is missing: {path}'
        assert path.read_bytes() == contents, f'Unexpected contents in {path}'

    old_html = EXTRACTED / 'docs/old.html'
    assert old_html.is_file(), f'File {old_html} is missing. It should have been renamed from .HTM'
    assert not (EXTRACTED / 'docs/old.HTM').exists(), 'The original .HTM file was not renamed'

    bad_doc = EXTRACTED / 'docs/bad_doc.txt'
    assert not bad_doc.exists(), f'File {bad_doc} should have been deleted based on the error log'

    actual_document_files = {
        str(path.relative_to(EXTRACTED))
        for path in EXTRACTED.rglob('*')
        if path.is_file() and path.name != 'index.dat'
    }
    assert actual_document_files == set(expected), 'Extracted document tree is incomplete or contains unexpected files'


def test_index_was_built_exactly_by_the_supplied_indexer():
    index_path = EXTRACTED / 'index.dat'
    assert index_path.is_file(), 'index.dat is missing from extracted_docs'
    assert Path('/app/doc_indexer').is_file()
    assert os.access('/app/doc_indexer', os.X_OK)

    with tempfile.TemporaryDirectory() as workdir:
        result = subprocess.run(
            ['/app/doc_indexer', '--build', str(EXTRACTED)],
            cwd=workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
        assert result.returncode == 0, f'doc_indexer failed: {result.stderr!r}'
        expected_index = (Path(workdir) / 'index.dat').read_bytes()

    assert index_path.read_bytes() == expected_index, 'index.dat is not the exact output of doc_indexer'


def test_api_index():
    response = get('/api/index')
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    assert response.text.startswith('MAGIC_INDEX_V1'), 'Response does not start with MAGIC_INDEX_V1'
    assert response.content == (EXTRACTED / 'index.dat').read_bytes(), '/api/index did not return the exact index.dat bytes'


def test_api_docs():
    response = get('/api/docs', params={'file': 'old.html'})
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    assert '<html>Old html</html>' in response.text, 'Response does not contain the expected HTML content'
    assert response.content == b'<html>Old html</html>\n'

    expected = {
        'intro.txt': b'Base doc\n',
        'new.txt': b'New doc\n',
        'final.txt': b'Final doc\n',
    }
    for filename, contents in expected.items():
        response = get('/api/docs', params={'file': filename})
        assert response.status_code == 200, f'Expected {filename} to be served'
        assert response.content == contents


def test_api_recursive_lookup_is_not_hardcoded():
    filename = f'verifier-{uuid.uuid4().hex}.txt'
    contents = os.urandom(48)
    nested = EXTRACTED / 'verifier-runtime' / 'deeply' / 'nested'
    nested.mkdir(parents=True, exist_ok=True)
    test_file = nested / filename
    test_file.write_bytes(contents)
    try:
        response = get('/api/docs', params={'file': filename})
        assert response.status_code == 200, 'Server did not recursively find a runtime-created document'
        assert response.content == contents, 'Server returned the wrong runtime-created document'
    finally:
        if test_file.exists():
            test_file.unlink()
        for directory in [nested, nested.parent, nested.parent.parent]:
            try:
                directory.rmdir()
            except OSError:
                pass


def test_api_missing_document_returns_404():
    missing = f'missing-{uuid.uuid4().hex}.txt'
    response = get('/api/docs', params={'file': missing})
    assert response.status_code == 404, f'Expected status code 404, got {response.status_code}'

    response = get('/api/docs', params={'file': 'old.HTM'})
    assert response.status_code == 404, 'The pre-rename .HTM filename should not be served'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
