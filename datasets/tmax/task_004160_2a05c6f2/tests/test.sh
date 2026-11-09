#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import secrets
import subprocess
import tarfile
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ARCHIVE = "/app/docs_archive.tar.gz"
CLEAN_ROOT = Path("/home/user/clean_docs")
THIS_TEST = Path(__file__).resolve()


def extract_token():
    result = subprocess.run(
        ["tesseract", "/app/legacy_watermark.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=True,
    )
    match = re.search(r"AUTH_TOKEN\s*:\s*([A-Za-z0-9-]+)", result.stdout)
    assert match, f"Could not read AUTH_TOKEN from image: {result.stdout!r}"
    return match.group(1)


TOKEN = extract_token()
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
BAD_HEADERS = {"Authorization": f"Bearer wrong-{secrets.token_hex(8)}"}


def archive_expectations():
    expected = {}
    original_ssns = set()
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            name = Path(member.name)
            assert not name.is_absolute() and ".." not in name.parts
            source = archive.extractfile(member).read()
            original_ssns.update(re.findall(rb"(?<=SSN: )\d{3}-\d{2}-\d{4}", source))
            clean = re.sub(rb"(?<=SSN: )\d{3}-\d{2}-\d{4}", b"[REDACTED]", source)
            clean = clean.replace(b"STATUS: DRAFT", b"STATUS: ARCHIVED")
            expected[name.as_posix()] = clean
    assert expected, "Documentation archive contains no regular files"
    return expected, original_ssns


EXPECTED, ORIGINAL_SSNS = archive_expectations()


def doc_url(name):
    return f"{BASE_URL}/docs/{name}"


def test_clean_docs_directory_exists():
    assert os.path.isdir(CLEAN_ROOT), "Directory /home/user/clean_docs does not exist."


def test_all_archive_files_exist_on_disk_and_are_exactly_sanitized():
    actual = {
        path.relative_to(CLEAN_ROOT).as_posix()
        for path in CLEAN_ROOT.rglob("*")
        if path.is_file()
    }
    assert actual == set(EXPECTED), "clean_docs does not exactly contain all archive files"
    for name, expected in EXPECTED.items():
        path = CLEAN_ROOT / name
        assert path.is_file() and not path.is_symlink(), f"Missing regular sanitized file: {name}"
        assert path.read_bytes() == expected, f"On-disk sanitized content is incorrect for {name}"


def test_no_unredacted_extracted_plaintext_is_left_on_disk():
    excluded = {Path(ARCHIVE).resolve(), Path("/app/legacy_watermark.png").resolve(), THIS_TEST}
    offenders = []
    for root in (Path("/home/user"), Path("/app"), Path("/tmp")):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                resolved = path.resolve()
                if resolved in excluded or not path.is_file() or path.stat().st_size > 10_000_000:
                    continue
                data = path.read_bytes()
            except (OSError, PermissionError):
                continue
            if any(ssn in data for ssn in ORIGINAL_SSNS) or b"STATUS: DRAFT" in data:
                offenders.append(str(path))
    assert not offenders, f"Unredacted extracted content remains on disk: {offenders}"


def test_unauthorized_access():
    name = next(iter(EXPECTED))
    try:
        response = requests.get(doc_url(name), timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {BASE_URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_authentication_is_required_on_every_endpoint():
    name = next(iter(EXPECTED))
    for headers in ({}, BAD_HEADERS):
        response = requests.get(doc_url(name), headers=headers, timeout=5)
        assert response.status_code == 401

        before = (CLEAN_ROOT / name).read_bytes()
        response = requests.post(
            f"{BASE_URL}/append_note",
            headers=headers,
            json={"file": name, "note": "UNAUTHORIZED-" + secrets.token_hex(8)},
            timeout=5,
        )
        assert response.status_code == 401
        assert (CLEAN_ROOT / name).read_bytes() == before, "Unauthorized append changed the file"


def test_every_document_is_served_from_sanitized_disk_content():
    for name, expected in EXPECTED.items():
        response = requests.get(doc_url(name), headers=HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected 200 for {name}, got {response.status_code}"
        assert response.content == expected, f"Service did not return raw on-disk content for {name}"


def test_authorized_access_and_sanitization_server_migration():
    response = requests.get(doc_url("server_migration.txt"), headers=HEADERS, timeout=5)
    assert response.status_code == 200
    content = response.text
    assert "STATUS: ARCHIVED" in content
    assert "STATUS: DRAFT" not in content
    assert "Contact SSN: [REDACTED]" in content
    assert "123-45-6789" not in content


def test_authorized_access_and_sanitization_database_schema():
    response = requests.get(doc_url("database_schema.log"), headers=HEADERS, timeout=5)
    assert response.status_code == 200
    content = response.text
    assert "STATUS: ARCHIVED" in content
    assert "Backup operator SSN: [REDACTED]" in content
    assert "987-65-4321" not in content


def test_authorized_missing_document_returns_404():
    missing = "missing-" + secrets.token_hex(12) + ".txt"
    response = requests.get(doc_url(missing), headers=HEADERS, timeout=5)
    assert response.status_code == 404


def test_append_note_endpoint():
    name = "database_schema.log"
    response = requests.post(
        f"{BASE_URL}/append_note",
        headers=HEADERS,
        json={"file": name, "note": "Verified safe"},
        timeout=5,
    )
    assert response.status_code == 200, f"Expected 200 OK for POST /append_note, got {response.status_code}"
    get_response = requests.get(doc_url(name), headers=HEADERS, timeout=5)
    assert get_response.status_code == 200
    content_lines = get_response.text.strip().split("\n")
    assert "Verified safe" in content_lines[-1]
    assert (CLEAN_ROOT / name).read_bytes() == get_response.content


def test_concurrent_random_appends_are_complete_and_persisted():
    name = next(iter(EXPECTED))
    notes = [f"concurrent-{secrets.token_hex(12)}-" + (chr(65 + i) * 32768) for i in range(8)]

    def append(note):
        return requests.post(
            f"{BASE_URL}/append_note",
            headers=HEADERS,
            json={"file": name, "note": note},
            timeout=20,
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(notes)) as pool:
        responses = list(pool.map(append, notes))
    assert all(response.status_code == 200 for response in responses)

    disk = (CLEAN_ROOT / name).read_text()
    lines = disk.splitlines()
    for note in notes:
        assert lines.count(note) == 1, "A concurrent append was lost, duplicated, or interleaved"
    response = requests.get(doc_url(name), headers=HEADERS, timeout=10)
    assert response.status_code == 200
    assert response.content == (CLEAN_ROOT / name).read_bytes()


def implementation_text():
    candidates = set()
    for root in (Path("/app"), Path("/home/user"), Path("/tmp")):
        if root.exists():
            for suffix in ("*.py", "*.sh"):
                candidates.update(root.rglob(suffix))

    inline = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmd_parts = (proc / "cmdline").read_bytes().split(b"\0")
            cmd = b" ".join(cmd_parts).decode(errors="ignore")
            if "python" not in cmd and "uvicorn" not in cmd and "flask" not in cmd:
                continue
            inline.append(cmd)
            cwd = (proc / "cwd").resolve()
            for part in cmd_parts:
                text = part.decode(errors="ignore")
                possible = Path(text)
                if not possible.is_absolute():
                    possible = cwd / possible
                if possible.suffix in (".py", ".sh"):
                    candidates.add(possible)
        except (OSError, PermissionError):
            pass

    chunks = inline
    for path in candidates:
        try:
            if path.resolve() == THIS_TEST or not path.is_file() or path.stat().st_size > 2_000_000:
                continue
            chunks.append(path.read_text(errors="ignore"))
        except (OSError, PermissionError):
            pass
    return "\n".join(chunks)


def test_implementation_uses_atomic_publish_and_safe_append_primitives():
    source = implementation_text()
    assert source, "Could not locate the deployed service implementation"

    has_atomic_rename = bool(re.search(r"\b(?:os\.)?(?:replace|rename)\s*\(|\.replace\s*\(|\.rename\s*\(|\bmv\s+", source))
    has_temporary_write = bool(re.search(r"NamedTemporaryFile|mkstemp|mktemp|tempfile|temp_path|tmp_path|\.tmp\b|temporary", source, re.I))
    assert has_atomic_rename and has_temporary_write, "Sanitized files are not published using temporary files and atomic rename"

    has_lock = bool(re.search(r"fcntl\s*\.\s*(?:flock|lockf)\s*\(", source))
    has_atomic_append = bool(re.search(r"O_APPEND|open\s*\([^\n]{0,300},\s*['\"]a[b+]?['\"]", source))
    assert has_lock or has_atomic_append, "Append implementation has neither file locking nor atomic append semantics"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
