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
import os
import json
import hashlib
import secrets
import subprocess
import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer backup_token_2024"}
MEDIA_DIR = "/app/media_assets"
VIDEO_PATH = os.path.join(MEDIA_DIR, "surveillance.mp4")


def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def build_expected_manifest():
    """Independently traverse the complete tree with branch-local cycle detection."""
    manifest = {}

    def visit(directory, rel_dir, ancestors):
        real_directory = os.path.realpath(directory)
        if real_directory in ancestors:
            return

        branch = ancestors | {real_directory}
        for entry in os.scandir(directory):
            rel_path = os.path.join(rel_dir, entry.name) if rel_dir else entry.name
            try:
                if entry.is_dir(follow_symlinks=True):
                    visit(entry.path, rel_path, branch)
                elif entry.is_file(follow_symlinks=True):
                    manifest[rel_path] = compute_sha256(entry.path)
            except (OSError, PermissionError):
                continue

    visit(MEDIA_DIR, "", set())
    return manifest


@pytest.fixture(scope="session", autouse=True)
def add_unpredictable_media_tree():
    """Add inputs unknown to the submitted server implementation."""
    token = secrets.token_hex(12)
    probe_root = os.path.join(MEDIA_DIR, f"recursive_probe_{token}")
    deep_dir = os.path.join(probe_root, "level_one", "level_two", "level_three")
    os.makedirs(deep_dir)

    deep_file = os.path.join(deep_dir, f"payload_{token}.bin")
    with open(deep_file, "wb") as f:
        f.write(secrets.token_bytes(8192) + token.encode())

    sibling_file = os.path.join(probe_root, f"sibling_{token}.txt")
    with open(sibling_file, "wb") as f:
        f.write(("dynamic recursive traversal " + token).encode())

    external_path = os.path.join("/tmp", f"manifest_external_{token}.bin")
    with open(external_path, "wb") as f:
        f.write(secrets.token_bytes(2048))
    os.symlink(external_path, os.path.join(deep_dir, f"external_{token}.link"))

    # Following this directory link would return to an ancestor and recurse forever.
    os.symlink(probe_root, os.path.join(deep_dir, f"cycle_{token}"))

    # Replace the video with a randomized, temporally changing test video. This
    # prevents a precomputed thumbnail for the image's original video from passing.
    color = secrets.token_hex(3)
    x_pos = secrets.randbelow(90)
    y_pos = secrets.randbelow(60)
    replacement = os.path.join(MEDIA_DIR, f".surveillance_{token}.mp4")
    video_filter = (
        "testsrc2=duration=7:size=160x120:rate=10,"
        f"drawbox=x={x_pos}:y={y_pos}:w=50:h=40:color=0x{color}:t=fill"
    )
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", video_filter,
         "-c:v", "libx264", "-pix_fmt", "yuv420p", replacement],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    os.replace(replacement, VIDEO_PATH)

    yield

    try:
        os.unlink(external_path)
    except OSError:
        pass


def test_auth_required():
    """Test that endpoints require authentication."""
    try:
        response = requests.get(f"{BASE_URL}/manifest", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {BASE_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without auth header, got {response.status_code}"


def test_thumbnail_auth_required():
    """Authentication must also protect /thumbnail for missing and invalid tokens."""
    for headers in ({}, {"Authorization": "Bearer wrong_token"}):
        try:
            response = requests.get(f"{BASE_URL}/thumbnail", headers=headers, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to server at {BASE_URL}: {e}")
        assert response.status_code == 401, (
            f"Expected 401 Unauthorized from /thumbnail, got {response.status_code}"
        )


def test_manifest_endpoint():
    """Test /manifest against every dynamically discovered file and checksum."""
    try:
        response = requests.get(f"{BASE_URL}/manifest", headers=AUTH_HEADER, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK for /manifest, got {response.status_code}"

    try:
        manifest = response.json()
    except json.JSONDecodeError:
        pytest.fail("Response body from /manifest is not valid JSON.")

    expected_files = {
        "logs/system.log": os.path.join(MEDIA_DIR, "logs/system.log"),
        "documents/data.txt": os.path.join(MEDIA_DIR, "documents/data.txt"),
        "documents/external_link.txt": os.path.join(MEDIA_DIR, "documents/external_link.txt"),
        "surveillance.mp4": os.path.join(MEDIA_DIR, "surveillance.mp4")
    }

    for rel_path, abs_path in expected_files.items():
        assert rel_path in manifest, f"Expected file '{rel_path}' missing from manifest."
        expected_hash = compute_sha256(abs_path)
        assert manifest[rel_path] == expected_hash, f"Hash mismatch for '{rel_path}'. Expected {expected_hash}, got {manifest[rel_path]}"

    expected_manifest = build_expected_manifest()
    assert manifest == expected_manifest, (
        "Manifest must contain exactly all recursively reachable regular files, "
        "including dynamic deep files and valid file symlinks while skipping cycles."
    )


def decode_png_to_rgb(png_data):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "pipe:0", "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        input=png_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Thumbnail is not a decodable PNG: {result.stderr.decode(errors='replace')}"
    return result.stdout


def reference_frame_at_five_seconds():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", "5.000", "-i", VIDEO_PATH,
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Could not derive reference frame: {result.stderr.decode(errors='replace')}"
    assert result.stdout, "Reference extraction at five seconds produced no frame."
    return result.stdout


def test_thumbnail_endpoint():
    """Test that /thumbnail is the actual frame at exactly five seconds."""
    try:
        response = requests.get(f"{BASE_URL}/thumbnail", headers=AUTH_HEADER, timeout=20)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK for /thumbnail, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "image/png" in content_type, f"Expected Content-Type 'image/png', got '{content_type}'"

    body = response.content
    assert len(body) > 8, "Response body is too short to be a valid PNG."

    png_magic = b'\x89PNG\r\n\x1a\n'
    assert body.startswith(png_magic), "Response body does not start with PNG magic bytes."

    actual_rgb = decode_png_to_rgb(body)
    expected_rgb = reference_frame_at_five_seconds()
    assert actual_rgb == expected_rgb, (
        "PNG pixels do not match surveillance.mp4's frame at exactly 00:00:05.000."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
