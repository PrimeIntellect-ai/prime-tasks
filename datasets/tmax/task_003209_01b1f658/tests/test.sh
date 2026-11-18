#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import json
import os
import random
import secrets
import subprocess
import tarfile

import pytest


def _image_size(path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "json", path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Could not decode image {path}: {result.stderr}"
    data = json.loads(result.stdout)
    assert len(data.get("streams", [])) == 1, f"Expected one image stream in {path}."
    stream = data["streams"][0]
    return stream["width"], stream["height"]


def _decode_rgb(path):
    width, height = _image_size(path)
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Could not decode image {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == width * height * 3, f"Image {path} did not decode to a complete frame."
    return width, height, result.stdout


def test_frames_extracted(tmp_path):
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} is missing."

    frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
    assert len(frames) == 15, f"Expected exactly 15 frames, found {len(frames)}."

    for i, frame in enumerate(frames, start=1):
        expected_name = f"frame_{i:03d}.jpg"
        actual_name = os.path.basename(frame)
        assert actual_name == expected_name, f"Expected frame name {expected_name}, got {actual_name}."

    expected_dir = tmp_path / "expected_frames"
    expected_dir.mkdir()
    result = subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error", "-i", "/app/camera_01.mp4",
            "-vf", "fps=1", str(expected_dir / "frame_%03d.jpg"),
        ],
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Verifier could not decode source video: {result.stderr.decode(errors='replace')}"
    expected = sorted(expected_dir.glob("frame_*.jpg"))
    assert len(expected) == 15, "Source video did not produce the expected 15 reference frames."

    expected_pixels = []
    for path in expected:
        width, height, pixels = _decode_rgb(str(path))
        assert (width, height) == (320, 240)
        expected_pixels.append(pixels)

    for index, frame in enumerate(frames):
        width, height, pixels = _decode_rgb(frame)
        assert (width, height) == (320, 240), f"{frame} has the wrong dimensions."

        target = expected_pixels[index]
        mean_error = sum(abs(a - b) for a, b in zip(pixels, target)) / len(target)
        assert mean_error <= 25.0, f"{frame} does not match frame {index + 1} of the source video."

        # Identify the temporal frame using a distributed sample, so duplicated or
        # fabricated JPEGs cannot satisfy the test merely by being decodable.
        sampled = pixels[::29]
        distances = [
            sum(abs(a - b) for a, b in zip(sampled, candidate[::29]))
            for candidate in expected_pixels
        ]
        assert distances[index] == min(distances), f"{frame} corresponds to the wrong source-video timestamp."
        assert distances.count(min(distances)) == 1, f"{frame} is not uniquely identifiable as the expected source frame."


def test_archive_created_correctly():
    archive_path = "/home/user/reference_frames.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            members = tar.getnames()
            assert len(members) == 15, f"Expected 15 files in archive, found {len(members)}."
            for i in range(1, 16):
                expected_name = f"frame_{i:03d}.jpg"
                assert expected_name in members, f"File {expected_name} is missing from the archive root."

            expected_names = {f"frame_{i:03d}.jpg" for i in range(1, 16)}
            assert set(members) == expected_names, "The archive must contain only the JPEG files at its root."
            for member in tar.getmembers():
                assert member.name == os.path.basename(member.name), f"Archive member {member.name} is not at the root."
                assert member.isfile(), f"Archive member {member.name} is not a regular JPEG file."
                archived_data = tar.extractfile(member).read()
                with open(os.path.join("/home/user/frames", member.name), "rb") as source:
                    assert archived_data == source.read(), f"Archived {member.name} differs from the extracted frame."
    except tarfile.ReadError:
        pytest.fail(f"Archive {archive_path} is not a valid or readable tar.gz file.")


def _add_bytes(tar, name, data=b"data"):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def _add_dir(tar, name):
    info = tarfile.TarInfo(name)
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    tar.addfile(info)


def _add_symlink(tar, name, target):
    info = tarfile.TarInfo(name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    info.mode = 0o777
    tar.addfile(info)


def _new_archive(directory, builder):
    path = directory / f"{secrets.token_hex(16)}.tar.gz"
    with tarfile.open(path, "w:gz") as tar:
        builder(tar)
    return str(path)


def _check_script(script_path, archive, expected):
    result = subprocess.run(["bash", script_path, archive], capture_output=True, text=True, timeout=15)
    expected_status = 0 if expected == "CLEAN" else 1
    assert result.returncode == expected_status, (
        f"{os.path.basename(archive)}: expected exit {expected_status}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"{os.path.basename(archive)}: expected {expected}, got stdout={result.stdout!r}"
    )


def test_verify_archive_script(tmp_path):
    script_path = "/home/user/verify_archive.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".tar.gz")] if os.path.isdir(clean_dir) else []
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".tar.gz")] if os.path.isdir(evil_dir) else []

    clean_bypassed = []
    evil_bypassed = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(["bash", script_path, filepath], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_bypassed.append(filename)

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(["bash", script_path, filepath], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(filename)

    reference_archive = "/home/user/reference_frames.tar.gz"
    if os.path.isfile(reference_archive):
        result = subprocess.run(["bash", script_path, reference_archive], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_bypassed.append("reference_frames.tar.gz")

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_bypassed:
        total_clean = len(clean_files) + (1 if os.path.isfile(reference_archive) else 0)
        error_messages.append(f"{len(clean_bypassed)} of {total_clean} clean modified/rejected: {', '.join(clean_bypassed)}")
    assert not error_messages, " | ".join(error_messages)

    # Generate hidden archives under indistinguishable randomized pathnames. The
    # expected result follows from archive contents, not from a corpus directory.
    cases = []
    cases.append((_new_archive(tmp_path, lambda t: _add_bytes(t, "ordinary.txt")), "CLEAN"))

    def nested_clean(t):
        _add_dir(t, "nested")
        _add_bytes(t, "nested/data.bin", b"payload")
        _add_bytes(t, "clock", b"not an exact lock name")
    cases.append((_new_archive(tmp_path, nested_clean), "CLEAN"))

    def safe_links(t):
        _add_bytes(t, "target.txt", b"target")
        _add_dir(t, "sub")
        _add_symlink(t, "link", "target.txt")
        _add_symlink(t, "sub/link", "../target.txt")
    cases.append((_new_archive(tmp_path, safe_links), "CLEAN"))

    cases.append((_new_archive(tmp_path, lambda t: _add_symlink(t, "link", "/etc/passwd")), "EVIL"))
    cases.append((_new_archive(tmp_path, lambda t: _add_symlink(t, "link", "../../outside")), "EVIL"))

    def nested_escape(t):
        _add_dir(t, "sub")
        _add_symlink(t, "sub/link", "../../outside")
    cases.append((_new_archive(tmp_path, nested_escape), "EVIL"))
    cases.append((_new_archive(tmp_path, lambda t: _add_bytes(t, "nested/lock", b"")), "EVIL"))

    def dot_lock_dir(t):
        _add_dir(t, "data")
        _add_dir(t, "data/.lock")
        _add_bytes(t, "data/.lock/item", b"incomplete")
    cases.append((_new_archive(tmp_path, dot_lock_dir), "EVIL"))

    corrupt = tmp_path / f"{secrets.token_hex(16)}.tar.gz"
    corrupt.write_bytes(b"this is not a readable gzip tar archive")
    cases.append((str(corrupt), "EVIL"))

    truncated = tmp_path / f"{secrets.token_hex(16)}.tar.gz"
    valid = _new_archive(tmp_path, lambda t: _add_bytes(t, "file", b"x" * 4096))
    data = open(valid, "rb").read()
    truncated.write_bytes(data[:max(1, len(data) // 2)])
    cases.append((str(truncated), "EVIL"))

    random.SystemRandom().shuffle(cases)
    for archive, expected in cases:
        _check_script(script_path, archive, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
