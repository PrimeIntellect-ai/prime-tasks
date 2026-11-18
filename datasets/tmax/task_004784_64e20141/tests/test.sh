#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tempfile

import cv2
import pytest

SCRIPT_PATH = "/home/user/process_manifests"


def test_failure_count():
    """Preserve the known result and independently derive it from the supplied video."""
    count_file = "/home/user/failure_count.txt"
    assert os.path.isfile(count_file), f"Missing {count_file}"
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "43", f"Expected failure count 43, but got {content}"

    video = cv2.VideoCapture("/app/storage_dashboard.mp4")
    assert video.isOpened(), "Could not open /app/storage_dashboard.mp4"
    derived_count = 0
    frame_count = 0
    while True:
        ok, frame = video.read()
        if not ok:
            break
        frame_count += 1
        blue, green, red = frame.mean(axis=(0, 1))
        if red > 150 and green < 50 and blue < 50:
            derived_count += 1
    video.release()
    assert frame_count > 0, "Dashboard video contained no readable frames"
    assert int(content) == derived_count, (
        f"failure_count.txt says {content}, but video analysis found {derived_count}"
    )


def test_process_manifests_executable():
    """Check if the process_manifests script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Missing script {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_process_manifests_clean_corpus():
    """Preserve checks against the original clean corpus."""
    clean_in = "/app/corpus/clean"

    with tempfile.TemporaryDirectory() as clean_out:
        result = subprocess.run([SCRIPT_PATH, clean_in, clean_out], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on clean corpus. stderr: {result.stderr}"

        expected_files = set(os.listdir(clean_in))
        actual_files = set(os.listdir(clean_out))
        assert "manifest.sha256" in actual_files, "manifest.sha256 is missing in clean output directory"
        actual_files.remove("manifest.sha256")

        missing = expected_files - actual_files
        assert not missing, f"Clean files missing from output: {missing}"

        manifest_path = os.path.join(clean_out, "manifest.sha256")
        with open(manifest_path, "r") as f:
            manifest_lines = f.read().strip().splitlines()

        manifest_hashes = {}
        for line in manifest_lines:
            if not line.strip():
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                filename = parts[1].lstrip(" *")
                manifest_hashes[filename] = parts[0]

        for filename in expected_files:
            file_path = os.path.join(clean_out, filename)
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    f.read()
            except UnicodeDecodeError:
                pytest.fail(f"File {filename} is not valid UTF-8")

            with open(file_path, "rb") as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()
            assert filename in manifest_hashes, f"File {filename} missing from manifest.sha256"
            assert manifest_hashes[filename] == file_hash, f"Hash mismatch for {filename} in manifest"


def test_process_manifests_evil_corpus():
    """Preserve checks against the original evil corpus."""
    evil_in = "/app/corpus/evil"

    with tempfile.TemporaryDirectory() as evil_out:
        subprocess.run([SCRIPT_PATH, evil_in, evil_out], capture_output=True, text=True)
        expected_files = set(os.listdir(evil_in))
        actual_files = set(os.listdir(evil_out))
        if "manifest.sha256" in actual_files:
            actual_files.remove("manifest.sha256")
        bypassed = actual_files.intersection(expected_files)
        assert not bypassed, f"{len(bypassed)} of {len(expected_files)} evil bypassed: {bypassed}"
        assert not actual_files, f"Unexpected files in evil output directory: {actual_files}"


def parse_standard_manifest(path):
    entries = {}
    with open(path, "r", encoding="utf-8", errors="strict", newline="") as manifest:
        for raw_line in manifest:
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            match = re.fullmatch(r"([0-9a-fA-F]{64}) ([ *])(.+)", line)
            assert match, f"Non-standard sha256sum manifest line: {line!r}"
            digest, _marker, filename = match.groups()
            assert filename not in entries, f"Duplicate manifest entry for {filename!r}"
            entries[filename] = digest.lower()
    return entries


def test_randomized_mixed_adversarial_corpus():
    """Exercise fresh names, all required encodings, and every forbidden content pattern."""
    token = secrets.token_hex(12)
    safe_specs = [
        (f"utf8_{token}.txt", f"Café and 東京 are safe metadata {token}", "utf-8"),
        (f"utf16_{token}.txt", f"Safe UTF-16 snowman ☃ metadata {token}", "utf-16"),
        (f"latin1_{token}.txt", f"Café £ storage metadata {token}", "iso-8859-1"),
        (f"sjis_{token}.txt", f"安全な保管データ {token}", "shift_jis"),
    ]
    forbidden = [
        "../private/file",
        "..\\private\\file",
        "embedded\x00byte",
        "/etc/passwd",
        "/var/lib/storage",
        "/root/secret",
    ]
    encodings = ["utf-8", "utf-16", "iso-8859-1", "shift_jis"]

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        expected = {}
        for filename, text, encoding in safe_specs:
            with open(os.path.join(input_dir, filename), "wb") as uploaded:
                uploaded.write(text.encode(encoding))
            expected[filename] = text.encode("utf-8")

        for index, pattern in enumerate(forbidden):
            encoding = encodings[index % len(encodings)]
            filename = f"payload_{token}_{index}.dat"
            text = f"random-prefix-{secrets.token_hex(7)} {pattern} suffix-{token}"
            with open(os.path.join(input_dir, filename), "wb") as uploaded:
                uploaded.write(text.encode(encoding))

        # A traversal sequence in the filename must be rejected even when content is safe.
        bad_filename = f"named_{token}_..\\escape.txt"
        with open(os.path.join(input_dir, bad_filename), "wb") as uploaded:
            uploaded.write(f"otherwise safe {token}".encode("utf-8"))

        result = subprocess.run(
            [SCRIPT_PATH, input_dir, output_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed on mixed corpus. stderr: {result.stderr}"

        actual_names = set(os.listdir(output_dir))
        assert actual_names == set(expected) | {"manifest.sha256"}, (
            f"Wrong output set. Expected approved files only; got {actual_names}"
        )

        for filename, expected_bytes in expected.items():
            output_path = os.path.join(output_dir, filename)
            assert os.path.isfile(output_path), f"Approved output {filename!r} is not a regular file"
            assert not os.path.islink(output_path), f"Approved output {filename!r} was not copied"
            with open(output_path, "rb") as processed:
                actual_bytes = processed.read()
            assert actual_bytes == expected_bytes, f"Incorrect UTF-8 conversion for {filename}"
            actual_bytes.decode("utf-8", errors="strict")

        manifest_path = os.path.join(output_dir, "manifest.sha256")
        manifest = parse_standard_manifest(manifest_path)
        assert set(manifest) == set(expected), "Manifest must list every and only approved file"
        for filename, expected_bytes in expected.items():
            assert manifest[filename] == hashlib.sha256(expected_bytes).hexdigest(), (
                f"Incorrect manifest hash for {filename}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
