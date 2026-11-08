#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import fcntl
import io
import os
import time
import uuid
import zipfile

import pytest
import requests

PORT = 8555
TOKEN = "ALPHA-99-BETA"
URL = f"http://127.0.0.1:{PORT}/analyze"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
SAFE_STORAGE = "/app/safe_storage"
LOCK_PATH = os.path.join(SAFE_STORAGE, "extraction.lock")


def make_zip(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, content in entries:
            zf.writestr(name, content)
    return buf.getvalue()


def create_zip_slip():
    return make_zip([("../../../../../tmp/evil.txt", b"evil content")])


def create_valid_zip(prefix=""):
    return make_zip([
        (f"{prefix}test.txt", b"hello world"),
        (f"{prefix}image.png", b"\x89PNG\r\n\x1a\nfake png"),
        (f"{prefix}binary.bin", b"\x7fELF\x01\x01\x01fake elf"),
    ])


def post(payload, headers=HEADERS, timeout=10):
    try:
        return requests.post(URL, headers=headers, data=payload, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")


def parse_retained(response):
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got invalid JSON: {response.text}")
    assert "retained_files" in data, f"Response JSON missing 'retained_files' key: {data}"
    value = data["retained_files"]
    assert isinstance(value, int) and not isinstance(value, bool) and value >= 0, \
        f"retained_files must be a non-negative integer, got {value!r}"
    return value


def empty_zip():
    return make_zip([])


def test_unauthenticated_request():
    response = post(b"dummy", headers={})
    assert response.status_code == 401, \
        f"Expected HTTP 401 for missing auth, got {response.status_code}. Response: {response.text}"


def test_wrong_tokens_are_rejected_exactly():
    invalid_headers = [
        {"Authorization": "Bearer WRONG-TOKEN"},
        {"Authorization": f"bearer {TOKEN}"},
        {"Authorization": f"Bearer {TOKEN} "},
        {"Authorization": TOKEN},
    ]
    for headers in invalid_headers:
        response = post(empty_zip(), headers=headers)
        assert response.status_code == 401, \
            f"Expected HTTP 401 for invalid Authorization header {headers!r}, got {response.status_code}"


def test_zip_slip_rejection():
    response = post(create_zip_slip())
    assert response.status_code == 400, \
        f"Expected HTTP 400 for zip slip payload, got {response.status_code}. Response: {response.text}"


def test_randomized_traversal_and_absolute_paths_are_completely_rejected():
    marker = f"archive_escape_{uuid.uuid4().hex}"
    outside = os.path.join("/tmp", marker)
    benign = f"must_not_extract_{uuid.uuid4().hex}.txt"
    benign_path = os.path.join(SAFE_STORAGE, benign)
    for path in (outside, benign_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    traversal = make_zip([
        (f"../../../../../tmp/{marker}", b"escaped"),
        (benign, b"benign member must not be extracted"),
    ])
    response = post(traversal)
    assert response.status_code == 400, \
        f"Expected HTTP 400 for randomized traversal archive, got {response.status_code}: {response.text}"
    assert not os.path.exists(outside), "Traversal member escaped /app/safe_storage"
    assert not os.path.exists(benign_path), "A partially malicious archive was not completely rejected"

    absolute = make_zip([
        (f"/tmp/{marker}", b"absolute escape"),
        (benign, b"benign member must not be extracted"),
    ])
    response = post(absolute)
    assert response.status_code == 400, \
        f"Expected HTTP 400 for absolute archive member, got {response.status_code}: {response.text}"
    assert not os.path.exists(outside), "Absolute archive member escaped /app/safe_storage"
    assert not os.path.exists(benign_path), "Archive with an absolute member was partially extracted"


def test_valid_extraction_and_elf_deletion():
    response = post(create_valid_zip(prefix="run1_"))
    assert response.status_code == 200, \
        f"Expected HTTP 200 for valid payload, got {response.status_code}. Response: {response.text}"
    parse_retained(response)

    assert os.path.exists(os.path.join(SAFE_STORAGE, "run1_test.txt")), \
        "Text file was not extracted or was incorrectly deleted."
    assert os.path.exists(os.path.join(SAFE_STORAGE, "run1_image.png")), \
        "PNG file was not extracted or was incorrectly deleted."
    assert not os.path.exists(os.path.join(SAFE_STORAGE, "run1_binary.bin")), \
        "ELF file was extracted but not deleted as required."


def test_concurrent_requests():
    num_requests = 5
    payloads = [create_valid_zip(prefix=f"concurrent_{i}_") for i in range(num_requests)]

    def send_request(payload):
        return post(payload, timeout=15)

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_requests) as executor:
        futures = [executor.submit(send_request, payload) for payload in payloads]
        responses = [future.result() for future in concurrent.futures.as_completed(futures)]

    for response in responses:
        assert response.status_code == 200, \
            f"Concurrent request failed with status {response.status_code}. Response: {response.text}"
        parse_retained(response)

    for i in range(num_requests):
        assert os.path.exists(os.path.join(SAFE_STORAGE, f"concurrent_{i}_test.txt")), \
            f"Concurrent text file {i} missing."
        assert os.path.exists(os.path.join(SAFE_STORAGE, f"concurrent_{i}_image.png")), \
            f"Concurrent PNG file {i} missing."
        assert not os.path.exists(os.path.join(SAFE_STORAGE, f"concurrent_{i}_binary.bin")), \
            f"Concurrent ELF file {i} not deleted."


def test_generalized_nested_archive_content_and_retained_count():
    baseline_response = post(empty_zip())
    assert baseline_response.status_code == 200, \
        f"Expected an empty valid ZIP to return 200, got {baseline_response.status_code}: {baseline_response.text}"
    baseline = parse_retained(baseline_response)

    root = f"random_{uuid.uuid4().hex}"
    retained = {
        f"{root}/alpha.data": os.urandom(37),
        f"{root}/deep/path/picture.exe": b"\x89PNG\r\n\x1a\nnot really an executable",
        f"{root}/short.bin": b"\x7fEL",
        f"{root}/empty.file": b"",
    }
    elf_paths = {
        f"{root}/deep/malware.txt": b"\x7fELF" + os.urandom(29),
        f"{root}/program.png": b"\x7fELFfake image",
    }
    response = post(make_zip(list(retained.items()) + list(elf_paths.items())))
    assert response.status_code == 200, \
        f"Expected HTTP 200 for randomized nested ZIP, got {response.status_code}: {response.text}"
    assert parse_retained(response) == baseline + len(retained), \
        "retained_files did not increase by the exact number of newly retained files"

    for relative, expected in retained.items():
        path = os.path.join(SAFE_STORAGE, *relative.split("/"))
        assert os.path.isfile(path), f"Randomized archive member was not extracted: {relative}"
        with open(path, "rb") as handle:
            assert handle.read() == expected, f"Extracted contents differ for {relative}"
    for relative in elf_paths:
        path = os.path.join(SAFE_STORAGE, *relative.split("/"))
        assert not os.path.exists(path), f"ELF file with deceptive extension was retained: {relative}"


def test_extraction_uses_required_exclusive_lock():
    baseline_response = post(empty_zip())
    assert baseline_response.status_code == 200
    baseline = parse_retained(baseline_response)

    name = f"lock_probe_{uuid.uuid4().hex}.txt"
    content = os.urandom(64)
    payload = make_zip([(name, content)])
    os.makedirs(SAFE_STORAGE, exist_ok=True)

    with open(LOCK_PATH, "a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(post, payload, HEADERS, 15)
            time.sleep(1.0)
            assert not future.done(), \
                "Extraction completed while another process held extraction.lock exclusively"
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            response = future.result(timeout=10)

    assert response.status_code == 200, \
        f"Request failed after extraction.lock was released: {response.status_code} {response.text}"
    assert parse_retained(response) == baseline + 1, \
        "retained_files was incorrect after the lock-probe extraction"
    path = os.path.join(SAFE_STORAGE, name)
    assert os.path.isfile(path), "Lock-probe file was not extracted"
    with open(path, "rb") as handle:
        assert handle.read() == content, "Lock-probe file contents were corrupted"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
