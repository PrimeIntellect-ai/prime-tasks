#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import random
import re
import secrets
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

import pytest


def decoded_rgb(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-map", "0:v:0", "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Not a decodable image: {path}: {result.stderr.decode(errors='replace')}"
    expected_size = 128 * 128 * 3
    assert len(result.stdout) == expected_size, (
        f"Frame {path} does not decode to the source video's 128x128 dimensions"
    )
    return result.stdout


def test_video_chunking():
    archive_dir = "/home/user/archive"
    assert os.path.isdir(archive_dir), f"Archive directory missing: {archive_dir}"

    expected_chunks = ["chunk_0.tar.gz", "chunk_1.tar.gz", "chunk_2.tar.gz"]
    found_chunks = sorted(os.path.basename(p) for p in glob.glob(os.path.join(archive_dir, "chunk_*.tar.gz")))
    assert found_chunks == expected_chunks, f"Expected exactly {expected_chunks}, found {found_chunks}"

    with tempfile.TemporaryDirectory() as reference_dir, tempfile.TemporaryDirectory() as submitted_dir:
        reference_pattern = os.path.join(reference_dir, "%03d.png")
        generated = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "/app/dataset_video.mp4", "-vf", "fps=1",
             "-start_number", "1", reference_pattern],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert generated.returncode == 0, generated.stderr.decode(errors="replace")
        reference_files = sorted(glob.glob(os.path.join(reference_dir, "*.png")))
        assert len(reference_files) == 15, f"Expected 15 one-FPS source frames, got {len(reference_files)}"
        reference_rgb = {i + 1: decoded_rgb(path) for i, path in enumerate(reference_files)}

        for chunk_index, chunk in enumerate(expected_chunks):
            chunk_path = os.path.join(archive_dir, chunk)
            assert os.path.isfile(chunk_path), f"Expected chunk missing: {chunk_path}"

            try:
                with tarfile.open(chunk_path, "r:gz") as tar:
                    members = [m for m in tar.getmembers() if m.isfile()]
                    assert len(members) == 5, f"Expected exactly 5 files in {chunk}, found {len(members)}"

                    expected_numbers = list(range(chunk_index * 5 + 1, chunk_index * 5 + 6))
                    numbered_members = []
                    for member in members:
                        basename = Path(member.name).name
                        match = re.search(r"(\d+)(?=\.[^.]+$)", basename)
                        assert match, f"Frame has no numeric sequence in its filename: {member.name}"
                        number_text = match.group(1)
                        number = int(number_text)
                        assert number_text == f"{number:03d}", f"Frame number must be zero-padded to three digits: {member.name}"
                        numbered_members.append((number, member))

                    assert sorted(number for number, _ in numbered_members) == expected_numbers, (
                        f"{chunk} must contain consecutive frames {expected_numbers}"
                    )

                    for number, member in numbered_members:
                        source = tar.extractfile(member)
                        assert source is not None
                        suffix = Path(member.name).suffix or ".frame"
                        submitted_path = os.path.join(submitted_dir, f"{number:03d}{suffix}")
                        with open(submitted_path, "wb") as output:
                            output.write(source.read())

                        actual = decoded_rgb(submitted_path)
                        expected = reference_rgb[number]
                        max_difference = max(abs(a - b) for a, b in zip(actual, expected))
                        assert max_difference <= 3, (
                            f"Frame {member.name} in {chunk} does not match frame {number} "
                            f"extracted from /app/dataset_video.mp4 at 1 FPS"
                        )
            except tarfile.TarError as e:
                pytest.fail(f"Failed to open tarball {chunk_path}: {e}")


def run_classifier(script_path, filepath):
    return subprocess.run(["bash", script_path, filepath], capture_output=True)


def test_classifier_clean_corpus():
    script_path = "/home/user/classifier.sh"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    clean_dir = "/app/test_corpora/clean"
    assert os.path.isdir(clean_dir), f"Hidden clean corpus directory missing: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, f"No files found in {clean_dir}"

    failed_files = []
    for filepath in clean_files:
        result = run_classifier(script_path, filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_classifier_evil_corpus():
    script_path = "/home/user/classifier.sh"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    evil_dir = "/app/test_corpora/evil"
    assert os.path.isdir(evil_dir), f"Hidden evil corpus directory missing: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    failed_files = []
    for filepath in evil_files:
        result = run_classifier(script_path, filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed/accepted. Offending files: {', '.join(failed_files)}")


def test_classifier_on_opaque_generated_inputs_and_embedding_usage():
    script_path = "/home/user/classifier.sh"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    embed_path = "/app/embed.py"
    original_bytes = Path(embed_path).read_bytes()
    original_mode = os.stat(embed_path).st_mode

    token = secrets.token_hex(12)
    saved_embed = f"/tmp/original_embed_{token}.py"
    call_log = f"/tmp/embed_calls_{token}.log"
    Path(saved_embed).write_bytes(original_bytes)

    wrapper = f'''import hashlib
import os
import sys
try:
    data = open(sys.argv[1], "rb").read()
    with open({call_log!r}, "a") as log:
        log.write(hashlib.sha256(data).hexdigest() + "\\n")
except Exception:
    pass
os.execv(sys.executable, [sys.executable, {saved_embed!r}] + sys.argv[1:])
'''

    rng = random.SystemRandom()
    math_tokens = ["theorem", "proof", "integral", "matrix", "derivative", "vector", "space", "dimension", "linear", "algebra"]
    evil_tokens = ["hello", "um", "students", "welcome", "today", "class", "so", "like", "okay", "guys", "matrix"]

    try:
        Path(embed_path).write_text(wrapper)
        os.chmod(embed_path, original_mode)

        with tempfile.TemporaryDirectory(prefix="classifier_inputs_") as input_dir:
            cases = []
            for source_tokens in (math_tokens, evil_tokens):
                for _ in range(12):
                    repetitions = rng.randint(1, 3)
                    words = source_tokens * repetitions
                    rng.shuffle(words)
                    filepath = os.path.join(input_dir, secrets.token_hex(16))
                    Path(filepath).write_text(" ".join(words) + "\n")

                    embedding = subprocess.run(
                        [sys.executable, saved_embed, filepath],
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                    vector = [float(value) for value in embedding.stdout.split()]
                    assert len(vector) == 10
                    expected_code = 0 if sum(vector[:5]) > sum(vector[5:]) else 1
                    cases.append((filepath, expected_code))

            rng.shuffle(cases)
            Path(call_log).write_text("")

            for filepath, expected_code in cases:
                before = Path(call_log).read_text().splitlines()
                result = run_classifier(script_path, filepath)
                assert result.returncode == expected_code, (
                    f"Classifier returned {result.returncode}, expected {expected_code}, "
                    f"for an opaque-path input whose label was derived from its embedding"
                )
                after = Path(call_log).read_text().splitlines()
                content_hash = hashlib.sha256(Path(filepath).read_bytes()).hexdigest()
                assert content_hash in after[len(before):], (
                    "classifier.sh did not invoke /app/embed.py on the supplied text content"
                )
    finally:
        Path(embed_path).write_bytes(original_bytes)
        os.chmod(embed_path, original_mode)
        for path in (saved_embed, call_log):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
