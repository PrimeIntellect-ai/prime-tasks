#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import random
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

AGENT_SCRIPT = "/home/user/process_artifact.py"


def generate_fuzz_content(size):
    chars = string.ascii_letters + string.digits
    content = "".join(random.choices(chars, k=size))
    num_insertions = random.randint(1, 10)
    for _ in range(num_insertions):
        pos = random.randint(0, len(content))
        content = content[:pos] + "__MACRO_REPO_HOST__" + content[pos:]
    return content.encode("utf-8")


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."


def test_fuzz_equivalence():
    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(20):
            size = random.randint(10000, 100000)
            content = generate_fuzz_content(size)
            expected = content.replace(
                b"__MACRO_REPO_HOST__", b"artifact-repo.internal.srv"
            )

            agent_path = os.path.join(tmpdir, f"agent_{i}.gz")
            with gzip.open(agent_path, "wb") as f:
                f.write(content)

            res = subprocess.run(
                ["python3", AGENT_SCRIPT, agent_path],
                capture_output=True,
                text=True,
            )
            assert res.returncode == 0, (
                f"Agent script failed on input {i}. Stderr: {res.stderr}"
            )

            with gzip.open(agent_path, "rb") as f:
                agent_content = f.read()

            assert agent_content == expected, (
                f"Mismatch on fuzz input {i}. Agent output was incorrect."
            )


def test_atomic_replacement_in_same_directory():
    with tempfile.TemporaryDirectory() as tmpdir:
        path = os.path.join(tmpdir, "atomic.gz")
        content = (b"prefix __MACRO_REPO_HOST__ suffix\n" * 100000)
        expected = content.replace(
            b"__MACRO_REPO_HOST__", b"artifact-repo.internal.srv"
        )
        with gzip.open(path, "wb") as f:
            f.write(content)

        original_inode = os.stat(path).st_ino
        env = os.environ.copy()
        # A processor using tempfile's default directory instead of the target
        # directory will attempt a cross-filesystem replacement on this image.
        env["TMPDIR"] = "/dev/shm"
        res = subprocess.run(
            ["python3", AGENT_SCRIPT, path],
            capture_output=True,
            text=True,
            env=env,
        )
        assert res.returncode == 0, f"Atomic processing failed: {res.stderr}"
        assert os.stat(path).st_ino != original_inode, (
            "The original file was modified in place instead of atomically replaced."
        )
        with gzip.open(path, "rb") as f:
            assert f.read() == expected


def test_start_worker_configured():
    script_path = "/app/start_worker.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()
    assert "PROCESSOR_SCRIPT=/home/user/process_artifact.py" in content, (
        f"{script_path} does not export PROCESSOR_SCRIPT correctly."
    )


def test_services_running():
    res = subprocess.run(["pgrep", "-f", "redis-server"], capture_output=True)
    assert res.returncode == 0, "Redis server is not running."

    res = subprocess.run(["pgrep", "-f", "upload_server.py"], capture_output=True)
    assert res.returncode == 0, "Flask upload_server.py is not running."

    res = subprocess.run(["pgrep", "-f", "worker.py"], capture_output=True)
    assert res.returncode == 0, "Worker daemon is not running."


def test_end_to_end_flow():
    content = b"Some random text with __MACRO_REPO_HOST__ inside."
    expected_content = b"Some random text with artifact-repo.internal.srv inside."

    with tempfile.NamedTemporaryFile(suffix=".gz", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        with gzip.open(tmp_path, "wb") as f:
            f.write(content)

        filename = os.path.basename(tmp_path)
        pattern = os.path.join("/home/user/uploads", "*_" + filename)
        existing = set(glob.glob(pattern))

        with open(tmp_path, "rb") as f:
            data = f.read()

        boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
        body = (
            f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
            "Content-Type: application/gzip\r\n\r\n"
        ).encode("utf-8") + data + f"\r\n--{boundary}--\r\n".encode("utf-8")

        req = urllib.request.Request("http://127.0.0.1:5000/upload", data=body)
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")

        try:
            with urllib.request.urlopen(req) as response:
                assert response.status == 200
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to upload file to Flask service: {e}")

        success = False
        for _ in range(50):
            candidates = set(glob.glob(pattern)) - existing
            for target_file in candidates:
                try:
                    with gzip.open(target_file, "rb") as f:
                        processed = f.read()
                    if processed == expected_content:
                        success = True
                        break
                except Exception:
                    pass
            if success:
                break
            time.sleep(0.1)

        assert success, (
            "End-to-end flow failed: the UUID-prefixed upload was not processed "
            "correctly within the timeout."
        )
    finally:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
