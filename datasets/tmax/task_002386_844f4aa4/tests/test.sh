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
import glob
import os
import fcntl
import subprocess
import pytest
import requests

DUMP_PATH = "/app/dump.bin"
IMAGE_PATH = "/app/disk_warning.png"
CHUNK_SIZE = 1048576


def expected_parts():
    with open(DUMP_PATH, "rb") as f:
        data = f.read()
    header = data[:32]
    remainder = data[32:]
    chunks = [remainder[i:i + CHUNK_SIZE] for i in range(0, len(remainder), CHUNK_SIZE)]
    return header, chunks


def expected_volume():
    result = subprocess.run(
        ["tesseract", IMAGE_PATH, "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_header_extracted():
    header_path = "/home/user/header.bin"
    assert os.path.isfile(header_path), f"Header file {header_path} is missing."
    with open(header_path, "rb") as f:
        content = f.read()
    assert len(content) == 32, f"Expected 32 bytes in header, got {len(content)}."
    assert content == b"A" * 32, "Header content does not match the first 32 bytes of dump.bin."
    header, _ = expected_parts()
    assert content == header, "Header content does not match the source dump."


def test_chunks_created():
    chunks_dir = "/home/user/chunks"
    assert os.path.isdir(chunks_dir), f"Directory {chunks_dir} is missing."

    chunk_0 = os.path.join(chunks_dir, "chunk_0.bin")
    chunk_1 = os.path.join(chunks_dir, "chunk_1.bin")
    chunk_2 = os.path.join(chunks_dir, "chunk_2.bin")

    assert os.path.isfile(chunk_0), f"Chunk {chunk_0} is missing."
    assert os.path.getsize(chunk_0) == 1048576, "Chunk 0 size incorrect."

    assert os.path.isfile(chunk_1), f"Chunk {chunk_1} is missing."
    assert os.path.getsize(chunk_1) == 1048576, "Chunk 1 size incorrect."

    assert os.path.isfile(chunk_2), f"Chunk {chunk_2} is missing."
    assert os.path.getsize(chunk_2) == 500, "Chunk 2 size incorrect."

    _, chunks = expected_parts()
    expected_names = [f"chunk_{i}.bin" for i in range(len(chunks))]
    actual_names = sorted(
        os.path.basename(path)
        for path in glob.glob(os.path.join(chunks_dir, "chunk_*.bin"))
    )
    assert sorted(expected_names) == actual_names, (
        f"Expected chunk files {expected_names}, got {actual_names}."
    )

    for i, expected in enumerate(chunks):
        path = os.path.join(chunks_dir, f"chunk_{i}.bin")
        assert os.path.isfile(path), f"Chunk {path} is missing."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Chunk {i} does not match the corresponding dump bytes."


def test_symlinks_created():
    links_dir = "/home/user/active_links"
    assert os.path.isdir(links_dir), f"Directory {links_dir} is missing."

    for i in range(3):
        link_path = os.path.join(links_dir, f"link_{i}.bin")
        target_path = f"/home/user/chunks/chunk_{i}.bin"

        assert os.path.islink(link_path), f"{link_path} is not a symlink."
        assert os.readlink(link_path) == target_path, f"Symlink {link_path} points to {os.readlink(link_path)} instead of {target_path}."


def test_server_lock():
    lock_path = "/home/user/server.lock"
    assert os.path.isfile(lock_path), f"Lock file {lock_path} does not exist."

    with open(lock_path, "w") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(f, fcntl.LOCK_UN)
            pytest.fail("The server is not holding an exclusive lock on /home/user/server.lock.")
        except BlockingIOError:
            pass


def test_http_volume():
    url = "http://127.0.0.1:8888/volume"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."
    assert response.text.strip() == "CRITICAL_VOL_8841", f"Expected 'CRITICAL_VOL_8841', got '{response.text}'."
    ocr_text = expected_volume()
    assert response.text == ocr_text, (
        f"Volume response is not the exact stripped tesseract output: {response.text!r} != {ocr_text!r}."
    )


def test_http_chunks():
    base_url = "http://127.0.0.1:8888/chunk"

    try:
        resp_0 = requests.get(f"{base_url}/0", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server for chunk 0: {e}")

    assert resp_0.status_code == 200, f"Expected status code 200 for chunk 0, got {resp_0.status_code}."
    assert len(resp_0.content) == 1048576, f"Expected 1048576 bytes for chunk 0, got {len(resp_0.content)}."
    assert resp_0.content == b"B" * 1048576, "Content of chunk 0 via HTTP does not match expected."

    try:
        resp_2 = requests.get(f"{base_url}/2", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server for chunk 2: {e}")

    assert resp_2.status_code == 200, f"Expected status code 200 for chunk 2, got {resp_2.status_code}."
    assert len(resp_2.content) == 500, f"Expected 500 bytes for chunk 2, got {len(resp_2.content)}."
    assert resp_2.content == b"D" * 500, "Content of chunk 2 via HTTP does not match expected."

    _, chunks = expected_parts()
    for i, expected in enumerate(chunks):
        try:
            response = requests.get(f"{base_url}/{i}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the server for chunk {i}: {e}")
        assert response.status_code == 200, (
            f"Expected status code 200 for chunk {i}, got {response.status_code}."
        )
        assert response.content == expected, (
            f"Content of chunk {i} via HTTP does not match the corresponding dump bytes."
        )


def test_http_reads_corresponding_symlink():
    link_path = "/home/user/active_links/link_1.bin"
    original_target = "/home/user/chunks/chunk_1.bin"
    probe_path = "/home/user/chunks/.verifier_symlink_probe.bin"
    replacement_link = "/home/user/active_links/.verifier_link_1.tmp"
    probe = os.urandom(8193)

    with open(probe_path, "wb") as f:
        f.write(probe)

    response = None
    try:
        os.symlink(probe_path, replacement_link)
        os.replace(replacement_link, link_path)
        try:
            response = requests.get("http://127.0.0.1:8888/chunk/1", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect while testing symlink-backed serving: {e}")
    finally:
        try:
            if os.path.lexists(replacement_link):
                os.unlink(replacement_link)
            os.symlink(original_target, replacement_link)
            os.replace(replacement_link, link_path)
        finally:
            if os.path.exists(probe_path):
                os.unlink(probe_path)

    assert response.status_code == 200, (
        f"Expected status code 200 for retargeted chunk 1, got {response.status_code}."
    )
    assert response.content == probe, (
        "The chunk endpoint did not read chunk 1 through /home/user/active_links/link_1.bin."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
