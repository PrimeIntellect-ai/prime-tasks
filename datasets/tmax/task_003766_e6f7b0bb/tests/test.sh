#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import random
import secrets
import shutil
import struct
import subprocess
import tarfile
import time
import urllib.error
import urllib.request

import pytest

BINARY = "/home/user/process_docs"
OUT_DIR = "/tmp/docs_out"


def run_processor(archive, timeout=30):
    return subprocess.run(
        [BINARY, archive], capture_output=True, text=True, timeout=timeout
    )


def redis_cli(*args):
    result = subprocess.run(
        ["redis-cli", "--raw", *map(str, args)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"redis-cli failed: {result.stderr}"
    return result.stdout.rstrip("\n")


def api_timestamp(doc_id):
    url = f"http://127.0.0.1:8080/api/doc/{doc_id}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            assert response.getcode() == 200, f"Expected HTTP 200, got {response.getcode()}"
            raw = response.read().decode("utf-8").strip()
    except urllib.error.URLError as exc:
        pytest.fail(
            f"Failed to connect through Nginx at {url}. Is the proxy configured and running? {exc}"
        )
    assert raw and raw != "null", "API returned an empty/null response"
    try:
        body = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"API returned invalid JSON: {raw!r}: {exc}")
    assert isinstance(body, dict), f"Expected a JSON object, got {body!r}"
    return body.get("timestamp")


def reset_output():
    shutil.rmtree(OUT_DIR, ignore_errors=True)
    os.makedirs(OUT_DIR, exist_ok=True)


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def test_compiled_binary_exists():
    assert os.path.isfile(BINARY), "Compiled binary /home/user/process_docs is missing."
    assert os.access(BINARY, os.X_OK), "/home/user/process_docs is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process_docs must be a compiled executable."

    metadata = subprocess.run(
        ["go", "version", "-m", BINARY], capture_output=True, text=True
    )
    assert metadata.returncode == 0 and "go1" in metadata.stdout, (
        "process_docs does not appear to be a compiled Go binary."
    )

    with open(BINARY, "rb") as submitted, open("/app/bin/process_docs_ref", "rb") as reference:
        assert submitted.read() != reference.read(), "Submitted binary is identical to the reference binary."


def test_tar_slip_prevention():
    reset_output()
    if os.path.exists("/tmp/evil.txt"):
        os.remove("/tmp/evil.txt")

    result = run_processor("/app/data/docs_upload.tar")
    assert result.returncode == 0, f"process_docs failed on docs_upload.tar:\n{result.stderr}"
    assert not os.path.exists("/tmp/evil.txt"), (
        "Tar slip vulnerability not fixed: /tmp/evil.txt was extracted outside the target directory."
    )
    with open(os.path.join(OUT_DIR, "valid.md"), "rb") as f:
        assert f.read() == b"valid", "The valid archive member was not extracted correctly."


def test_api_and_wal_parsing():
    assert api_timestamp(101) == "1620000000", (
        "The API did not return the timestamp encoded in docs_upload.tar's WAL."
    )


def test_randomized_extraction_security_and_wal_accuracy():
    token = secrets.token_hex(12)
    archive = f"/tmp/docs_dynamic_{token}.tar"
    escape1 = f"/tmp/verifier_escape_{token}"
    escape2 = f"/tmp/verifier_escape2_{token}"
    for path in (escape1, escape2):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    expected_files = {}
    for i in range(18):
        name = f"section_{token}/part_{i}_{secrets.token_hex(3)}.md"
        expected_files[name] = secrets.token_bytes(random.randint(32, 512))

    active = []
    used_ids = set()
    while len(active) < 3:
        doc_id = random.randint(200000000, 3900000000)
        if doc_id not in used_ids:
            used_ids.add(doc_id)
            active.append((doc_id, random.randint(1000000000, 4000000000)))
    inactive_id = random.randint(200000000, 3900000000)
    while inactive_id in used_ids:
        inactive_id = random.randint(200000000, 3900000000)
    inactive_marker = f"unchanged-{token}"

    for doc_id, _ in active:
        redis_cli("SET", f"doc:{doc_id}", f"wrong-{token}")
    redis_cli("SET", f"doc:{inactive_id}", inactive_marker)

    wal = b"".join(struct.pack("<IIB", doc_id, timestamp, 1) for doc_id, timestamp in active)
    wal += struct.pack("<IIB", inactive_id, random.randint(1000000000, 4000000000), 0)

    with tarfile.open(archive, "w") as tar:
        for name, data in expected_files.items():
            add_bytes(tar, name, data)
        add_bytes(tar, "history.wal", wal)
        add_bytes(tar, f"../verifier_escape_{token}", b"escape-one")
        add_bytes(tar, f"nested/../../verifier_escape2_{token}", b"escape-two")

    reset_output()
    result = run_processor(archive)
    assert result.returncode == 0, f"process_docs failed on generated archive:\n{result.stderr}"

    assert not os.path.lexists(escape1), f"Traversal member escaped extraction root to {escape1}"
    assert not os.path.lexists(escape2), f"Traversal member escaped extraction root to {escape2}"

    for name, expected in expected_files.items():
        target = os.path.join(OUT_DIR, name)
        assert os.path.isfile(target), f"Archive member was not extracted: {name}"
        with open(target, "rb") as f:
            assert f.read() == expected, f"Extracted content is incorrect for {name}"

    for doc_id, timestamp in active:
        assert redis_cli("GET", f"doc:{doc_id}") == str(timestamp), (
            f"Incorrect Redis value for WAL document {doc_id}"
        )
    assert redis_cli("GET", f"doc:{inactive_id}") == inactive_marker, (
        "A WAL record whose status flag was not 1 incorrectly modified Redis."
    )

    checked_id, checked_timestamp = active[0]
    assert api_timestamp(checked_id) == str(checked_timestamp), (
        "Nginx -> Flask -> Redis did not return the generated WAL timestamp."
    )


def test_performance_speedup_and_large_archive_output():
    reset_output()
    start_ref = time.perf_counter()
    ref_result = subprocess.run(
        ["/app/bin/process_docs_ref", "/app/data/large_docs.tar"],
        capture_output=True,
        timeout=30,
    )
    time_ref = time.perf_counter() - start_ref
    assert ref_result.returncode == 0, "Reference binary failed to run."

    reset_output()
    start_agent = time.perf_counter()
    agent_result = subprocess.run(
        [BINARY, "/app/data/large_docs.tar"], capture_output=True, timeout=30
    )
    time_agent = time.perf_counter() - start_agent
    assert agent_result.returncode == 0, (
        "Agent binary failed on large_docs.tar:\n"
        + agent_result.stderr.decode("utf-8", errors="ignore")
    )

    for i in range(200):
        target = os.path.join(OUT_DIR, f"doc_{i}.md")
        assert os.path.isfile(target), f"Large archive member doc_{i}.md was not extracted."
        with open(target, "rb") as f:
            assert f.read() == f"doc {i}".encode(), f"Incorrect content in doc_{i}.md"

    speedup = time_ref / max(time_agent, 1e-9)
    assert speedup >= 3.0, (
        f"Performance metric failed: Target speedup >= 3.0, but achieved {speedup:.2f}x. "
        f"(Ref time: {time_ref:.2f}s, Agent time: {time_agent:.2f}s). "
        "Ensure your Go code uses goroutines to process files concurrently."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
