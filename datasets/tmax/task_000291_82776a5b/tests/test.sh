#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/scan_patches.py"
VIDEO_PATH = "/app/salt_video.mp4"
CLEAN_CORPUS = "/app/corpus/clean/"
EVIL_CORPUS = "/app/corpus/evil/"
CLEAN_OUT = "/tmp/clean_results.json"
EVIL_OUT = "/tmp/evil_results.json"


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    for output in (CLEAN_OUT, EVIL_OUT):
        if os.path.exists(output):
            os.remove(output)

    res_clean = subprocess.run(
        ["python3", SCRIPT_PATH, "--corpus", CLEAN_CORPUS, "--video", VIDEO_PATH, "--out", CLEAN_OUT],
        capture_output=True, text=True, timeout=120
    )
    assert res_clean.returncode == 0, f"Script failed on clean corpus: {res_clean.stderr}"

    res_evil = subprocess.run(
        ["python3", SCRIPT_PATH, "--corpus", EVIL_CORPUS, "--video", VIDEO_PATH, "--out", EVIL_OUT],
        capture_output=True, text=True, timeout=120
    )
    assert res_evil.returncode == 0, f"Script failed on evil corpus: {res_evil.stderr}"


def test_clean_corpus_results():
    assert os.path.isfile(CLEAN_OUT), f"Output JSON for clean corpus not found at {CLEAN_OUT}"

    with open(CLEAN_OUT, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Clean results output is not valid JSON")

    expected_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".patch")]

    modified_clean = []
    missing_clean = []

    for fname in expected_files:
        if fname not in results:
            missing_clean.append(fname)
        elif results[fname] != "clean":
            modified_clean.append(fname)

    errors = []
    if missing_clean:
        errors.append(f"{len(missing_clean)} clean files missing from output: {missing_clean}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(expected_files)} clean modified/flagged as evil: {modified_clean}")

    if errors:
        pytest.fail("; ".join(errors))


def test_evil_corpus_results():
    assert os.path.isfile(EVIL_OUT), f"Output JSON for evil corpus not found at {EVIL_OUT}"

    with open(EVIL_OUT, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Evil results output is not valid JSON")

    expected_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith(".patch")]

    bypassed_evil = []
    missing_evil = []

    for fname in expected_files:
        if fname not in results:
            missing_evil.append(fname)
        elif results[fname] != "evil":
            bypassed_evil.append(fname)

    errors = []
    if missing_evil:
        errors.append(f"{len(missing_evil)} evil files missing from output: {missing_evil}")
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(expected_files)} evil bypassed/flagged as clean: {bypassed_evil}")

    if errors:
        pytest.fail("; ".join(errors))


def make_video(directory, salt):
    frames = os.path.join(directory, "frames")
    os.mkdir(frames)
    for index, char in enumerate(salt):
        subprocess.run([
            "convert", "-size", "200x200", "xc:white",
            "-font", "DejaVu-Sans", "-pointsize", "100",
            "-fill", "black", "-gravity", "center",
            "-draw", f"text 0,0 '{char}'",
            os.path.join(frames, f"{index}.png")
        ], check=True, capture_output=True, text=True)

    video = os.path.join(directory, "challenge.mp4")
    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y", "-framerate", "1",
        "-i", os.path.join(frames, "%d.png"), "-c:v", "libx264",
        "-r", "1", "-pix_fmt", "yuv420p", video
    ], check=True, capture_output=True, text=True)
    return video


def patch_text(routes):
    lines = ["--- a/routes.conf", "+++ b/routes.conf", "@@ -0,0 +1 @@"]
    if routes:
        for url, checksum in routes:
            lines.append(f"++ROUTE {url} CHECKSUM={checksum}")
    else:
        lines.append("+# routing documentation only")
    return "\n".join(lines) + "\n"


def test_unseen_randomized_corpus_and_video():
    rng = random.SystemRandom()
    alphabet = "3479AHKRTX"
    salt = "".join(rng.choice(alphabet) for _ in range(4))
    if salt == "X7K9":
        salt = "A7K9"

    nonce = uuid.uuid4().hex

    def digest(url):
        return hashlib.md5((url + salt).encode()).hexdigest()

    valid_url = f"/service/{nonce}/users?id={rng.randrange(10000, 99999)}&mode=view"
    valid_url_two = f"/service/{nonce}/search?q=alpha&limit={rng.randrange(2, 50)}"
    invalid_url = f"/service/{nonce}/account?id={rng.randrange(10000, 99999)}"
    nop_url = f"/service/{nonce}/exec?cmd=%90%90%90%31%c0&job={rng.randrange(100, 999)}"
    mixed_good = f"/service/{nonce}/status?item={rng.randrange(100, 999)}"
    mixed_bad = f"/service/{nonce}/status?item={rng.randrange(1000, 9999)}"

    specifications = [
        ([(valid_url, digest(valid_url))], "clean"),
        ([(valid_url, digest(valid_url)), (valid_url_two, digest(valid_url_two))], "clean"),
        ([], "clean"),
        ([(invalid_url, "0" * 32)], "evil"),
        ([(nop_url, digest(nop_url))], "evil"),
        ([(mixed_good, digest(mixed_good)), (mixed_bad, "f" * 32)], "evil"),
    ]
    rng.shuffle(specifications)

    with tempfile.TemporaryDirectory(prefix="scan-verifier-") as work:
        corpus = os.path.join(work, "incoming")
        os.mkdir(corpus)
        video = make_video(work, salt)
        output = os.path.join(work, "results.json")

        expected = {}
        for routes, classification in specifications:
            filename = f"{uuid.uuid4().hex}.patch"
            expected[filename] = classification
            with open(os.path.join(corpus, filename), "w") as handle:
                handle.write(patch_text(routes))

        with open(os.path.join(corpus, f"{uuid.uuid4().hex}.txt"), "w") as handle:
            handle.write("not a patch\n")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--corpus", corpus, "--video", video, "--out", output],
            capture_output=True, text=True, timeout=120
        )
        assert result.returncode == 0, f"Script failed on unseen corpus: {result.stderr}"
        assert os.path.isfile(output), "Output JSON for unseen corpus was not created"

        try:
            with open(output, "r") as handle:
                actual = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("Unseen corpus output is not valid JSON")

        assert actual == expected, f"Incorrect classifications for unseen corpus: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
