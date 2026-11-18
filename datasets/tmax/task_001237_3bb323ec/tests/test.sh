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
import io
import os
import secrets
import subprocess
import tarfile
import uuid
import zipfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"


def test_status_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/status", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to GET /status: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /status is not valid JSON: {response.text}")

    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def _write_valid_tar(path, member_name, contents):
    with tarfile.open(path, "w:gz") as tf:
        info = tarfile.TarInfo(member_name)
        info.size = len(contents)
        tf.addfile(info, io.BytesIO(contents))


def test_archives_clean_endpoint():
    try:
        response = requests.post(f"{BASE_URL}/archives/clean", timeout=15)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to POST /archives/clean: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /archives/clean is not valid JSON: {response.text}")

    assert isinstance(data, list), "Expected a JSON array of filenames"
    expected_files = {"backup_1.tar.gz", "metrics_1.tar.gz"}
    assert set(data) == expected_files, f"Expected {expected_files}, got {set(data)}"

    archives_dir = "/home/user/archives"
    assert os.path.exists(os.path.join(archives_dir, "backup_1.tar.gz")), "backup_1.tar.gz should not be deleted"
    assert os.path.exists(os.path.join(archives_dir, "metrics_1.tar.gz")), "metrics_1.tar.gz should not be deleted"
    assert os.path.exists(os.path.join(archives_dir, "random_1.tar.gz")), "random_1.tar.gz should not be deleted"
    assert not os.path.exists(os.path.join(archives_dir, "backup_2.tar.gz")), "Corrupt archive backup_2.tar.gz was not deleted"
    assert not os.path.exists(os.path.join(archives_dir, "old_data.tar.gz")), "Corrupt archive old_data.tar.gz was not deleted"

    # Exercise fresh names and a fresh configuration so fixed responses and
    # deletion of only the setup fixture cannot pass.
    token = uuid.uuid4().hex
    wanted_prefix = f"live_{token}_"
    wanted_name = f"{wanted_prefix}good.tar.gz"
    other_name = f"other_{token}_good.tar.gz"
    corrupt_name = f"{wanted_prefix}broken.tar.gz"
    corrupt_other_name = f"unrelated_{token}_broken.tar.gz"

    wanted_path = os.path.join(archives_dir, wanted_name)
    other_path = os.path.join(archives_dir, other_name)
    corrupt_path = os.path.join(archives_dir, corrupt_name)
    corrupt_other_path = os.path.join(archives_dir, corrupt_other_name)

    _write_valid_tar(wanted_path, "wanted.txt", secrets.token_bytes(61))
    _write_valid_tar(other_path, "other.txt", secrets.token_bytes(73))

    temporary_valid = os.path.join(archives_dir, f"temporary_{token}.tar.gz")
    _write_valid_tar(temporary_valid, "truncated.txt", secrets.token_bytes(127))
    with open(temporary_valid, "rb") as f:
        valid_bytes = f.read()
    os.replace(temporary_valid, corrupt_path)
    with open(corrupt_path, "wb") as f:
        f.write(valid_bytes[: max(1, len(valid_bytes) // 2)])
    with open(corrupt_other_path, "wb") as f:
        f.write(secrets.token_bytes(97))

    with open("/home/user/config.yaml", "w", encoding="utf-8") as f:
        f.write(f'prefixes:\n  - "{wanted_prefix}"\n')

    response = requests.post(f"{BASE_URL}/archives/clean", timeout=15)
    assert response.status_code == 200, f"Expected 200 OK on dynamic fixture, got {response.status_code}"
    try:
        dynamic_data = response.json()
    except ValueError:
        pytest.fail(f"Dynamic /archives/clean response is not valid JSON: {response.text}")

    assert isinstance(dynamic_data, list), "Expected a JSON array for dynamic fixture"
    assert set(dynamic_data) == {wanted_name}, f"Expected only {wanted_name}, got {dynamic_data}"
    assert os.path.exists(wanted_path), "Matching valid archive was deleted"
    assert os.path.exists(other_path), "Non-matching valid archive was deleted"
    assert not os.path.exists(corrupt_path), "Dynamically named matching corrupt archive was not deleted"
    assert not os.path.exists(corrupt_other_path), "Dynamically named non-matching corrupt archive was not deleted"


def test_logs_errors_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/logs/errors", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to GET /logs/errors: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.text.strip() == "2", f"Expected count '2', got '{response.text}'"

    # Replace the WAL with a randomized number of IDs, a duplicate, an INFO
    # entry containing an ID, and an ERROR without an ID.
    unique_count = 3 + secrets.randbelow(3)
    error_ids = [str(uuid.uuid4()) for _ in range(unique_count)]
    ignored_info_id = str(uuid.uuid4())
    lines = [
        "2026-01-01 00:00:00 INFO Starting dynamic test",
        f"  ErrID: {ignored_info_id}",
    ]
    for index, err_id in enumerate(error_ids):
        lines.extend([
            f"2026-01-01 00:{index + 1:02d}:00 ERROR Dynamic failure {index}",
            "  diagnostic continuation",
            f"  ErrID: {err_id}",
        ])
    lines.extend([
        "2026-01-01 00:20:00 ERROR Duplicate failure",
        f"  ErrID: {error_ids[0]}",
        "2026-01-01 00:21:00 ERROR Entry with no identifier",
        "  diagnostic continuation only",
        "2026-01-01 00:22:00 INFO Finished",
    ])
    with open("/home/user/storage.wal", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    response = requests.get(f"{BASE_URL}/logs/errors", timeout=5)
    assert response.status_code == 200, f"Expected 200 OK on dynamic WAL, got {response.status_code}"
    assert response.text.strip() == str(unique_count), (
        f"Expected dynamically derived count {unique_count}, got {response.text!r}"
    )


def _decode_rgb(command):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    return result.stdout


def test_video_extract_endpoint():
    try:
        response = requests.post(f"{BASE_URL}/video/extract", timeout=30)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to POST /video/extract: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    returned_hash = response.text.strip()

    zip_path = "/home/user/frame.zip"
    frame_path = "/home/user/frame.jpg"
    assert os.path.exists(zip_path), f"{zip_path} was not created"
    assert os.path.isfile(frame_path), f"{frame_path} was not created"

    sha256 = hashlib.sha256()
    with open(zip_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    actual_hash = sha256.hexdigest()

    assert returned_hash == actual_hash, f"Returned hash {returned_hash} does not match actual hash {actual_hash}"

    with zipfile.ZipFile(zip_path, "r") as zf:
        namelist = zf.namelist()
        assert len(namelist) == 1, f"Expected exactly 1 file in zip, found {len(namelist)}: {namelist}"
        assert namelist[0] == "frame.jpg", f"Expected file 'frame.jpg' in zip, found '{namelist[0]}'"
        archived_frame = zf.read("frame.jpg")

    with open(frame_path, "rb") as f:
        saved_frame = f.read()
    assert archived_frame == saved_frame, "The frame in frame.zip differs from /home/user/frame.jpg"

    # Decode both the submitted JPEG and an independently extracted source
    # frame. This rejects arbitrary data or an unrelated image named frame.jpg.
    submitted_rgb = _decode_rgb([
        "ffmpeg", "-v", "error", "-i", frame_path,
        "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1",
    ])
    reference_rgb = _decode_rgb([
        "ffmpeg", "-v", "error", "-ss", "5.000", "-i", "/app/storage_scan.mp4",
        "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1",
    ])

    expected_size = 320 * 240 * 3
    assert len(submitted_rgb) == expected_size, "frame.jpg is not a decodable 320x240 frame"
    assert len(reference_rgb) == expected_size, "Could not derive the reference frame from the source video"
    mean_absolute_error = sum(abs(a - b) for a, b in zip(submitted_rgb, reference_rgb)) / expected_size
    assert mean_absolute_error < 12.0, (
        f"frame.jpg does not match the source video at 00:00:05 (MAE={mean_absolute_error:.3f})"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
