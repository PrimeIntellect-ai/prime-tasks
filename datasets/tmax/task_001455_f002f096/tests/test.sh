#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest
import requests
from PIL import Image, ImageChops, ImageStat

HOME = "/home/user"
FRAMES_DIR = os.path.join(HOME, "frames")
VIDEO = "/app/data/training_video.mp4"


def run_checked(command, timeout=60):
    result = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_artifacts():
    extract_script = os.path.join(HOME, "extract.sh")
    compute_script = os.path.join(HOME, "compute_embeddings.py")
    assert os.path.isfile(extract_script), f"File does not exist: {extract_script}"
    assert os.path.isfile(compute_script), f"File does not exist: {compute_script}"

    with open(extract_script, "r", errors="replace") as f:
        extract_source = f.read()
    assert "ffmpeg" in extract_source, "extract.sh does not invoke ffmpeg"

    shutil.rmtree(FRAMES_DIR, ignore_errors=True)
    run_checked(["bash", extract_script])
    run_checked(["python3", compute_script])

    reference_dir = tempfile.mkdtemp(prefix="reference_frames_")
    run_checked([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", VIDEO, "-vf", "fps=1", "-start_number", "0",
        os.path.join(reference_dir, "frame_%03d.jpg"),
    ])

    yield reference_dir
    shutil.rmtree(reference_dir, ignore_errors=True)


def image_distance(path_a, path_b):
    with Image.open(path_a) as a, Image.open(path_b) as b:
        assert a.size == b.size, f"Frame dimensions differ: {path_a} has {a.size}, expected {b.size}"
        a = a.convert("RGB").resize((160, 120), Image.Resampling.BILINEAR)
        b = b.convert("RGB").resize((160, 120), Image.Resampling.BILINEAR)
        means = ImageStat.Stat(ImageChops.difference(a, b)).mean
        return sum(means) / len(means)


def expected_histogram(path):
    with Image.open(path) as image:
        gray = image.convert("L")
        histogram = gray.histogram()
        total = gray.width * gray.height
    return [round(sum(histogram[i:i + 32]) / total, 4) for i in range(0, 256, 32)]


def load_embeddings():
    json_path = os.path.join(HOME, "embeddings.json")
    assert os.path.exists(json_path), f"File does not exist: {json_path}"
    with open(json_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, "embeddings.json is not valid JSON"


def test_frames_extracted(execute_artifacts):
    """Test extraction produced exactly the independently derived 1-FPS sequence."""
    assert os.path.exists(FRAMES_DIR), f"Directory does not exist: {FRAMES_DIR}"
    frames = sorted(glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg")))
    assert len(frames) > 0, "No frames were extracted to /home/user/frames/"

    references = sorted(glob.glob(os.path.join(execute_artifacts, "frame_*.jpg")))
    assert references, "Verifier failed to derive reference frames"
    expected_names = [f"frame_{i:03d}.jpg" for i in range(len(references))]
    assert [os.path.basename(p) for p in frames] == expected_names, (
        f"Expected exactly the contiguous 1-FPS frames {expected_names}, got "
        f"{[os.path.basename(p) for p in frames]}"
    )

    for index, frame in enumerate(frames):
        distances = [image_distance(frame, reference) for reference in references]
        assert distances[index] < 20.0, (
            f"{os.path.basename(frame)} does not resemble the video frame at second {index} "
            f"(distance {distances[index]:.2f})"
        )
        assert distances.index(min(distances)) == index, (
            f"{os.path.basename(frame)} is not the frame corresponding to second {index}"
        )


def test_embeddings_json():
    """Test structure and recompute every embedding from its extracted frame."""
    data = load_embeddings()
    assert len(data) > 0, "embeddings.json is empty"
    for k, v in data.items():
        assert isinstance(v, list), f"Embedding for frame {k} is not a list"
        assert len(v) == 8, f"Embedding for frame {k} does not have exactly 8 elements"
        assert all(isinstance(x, (int, float)) for x in v), f"Embedding for frame {k} contains non-numeric values"
        assert abs(sum(v) - 1.0) < 0.005, f"Embedding for frame {k} does not sum to 1.0 (sum is {sum(v)})"

    frames = sorted(glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg")))
    expected_keys = {str(i) for i in range(len(frames))}
    assert set(data.keys()) == expected_keys, (
        f"Embedding IDs must exactly match extracted frame IDs; expected {sorted(expected_keys)}, "
        f"got {sorted(data.keys())}"
    )
    for i, frame in enumerate(frames):
        expected = expected_histogram(frame)
        assert data[str(i)] == expected, (
            f"Embedding for frame {i} is incorrect: expected {expected}, got {data[str(i)]}"
        )


def request_json(method, url, **kwargs):
    try:
        response = requests.request(method, url, timeout=5, **kwargs)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to {url}: {e}"
    return response


def tokenize_expected(text):
    return re.sub(r"[^a-z0-9 ]", "", text.lower()).split()


def test_api_tokenize():
    """Test the fixed example and additional dynamically generated tokenization inputs."""
    url = "http://127.0.0.1:8888/api/tokenize"
    payload = {"text": "Hello, World! 123"}
    resp = request_json("POST", url, json=payload)
    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        assert False, "Response from /api/tokenize is not valid JSON"
    assert "tokens" in data, "Response JSON missing 'tokens' key"
    expected_tokens = ["hello", "world", "123"]
    assert data["tokens"] == expected_tokens, f"Expected tokens {expected_tokens}, got {data['tokens']}"

    nonce = uuid.uuid4().hex
    texts = [
        f"  MIXED-CaSe__{nonce}... Room  42! C++ ",
        f"punctuation@joins#{nonce}; but spaces remain",
    ]
    for text in texts:
        resp = request_json("POST", url, json={"text": text})
        assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}: {resp.text}"
        assert resp.json().get("tokens") == tokenize_expected(text), (
            f"Incorrect tokenization for {text!r}: got {resp.text}"
        )


def test_api_embedding():
    """Test the fixed ID, all stored IDs, consistency with JSON, and missing-ID behavior."""
    data_on_disk = load_embeddings()
    url = "http://127.0.0.1:8888/api/embedding?id=1"
    resp = request_json("GET", url)
    assert resp.status_code == 200, f"Expected HTTP 200 for id=1 (video is >3s long), got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        assert False, "Response from /api/embedding is not valid JSON"
    assert "id" in data, "Response JSON missing 'id' key"
    assert data["id"] == 1, f"Expected id to be 1, got {data['id']}"
    assert "embedding" in data, "Response JSON missing 'embedding' key"
    embedding = data["embedding"]
    assert isinstance(embedding, list), "Embedding must be a list"
    assert len(embedding) == 8, "Embedding must have exactly 8 elements"
    assert abs(sum(embedding) - 1.0) < 0.005, f"Embedding must sum to 1.0 (sum is {sum(embedding)})"
    assert embedding == data_on_disk["1"], "API embedding for id=1 is inconsistent with embeddings.json"

    for key, expected in data_on_disk.items():
        frame_id = int(key)
        resp = request_json("GET", f"http://127.0.0.1:8888/api/embedding?id={frame_id}")
        assert resp.status_code == 200, f"Expected HTTP 200 for id={frame_id}, got {resp.status_code}: {resp.text}"
        body = resp.json()
        assert body.get("id") == frame_id, f"Incorrect id in response for id={frame_id}: {body}"
        assert body.get("embedding") == expected, (
            f"API embedding for id={frame_id} is inconsistent with embeddings.json"
        )

    missing_id = max(map(int, data_on_disk.keys())) + 100003
    resp = request_json("GET", f"http://127.0.0.1:8888/api/embedding?id={missing_id}")
    assert resp.status_code == 404, (
        f"Expected HTTP 404 for missing id={missing_id}, got {resp.status_code}: {resp.text}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
