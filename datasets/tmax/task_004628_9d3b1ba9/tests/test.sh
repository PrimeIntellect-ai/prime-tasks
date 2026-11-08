#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import string
import subprocess
import tempfile

import pytest

VIDEO = "/app/tutorial.mp4"
METADATA = "/home/user/metadata.json"
IMAGES_DIR = "/home/user/docs/images"
EXPECTED_TIMESTAMPS = ["00:00:15", "00:01:23", "00:02:45"]


def run_checked(command, timeout=30):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def decode_rgb(path):
    result = run_checked([
        "ffmpeg", "-v", "error", "-xerror", "-i", path,
        "-map", "0:v:0", "-frames:v", "1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
    ])
    return result.stdout


def test_video_figure_extraction():
    with open(METADATA, "r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    timestamps = metadata.get("extract_frames")
    assert timestamps == EXPECTED_TIMESTAMPS, "The extraction metadata was changed or is invalid."

    expected_images = [f"figure_{i}.jpg" for i in range(1, len(timestamps) + 1)]

    with tempfile.TemporaryDirectory(prefix="frame_reference_") as reference_dir:
        for index, (timestamp, img) in enumerate(zip(timestamps, expected_images), start=1):
            img_path = os.path.join(IMAGES_DIR, img)
            assert os.path.isfile(img_path), f"Expected extracted frame {img_path} is missing."

            # Retain the original JPEG magic-number assertion.
            with open(img_path, "rb") as handle:
                header = handle.read(2)
                assert header == b"\xff\xd8", f"File {img_path} is not a valid JPEG image."

            probe = run_checked([
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=codec_name,width,height,pix_fmt",
                "-of", "json", img_path,
            ])
            streams = json.loads(probe.stdout.decode("utf-8")).get("streams", [])
            assert len(streams) == 1, f"{img_path} does not contain one decodable image stream."
            stream = streams[0]
            assert stream.get("codec_name") == "mjpeg", f"{img_path} is not a standard JPEG image."
            assert stream.get("width") == 320 and stream.get("height") == 240, \
                f"{img_path} has the wrong dimensions."

            reference_path = os.path.join(reference_dir, f"reference_{index}.jpg")
            run_checked([
                "ffmpeg", "-v", "error", "-ss", timestamp, "-i", VIDEO,
                "-map", "0:v:0", "-frames:v", "1", "-q:v", "2",
                "-pix_fmt", "yuvj420p", "-y", reference_path,
            ])

            submitted_rgb = decode_rgb(img_path)
            reference_rgb = decode_rgb(reference_path)
            expected_size = 320 * 240 * 3
            assert len(submitted_rgb) == expected_size, \
                f"{img_path} does not decode to a standard 24-bit RGB frame."
            assert len(reference_rgb) == expected_size

            differences = [abs(a - b) for a, b in zip(submitted_rgb, reference_rgb)]
            mean_error = sum(differences) / len(differences)
            max_error = max(differences)
            assert mean_error <= 3.0 and max_error <= 12, \
                f"{img_path} does not match the video frame at {timestamp}."


def find_detector():
    scripts = glob.glob("/home/user/docs/leak_detector.*")
    assert len(scripts) > 0, "No leak detector script found matching /home/user/docs/leak_detector.*"
    script_path = scripts[0]
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."
    return script_path


def detector_status(script_path, file_path):
    result = subprocess.run(
        [script_path, file_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
    return result.returncode


def test_leak_detector_adversarial_corpus():
    script_path = find_detector()

    evil_corpus_path = "/app/corpus/evil/"
    clean_corpus_path = "/app/corpus/clean/"
    evil_files = [os.path.join(evil_corpus_path, f) for f in os.listdir(evil_corpus_path)
                  if os.path.isfile(os.path.join(evil_corpus_path, f))]
    clean_files = [os.path.join(clean_corpus_path, f) for f in os.listdir(clean_corpus_path)
                   if os.path.isfile(os.path.join(clean_corpus_path, f))]

    assert len(evil_files) > 0, "Evil corpus is empty."
    assert len(clean_files) > 0, "Clean corpus is empty."

    bypassed_evil = []
    modified_clean = []
    for file_path in evil_files:
        if detector_status(script_path, file_path) != 1:
            bypassed_evil.append(os.path.basename(file_path))
    for file_path in clean_files:
        if detector_status(script_path, file_path) != 0:
            modified_clean.append(os.path.basename(file_path))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")
    if errors:
        pytest.fail("Adversarial corpus failed: " + " | ".join(errors))


def test_leak_detector_generated_hidden_cases():
    script_path = find_detector()
    alphabet = string.ascii_lowercase
    username = "".join(secrets.choice(alphabet) for _ in range(random.randint(5, 14)))
    password = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
    digit = secrets.choice("123456789")
    nonce = secrets.token_hex(10)

    evil_contents = [
        f"Random document {nonce}\nendpoint = api.internal.corp:8080/v{digit}\n",
        f"Random document {nonce}\nlogin test_user_{username}:{password}.\n",
        f"test_user_{username}:{password}\napi.internal.corp:8080/v{digit}\n",
        f"prefix text api.internal.corp:8080/v1, followed by unrelated {nonce}",
    ]
    clean_contents = [
        f"Public notes {nonce}: api.internal.corp:8080/v0",
        f"Public notes {nonce}: api.internal.corp:8080/v10",
        f"Public notes {nonce}: api.internal.corp:8080/v99",
        f"Public notes {nonce}: api.internal.corp:8081/v{digit}",
        f"Public notes {nonce}: API.INTERNAL.CORP:8080/v{digit}",
        f"test_user_{username}:{password}Z",  # 13 alphanumeric password characters
        f"test_user_{username}:{password[:-1]}",  # 11 characters
        f"test_user_{username.upper()}:{password}",
        f"Ordinary release documentation containing no secrets: {nonce}",
    ]

    cases = [(1, text) for text in evil_contents] + [(0, text) for text in clean_contents]
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix=f"docs_{nonce}_") as directory:
        for index, (expected, content) in enumerate(cases):
            path = os.path.join(directory, f"note_{secrets.token_hex(6)}_{index}.md")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(content)
            actual = detector_status(script_path, path)
            assert actual == expected, \
                f"Detector returned {actual} instead of {expected} for generated case {index}."

    no_arg = subprocess.run([script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    two_args = subprocess.run(
        [script_path, "/dev/null", "/dev/null"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
    )
    assert no_arg.returncode != 0, "Detector must require exactly one argument."
    assert two_args.returncode != 0, "Detector must reject more than one argument."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
