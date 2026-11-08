#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import urllib.request
import urllib.error
import pytest


def test_redis_running_and_configured():
    try:
        result = subprocess.run(
            ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"],
            capture_output=True, text=True, timeout=5
        )
        assert "PONG" in result.stdout, "Redis is not responding to PING on 127.0.0.1:6379"
    except FileNotFoundError:
        pytest.fail("redis-cli not found")


def test_nginx_data_endpoint():
    test_filename = "test_nginx_data_123.dat"
    test_filepath = f"/app/backup_data/{test_filename}"
    test_content = b"nginx_data_test_content"
    os.makedirs("/app/backup_data", exist_ok=True)
    with open(test_filepath, "wb") as f:
        f.write(test_content)
    try:
        req = urllib.request.Request(f"http://127.0.0.1/data/{test_filename}")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, "Nginx /data/ endpoint did not return 200 OK"
            assert response.read() == test_content, "Nginx /data/ endpoint returned incorrect content"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to fetch from Nginx /data/ endpoint: {e}")
    finally:
        if os.path.exists(test_filepath):
            os.remove(test_filepath)


def test_nginx_api_endpoint():
    try:
        req = urllib.request.Request("http://127.0.0.1/api/status")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, "Nginx /api/ endpoint did not return 200 OK"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to fetch from Nginx /api/ endpoint: {e}")


def generate_random_filename():
    length = random.randint(5, 15)
    chars = string.ascii_letters + string.digits + "_-"
    return "".join(random.choices(chars, k=length)) + ".dat"


def setup_test_files_and_redis(num_files=50):
    records = {}
    os.makedirs("/app/backup_data", exist_ok=True)
    for i in range(num_files):
        fname = generate_random_filename()
        payload = ("".join(random.choices(string.ascii_letters + string.digits, k=97)) + str(i)).encode()
        meta = f"metadata  {i} for {fname}  "
        with open(f"/app/backup_data/{fname}", "wb") as f:
            f.write(payload)
        proc = subprocess.run(
            ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "-x", "SET", f"file_meta:{fname}"],
            input=meta.encode("utf-16le"), capture_output=True
        )
        assert proc.returncode == 0, f"Failed to set redis key for {fname}"
        records[fname] = (meta, payload)
    return records


def expected_output(selected, records):
    out = bytearray()
    for fname in selected:
        meta, payload = records[fname]
        out.extend(b"---BEGIN_RECORD---\n")
        out.extend(f"FILE: {fname}\n".encode())
        out.extend(f"META: {meta}\n".encode())
        out.extend(b"PAYLOAD:\n")
        out.extend(payload)
        out.extend(b"\n---END_RECORD---\n")
    return bytes(out)


def test_archive_processor_fuzz_equivalence():
    agent_script = "/home/user/archive_processor.sh"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    records = setup_test_files_and_redis(50)
    filenames_pool = list(records)

    for i in range(20):
        selected_files = random.choices(filenames_pool, k=random.randint(1, 10))
        input_data = ("\n".join(selected_files) + "\n").encode()
        if os.path.exists("/tmp/backup_audit.log"):
            os.remove("/tmp/backup_audit.log")

        agent_proc = subprocess.run(
            ["bash", agent_script], input=input_data, capture_output=True, timeout=30
        )
        assert agent_proc.returncode == 0, f"Agent failed: {agent_proc.stderr!r}"
        assert agent_proc.stderr == b"", f"Agent emitted stderr: {agent_proc.stderr!r}"
        expected = expected_output(selected_files, records)
        assert agent_proc.stdout == expected, (
            f"Fuzz iteration {i} failed.\nInput: {input_data!r}\n"
            f"Expected stdout: {expected!r}\nGot stdout: {agent_proc.stdout!r}"
        )

        with open("/tmp/backup_audit.log", "rb") as f:
            audit = f.read()
        expected_lines = sorted(f"[ARCHIVED] {name}".encode() for name in selected_files)
        actual_lines = sorted(line for line in audit.splitlines() if line)
        assert actual_lines == expected_lines, (
            f"Fuzz iteration {i} failed on audit log. Expected {expected_lines!r}, got {actual_lines!r}"
        )


def test_concurrent_audit_logging():
    agent_script = "/home/user/archive_processor.sh"
    random.seed(99)
    records = setup_test_files_and_redis(12)
    names = list(records)
    if os.path.exists("/tmp/backup_audit.log"):
        os.remove("/tmp/backup_audit.log")
    procs = []
    submitted = []
    for i in range(12):
        selected = [names[i]] * 4
        submitted.extend(selected)
        procs.append(subprocess.Popen(["bash", agent_script], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        procs[-1].stdin.write(("\n".join(selected) + "\n").encode())
        procs[-1].stdin.close()
    for proc in procs:
        proc.wait(timeout=30)
        assert proc.returncode == 0
        assert proc.stderr.read() == b""
    with open("/tmp/backup_audit.log", "rb") as f:
        lines = f.read().splitlines()
    assert sorted(lines) == sorted(f"[ARCHIVED] {n}".encode() for n in submitted)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
