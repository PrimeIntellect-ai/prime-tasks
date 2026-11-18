#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile
import io
import pytest

EXECUTABLE = "/home/user/dataset_filter"
SOURCE = "/home/user/dataset_filter.c"
VIDEO = "/app/dataset_video.mp4"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def parse_config(filepath):
    config = {}
    with open(filepath, "r") as f:
        for line in f:
            if ": " in line:
                key, val = line.strip().split(": ", 1)
                config[key] = val
    return config


def write_config(path, dataset="fixture", archive="frames.tar", start="0", end="1"):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"dataset_name: {dataset}\n")
        f.write(f"output_archive: {archive}\n")
        f.write(f"start_frame: {start}\n")
        f.write(f"end_frame: {end}\n")


def video_frame_count():
    result = subprocess.run([
        "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
        "-show_entries", "stream=nb_read_frames", "-of", "default=nw=1:nk=1", VIDEO
    ], capture_output=True, text=True, check=True)
    return int(result.stdout.strip())


def decode_source_frame(number):
    result = subprocess.run([
        "ffmpeg", "-v", "error", "-i", VIDEO,
        "-vf", f"select=eq(n\\,{number})", "-frames:v", "1",
        "-pix_fmt", "rgb24", "-f", "rawvideo", "-threads", "1", "-"
    ], capture_output=True, check=True)
    assert result.stdout, f"could not decode source frame {number}"
    return result.stdout


def decode_jpeg(data):
    result = subprocess.run([
        "ffmpeg", "-v", "error", "-f", "image2pipe", "-vcodec", "mjpeg", "-i", "-",
        "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-threads", "1", "-"
    ], input=data, capture_output=True, check=True)
    return result.stdout


def mean_abs_error(a, b):
    assert len(a) == len(b) and len(a) > 0
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "dataset_filter must be a compiled executable"
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"


def test_required_implementation_primitives():
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"\bmmap\s*\(", source) or ("SYS_mmap" in source and re.search(r"\bsyscall\s*\(", source)), \
        "configuration file must be read using mmap"
    assert re.search(r"\bmkdtemp\s*\(", source), "a securely created temporary directory is required"
    assert re.search(r"\brename(?:at|at2)?\s*\(", source), "final archive must be installed with an atomic rename"

    symbols = subprocess.run(["nm", "-D", EXECUTABLE], capture_output=True, text=True).stdout
    assert not re.search(r"\b(fopen|fopen64|fread|freopen|freopen64)(?:@|\s)", symbols), \
        "fopen/fread must not be used to read the configuration"


def test_exact_argument_count():
    assert subprocess.run([EXECUTABLE], capture_output=True).returncode == 1
    with tempfile.TemporaryDirectory() as td:
        cfg = os.path.join(td, "ok.cfg")
        write_config(cfg)
        assert subprocess.run([EXECUTABLE, cfg, "extra"], cwd=td, capture_output=True).returncode == 1


def test_evil_corpus_rejected():
    if not os.path.isfile(EXECUTABLE):
        pytest.fail("Executable not found")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    bypassed = []

    for evil_file in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, evil_file)
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed.append(evil_file)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_generated_invalid_configs_rejected():
    total = video_frame_count()
    valid = "dataset_name: fixture\noutput_archive: frames.tar\nstart_frame: 1\nend_frame: 3\n"
    cases = {
        "empty": "",
        "missing_key": "dataset_name: fixture\noutput_archive: frames.tar\nstart_frame: 1\n",
        "extra_key": valid + "other: value\n",
        "duplicate_key": valid + "start_frame: 2\n",
        "wrong_key": valid.replace("dataset_name", "Dataset_name"),
        "wrong_separator": valid.replace("dataset_name: ", "dataset_name:"),
        "reordered_typo": valid.replace("end_frame: ", "endframe: "),
        "slash": valid.replace("frames.tar", "../frames.tar"),
        "backslash": valid.replace("frames.tar", "foo\\bar.tar"),
        "subdirectory": valid.replace("frames.tar", "sub/frames.tar"),
        "double_dot": valid.replace("frames.tar", "frames..tar"),
        "hyphen": valid.replace("frames.tar", "bad-name.tar"),
        "wrong_suffix": valid.replace("frames.tar", "frames.tar.gz"),
        "empty_basename": valid.replace("frames.tar", ".tar"),
        "noninteger_start": valid.replace("start_frame: 1", "start_frame: one"),
        "noninteger_end": valid.replace("end_frame: 3", "end_frame: 3x"),
        "negative": valid.replace("start_frame: 1", "start_frame: -1"),
        "equal": valid.replace("end_frame: 3", "end_frame: 1"),
        "reversed": valid.replace("end_frame: 3", "end_frame: 0"),
        "past_video": valid.replace("end_frame: 3", f"end_frame: {total + 1}"),
    }

    with tempfile.TemporaryDirectory() as td:
        for name, contents in cases.items():
            cfg = os.path.join(td, name + ".cfg")
            with open(cfg, "w", encoding="utf-8") as f:
                f.write(contents)
            before = set(os.listdir(td))
            result = subprocess.run([EXECUTABLE, cfg], cwd=td, capture_output=True, timeout=20)
            assert result.returncode == 1, f"invalid case {name} returned {result.returncode}"
            after = set(os.listdir(td))
            assert after == before, f"invalid case {name} created output files"


def verify_archive(archive_path, start, end, total):
    with open(archive_path, "rb") as f:
        header = f.read(6)
    assert not header.startswith(b"\x1f\x8b"), "archive must be uncompressed"
    assert not header.startswith(b"BZh"), "archive must be uncompressed"
    assert not header.startswith(b"\xfd7zXZ\x00"), "archive must be uncompressed"

    with tarfile.open(archive_path, "r:") as tar:
        members = tar.getmembers()
        expected_names = [f"frame_{i:04d}.jpg" for i in range(end - start)]
        assert [m.name for m in members] == expected_names
        assert all(m.isfile() for m in members), "archive may contain only regular JPEG files"

        for relative, member in enumerate(members):
            data = tar.extractfile(member).read()
            assert data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9"), f"{member.name} is not JPEG"
            actual = decode_jpeg(data)
            frame_number = start + relative
            target = decode_source_frame(frame_number)
            assert len(actual) == len(target), f"{member.name} has the wrong dimensions"
            target_error = mean_abs_error(actual, target)
            assert target_error < 12.0, f"{member.name} does not resemble source frame {frame_number}"

            alternatives = []
            if frame_number > 0:
                alternatives.append(mean_abs_error(actual, decode_source_frame(frame_number - 1)))
            if frame_number + 1 < total:
                alternatives.append(mean_abs_error(actual, decode_source_frame(frame_number + 1)))
            if alternatives:
                assert target_error < min(alternatives), f"{member.name} is not source frame {frame_number}"


def test_generated_valid_configs_and_frame_contents():
    total = video_frame_count()
    assert total >= 6
    ranges = [(0, 3), (total // 2, total // 2 + 3), (total - 1, total)]

    with tempfile.TemporaryDirectory() as td:
        for index, (start, end) in enumerate(ranges):
            archive = f"valid_{index}.tar"
            cfg = os.path.join(td, f"valid_{index}.cfg")
            write_config(cfg, archive=archive, start=str(start), end=str(end))
            result = subprocess.run([EXECUTABLE, cfg], cwd=td, capture_output=True, timeout=90)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            archive_path = os.path.join(td, archive)
            assert os.path.isfile(archive_path), f"archive {archive} not created"
            verify_archive(archive_path, start, end, total)


def test_clean_corpus_accepted():
    if not os.path.isfile(EXECUTABLE):
        pytest.fail("Executable not found")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    failed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for clean_file in clean_files:
            filepath = os.path.join(CLEAN_CORPUS_DIR, clean_file)
            config = parse_config(filepath)

            result = subprocess.run([EXECUTABLE, filepath], cwd=tmpdir, capture_output=True)
            if result.returncode != 0:
                failed.append(f"{clean_file} (exit code {result.returncode})")
                continue

            output_archive = config.get("output_archive")
            if not output_archive:
                failed.append(f"{clean_file} (no output_archive in config)")
                continue

            archive_path = os.path.join(tmpdir, output_archive)
            if not os.path.isfile(archive_path):
                failed.append(f"{clean_file} (archive {output_archive} not created)")
                continue

            try:
                start_frame = int(config["start_frame"])
                end_frame = int(config["end_frame"])
                expected_count = end_frame - start_frame

                with tarfile.open(archive_path, "r") as tar:
                    members = tar.getmembers()
                    if len(members) != expected_count:
                        failed.append(f"{clean_file} (expected {expected_count} frames, got {len(members)})")
            except Exception as e:
                failed.append(f"{clean_file} (error verifying archive: {e})")

    if failed:
        pytest.fail(f"{len(failed)} of {len(clean_files)} clean modified/failed: {', '.join(failed)}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
