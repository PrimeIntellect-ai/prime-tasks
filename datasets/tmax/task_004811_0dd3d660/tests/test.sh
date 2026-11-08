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
import io
import json
import os
import subprocess
import tarfile
import zipfile
from urllib.parse import quote

import pytest
import requests

RAW_DIR = "/home/user/raw_datasets"
CLEAN_DIR = "/home/user/clean_datasets"
FILTER = "/app/data_filter"


def collect_candidates():
    candidates = []

    def process_blob(name, content):
        lower = name.lower()
        if lower.endswith(".zip"):
            with zipfile.ZipFile(io.BytesIO(content)) as archive:
                for info in archive.infolist():
                    if not info.is_dir():
                        process_blob(info.filename, archive.read(info))
        elif lower.endswith((".tar.gz", ".tgz")):
            with tarfile.open(fileobj=io.BytesIO(content), mode="r:gz") as archive:
                for member in archive.getmembers():
                    if member.isfile():
                        extracted = archive.extractfile(member)
                        assert extracted is not None
                        process_blob(member.name, extracted.read())
        else:
            candidates.append((os.path.basename(name), content))

    for root, _, files in os.walk(RAW_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            with open(path, "rb") as source:
                process_blob(filename, source.read())

    return candidates


def derive_expected():
    assert os.path.isfile(FILTER), f"Validation utility {FILTER} does not exist"
    assert os.access(FILTER, os.X_OK), f"Validation utility {FILTER} is not executable"

    expected = {}
    for basename, content in collect_candidates():
        result = subprocess.run(
            [FILTER], input=content, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=False
        )
        if result.stdout == b"VALID\n":
            assert basename not in expected, f"Duplicate valid base name: {basename}"
            expected[basename] = content
    return expected


EXPECTED = derive_expected()


def test_clean_datasets_files():
    assert os.path.isdir(CLEAN_DIR), f"Directory {CLEAN_DIR} does not exist"

    valid1_path = os.path.join(CLEAN_DIR, "valid1.txt")
    valid2_path = os.path.join(CLEAN_DIR, "valid2.txt")
    assert os.path.isfile(valid1_path), f"File {valid1_path} does not exist"
    assert os.path.isfile(valid2_path), f"File {valid2_path} does not exist"

    with open(valid1_path, "rb") as f:
        assert f.read() == b"BIOSEQ_v2\tATGC\n", f"Content of {valid1_path} is incorrect"
    with open(valid2_path, "rb") as f:
        assert f.read() == b"BIOSEQ_v2\tCGTA\n", f"Content of {valid2_path} is incorrect"

    actual_files = sorted(
        name for name in os.listdir(CLEAN_DIR)
        if os.path.isfile(os.path.join(CLEAN_DIR, name))
    )
    assert actual_files == sorted(EXPECTED), (
        f"Clean dataset files differ from validator results: "
        f"expected {sorted(EXPECTED)}, got {actual_files}"
    )

    for name, expected_content in EXPECTED.items():
        path = os.path.join(CLEAN_DIR, name)
        assert os.path.isfile(path), f"File {path} does not exist"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Content of {path} is incorrect"


def get(url):
    try:
        return requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")


def test_http_list():
    url = "http://127.0.0.1:9090/list"
    response = get(url)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")

    assert isinstance(data, list), "Response JSON should be a list"
    assert "valid1.txt" in data, "valid1.txt not found in /list response"
    assert "valid2.txt" in data, "valid2.txt not found in /list response"
    assert len(data) == 2, f"Expected exactly 2 files in list, got {len(data)}"
    assert len(data) == len(set(data)), "/list response contains duplicate filenames"
    assert sorted(data) == sorted(EXPECTED), (
        f"/list differs from validator results: expected {sorted(EXPECTED)}, got {data}"
    )


def test_http_data_valid1():
    url = "http://127.0.0.1:9090/data/valid1.txt"
    response = get(url)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    assert response.content == b"BIOSEQ_v2\tATGC\n", (
        f"Content for valid1.txt is incorrect: {response.content!r}"
    )


def test_http_data_valid2():
    url = "http://127.0.0.1:9090/data/valid2.txt"
    response = get(url)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    assert response.content == b"BIOSEQ_v2\tCGTA\n", (
        f"Content for valid2.txt is incorrect: {response.content!r}"
    )


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_http_data_all_validator_selected_files(name):
    url = "http://127.0.0.1:9090/data/" + quote(name, safe="")
    response = get(url)
    assert response.status_code == 200, (
        f"Expected status code 200 for {name}, got {response.status_code}"
    )
    assert response.content == EXPECTED[name], (
        f"HTTP content for {name} does not match the source file selected by data_filter"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
