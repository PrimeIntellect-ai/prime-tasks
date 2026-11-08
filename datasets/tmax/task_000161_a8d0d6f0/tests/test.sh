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
import hashlib
import os
import shutil
import socket
import subprocess
import tarfile
import tempfile

import pytest
import requests


def digest_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


@pytest.fixture(scope='session')
def archive_expected():
    archive = '/home/user/raw_docs.tar.gz'
    assert os.path.isfile(archive), f"Archive {archive} does not exist."

    temp_dir = tempfile.mkdtemp(prefix='verifier_raw_docs_')
    expected = {}
    try:
        with tarfile.open(archive, 'r:gz') as tf:
            members = [m for m in tf.getmembers() if m.isfile() and m.name.endswith('.txt')]
            for index, member in enumerate(members):
                source = tf.extractfile(member)
                assert source is not None, f"Could not read {member.name} from archive."

                temp_path = os.path.join(temp_dir, f'{index}.txt')
                with source, open(temp_path, 'wb') as out:
                    shutil.copyfileobj(source, out)

                with open(temp_path, 'rb') as f:
                    metadata = f.read(500)
                title_lines = [line for line in metadata.splitlines() if line.startswith(b'Doc-Title: ')]
                assert title_lines, f"No Doc-Title metadata found in first 500 bytes of {member.name}."
                title = title_lines[0][len(b'Doc-Title: '):].decode('utf-8')

                result = subprocess.run(
                    ['/app/doc_hasher', temp_path], capture_output=True, text=True
                )
                assert result.returncode == 0, f"doc_hasher failed on archived file {member.name}"
                file_hash = result.stdout.strip()
                filename = f"{file_hash}_{title.replace(' ', '_')}.txt"
                assert filename not in expected, f"Archive produces duplicate destination filename {filename}."
                expected[filename] = {
                    'size': os.path.getsize(temp_path),
                    'digest': digest_file(temp_path),
                }

        yield expected
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_organized_docs_directory(archive_expected):
    org_dir = '/home/user/organized_docs'
    assert os.path.isdir(org_dir), f"Directory {org_dir} does not exist."
    files = [f for f in os.listdir(org_dir) if f.endswith('.txt')]
    assert len(files) == 3, f"Expected exactly 3 .txt files in {org_dir}, found {len(files)}."

    expected_titles = {"Architecture_Plan", "API_Reference_V2", "Database_Schema"}

    for f in files:
        filepath = os.path.join(org_dir, f)

        # Get hash using the binary
        result = subprocess.run(['/app/doc_hasher', filepath], capture_output=True, text=True)
        assert result.returncode == 0, f"doc_hasher failed on {filepath}"
        file_hash = result.stdout.strip()

        # Check filename format
        assert f.startswith(file_hash + "_"), f"Filename {f} does not start with its hash {file_hash}_"

        title_part = f[len(file_hash)+1:-4]
        assert title_part in expected_titles, f"Unexpected title part in filename: {title_part}"
        expected_titles.remove(title_part)

    assert len(expected_titles) == 0, f"Missing files for titles: {expected_titles}"

    # Verify the names and complete contents come from the supplied archive.
    assert set(files) == set(archive_expected), (
        f"Organized filenames do not match archive-derived filenames: "
        f"expected {set(archive_expected)}, found {set(files)}"
    )
    for filename, expected in archive_expected.items():
        filepath = os.path.join(org_dir, filename)
        assert os.path.getsize(filepath) == expected['size'], f"Size mismatch for {filename}"
        assert digest_file(filepath) == expected['digest'], f"Content mismatch for {filename}"


def test_http_service():
    org_dir = '/home/user/organized_docs'
    if not os.path.isdir(org_dir):
        pytest.fail(f"Directory {org_dir} does not exist.")

    files = [f for f in os.listdir(org_dir) if f.endswith('.txt')]
    assert len(files) == 3, "Prerequisite failed: exactly 3 files not found."

    for f in files:
        url = f"http://127.0.0.1:8080/{f}"
        try:
            resp = requests.get(url, timeout=2)
            assert resp.status_code == 200, f"HTTP GET {url} returned status {resp.status_code}"

            # Verify content matches
            filepath = os.path.join(org_dir, f)
            with open(filepath, 'rb') as local_f:
                local_content = local_f.read()
            assert resp.content == local_content, f"Content mismatch for {url}"
        except requests.RequestException as e:
            pytest.fail(f"HTTP request to {url} failed: {e}")


def test_tcp_metadata_service():
    org_dir = '/home/user/organized_docs'
    if not os.path.isdir(org_dir):
        pytest.fail(f"Directory {org_dir} does not exist.")

    files = [f for f in os.listdir(org_dir) if f.endswith('.txt')]
    assert len(files) == 3, "Prerequisite failed: exactly 3 files not found."

    for f in files:
        filepath = os.path.join(org_dir, f)
        result = subprocess.run(['/app/doc_hasher', filepath], capture_output=True, text=True)
        file_hash = result.stdout.strip()

        try:
            with socket.create_connection(('127.0.0.1', 9090), timeout=2) as s:
                s.sendall(f"{file_hash}\n".encode('utf-8'))
                response = b""
                while True:
                    chunk = s.recv(1024)
                    if not chunk:
                        break
                    response += chunk
                response_str = response.decode('utf-8')
                expected_response = f"{f}\n"
                assert response_str == expected_response, (
                    f"TCP service returned {response_str!r} instead of {expected_response!r}"
                )
        except Exception as e:
            pytest.fail(f"TCP connection/request failed for hash {file_hash}: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
