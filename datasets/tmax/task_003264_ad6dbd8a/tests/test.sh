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
import subprocess
import tarfile
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
INCOMING = "/app/incoming"
ARCHIVE = "/app/archive"


def get_video_frame_count(filepath):
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-count_packets", "-show_entries", "stream=nb_read_packets",
        "-of", "csv=p=0", filepath,
    ]
    try:
        output = subprocess.check_output(cmd, text=True).strip()
        return int(output)
    except Exception:
        return None


def get_json(path):
    url = BASE_URL + path
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail("Response was not valid JSON")


def make_wal(transactions=(), magic=b"MAGIC_WAL", bad_hash=False):
    preceding = magic + b"\n"
    for transaction in transactions:
        preceding += transaction + b"\n"
    digest = hashlib.md5(preceding).hexdigest()
    if bad_hash:
        digest = "0" * 32
    return preceding + f"END {digest}".encode()


def write_tar(path, entries):
    work = f"/tmp/wal-input-{uuid.uuid4().hex}"
    os.makedirs(work)
    try:
        with tarfile.open(path, "w:gz") as archive:
            for name, content in entries.items():
                source = os.path.join(work, name)
                os.makedirs(os.path.dirname(source), exist_ok=True)
                with open(source, "wb") as handle:
                    handle.write(content)
                archive.add(source, arcname=name)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def archive_files_on_disk():
    return sorted(
        name for name in os.listdir(ARCHIVE)
        if os.path.isfile(os.path.join(ARCHIVE, name)) and name.endswith(".wal")
    )


def assert_archive_state(expected_contents):
    data = get_json("/archived_wals")
    assert "files" in data, "Response JSON missing 'files' key"
    assert isinstance(data["files"], list), "'files' must be a list"
    expected_names = sorted(expected_contents)
    assert data["files"] == expected_names, (
        f"Expected sorted archive listing {expected_names}, got {data['files']}"
    )
    assert archive_files_on_disk() == expected_names, (
        "Endpoint result did not match the verified WAL files actually present on disk"
    )
    for name, expected in expected_contents.items():
        with open(os.path.join(ARCHIVE, name), "rb") as handle:
            assert handle.read() == expected, f"Archived contents of {name} were changed"


def wait_for_archive_state(expected_contents, timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            assert_archive_state(expected_contents)
            return
        except (AssertionError, OSError, requests.RequestException) as exc:
            last_error = exc
            time.sleep(0.25)
    if last_error:
        raise last_error
    assert_archive_state(expected_contents)


def test_video_info():
    data = get_json("/video_info")
    assert "total_frames" in data, "Response JSON missing 'total_frames' key"
    assert isinstance(data["total_frames"], int), "'total_frames' must be an integer"

    expected_frames = get_video_frame_count("/app/surveillance.mp4")
    if expected_frames is not None:
        assert data["total_frames"] == expected_frames, (
            f"Expected {expected_frames} frames, got {data['total_frames']}"
        )

    # Replace the video temporarily with a verifier-generated video so a fixed
    # response for the image's original 30-frame fixture cannot pass.
    original = "/tmp/original-surveillance.mp4"
    generated = "/tmp/generated-surveillance.mp4"
    shutil.copy2("/app/surveillance.mp4", original)
    try:
        subprocess.check_call([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=160x120:rate=11",
            "-frames:v", "7", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            generated,
        ])
        os.replace(generated, "/app/surveillance.mp4")
        dynamic_expected = get_video_frame_count("/app/surveillance.mp4")
        assert dynamic_expected == 7
        dynamic_data = get_json("/video_info")
        assert "total_frames" in dynamic_data
        assert isinstance(dynamic_data["total_frames"], int)
        assert dynamic_data["total_frames"] == dynamic_expected, (
            "The endpoint did not inspect the current surveillance video"
        )
    finally:
        os.replace(original, "/app/surveillance.mp4")


def test_wal_processing():
    os.makedirs(INCOMING, exist_ok=True)
    os.makedirs(ARCHIVE, exist_ok=True)
    for directory in (INCOMING, ARCHIVE):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    token = uuid.uuid4().hex[:12]

    # Preserve the original fixed valid/invalid assertions while including
    # verifier-generated names and several validation cases in the same archive.
    valid_content_base = b"MAGIC_WAL\ntxn 1\ntxn 2\n"
    valid_md5 = hashlib.md5(valid_content_base).hexdigest()
    valid_content = valid_content_base + f"END {valid_md5}".encode()
    invalid_content = b"MAGIC_WAL\ntxn 1\nEND badmd5"

    zero_name = f"{token}_empty.wal"
    alpha_name = f"{token}_alpha.wal"
    bad_magic_name = f"{token}_bad_magic.wal"
    bad_hash_name = f"{token}_bad_hash.wal"
    zero_content = make_wal(())
    alpha_content = make_wal((b"txn random A", b"txn random B"))

    first_tar = os.path.join(INCOMING, f"batch-{token}-one.tar.gz")
    write_tar(first_tar, {
        "valid_test.wal": valid_content,
        "invalid_test.wal": invalid_content,
        zero_name: zero_content,
        alpha_name: alpha_content,
        bad_magic_name: make_wal((b"txn x",), magic=b"NOT_MAGIC"),
        bad_hash_name: make_wal((b"txn y",), bad_hash=True),
        "ignored.txt": b"not a WAL",
    })

    expected = {
        "valid_test_verified.wal": valid_content,
        f"{token}_empty_verified.wal": zero_content,
        f"{token}_alpha_verified.wal": alpha_content,
    }
    wait_for_archive_state(expected)

    data = get_json("/archived_wals")
    files = data["files"]
    assert "valid_test_verified.wal" in files, "Valid WAL was not verified and archived"
    assert "invalid_test_verified.wal" not in files, "Invalid WAL was incorrectly archived"
    assert f"{token}_bad_magic_verified.wal" not in files
    assert f"{token}_bad_hash_verified.wal" not in files

    # Drop another archive only after the first one has completed. Write it
    # gradually at its final .tar.gz path to exercise complete-write handling
    # and continuous monitoring rather than startup-only processing.
    beta_name = f"{token}_beta.wal"
    gamma_name = f"{token}_gamma.wal"
    beta_content = make_wal((os.urandom(19).hex().encode(),))
    gamma_content = make_wal((b"txn later 1", b"txn later 2", b"txn later 3"))
    second_source = f"/tmp/batch-{token}-two.tar.gz"
    write_tar(second_source, {
        beta_name: beta_content,
        gamma_name: gamma_content,
        f"{token}_later_invalid.wal": make_wal((b"bad",), bad_hash=True),
    })
    second_target = os.path.join(INCOMING, f"batch-{token}-two.tar.gz")
    with open(second_source, "rb") as source, open(second_target, "wb") as target:
        payload = source.read()
        chunk_size = max(1, len(payload) // 7)
        for offset in range(0, len(payload), chunk_size):
            target.write(payload[offset:offset + chunk_size])
            target.flush()
            os.fsync(target.fileno())
            time.sleep(0.12)

    expected[f"{token}_beta_verified.wal"] = beta_content
    expected[f"{token}_gamma_verified.wal"] = gamma_content
    wait_for_archive_state(expected)
    assert f"{token}_later_invalid_verified.wal" not in get_json("/archived_wals")["files"]

    # A corrupt gzip archive must not create output or stop the watcher/service.
    corrupt_path = os.path.join(INCOMING, f"batch-{token}-corrupt.tar.gz")
    with open(corrupt_path, "wb") as handle:
        handle.write(b"not a gzip or tar archive\n" + os.urandom(64))
    time.sleep(2)
    assert_archive_state(expected)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
