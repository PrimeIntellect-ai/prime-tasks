#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import subprocess
import tempfile
import time
import uuid


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def test_meta_extractor_compiles():
    """Verify that the meta-extractor code successfully compiles."""
    src_dir = "/home/user/meta-extractor"
    assert os.path.isdir(src_dir), f"{src_dir} directory is missing"

    result = run(["go", "build"], cwd=src_dir)
    assert result.returncode == 0, f"meta-extractor failed to compile:\n{result.stderr}"


def test_meta_extractor_runtime_fixes():
    """Exercise the repaired timestamp conversion and payload boundary."""
    src_dir = "/home/user/meta-extractor"
    with tempfile.TemporaryDirectory(prefix="meta-check-") as td:
        binary = os.path.join(td, "meta-extractor")
        built = run(["go", "build", "-o", binary, "."], cwd=src_dir)
        assert built.returncode == 0, f"meta-extractor failed to compile:\n{built.stderr}"

        before = time.time_ns()
        result = run([binary])
        after = time.time_ns()
        assert result.returncode == 0, (
            "meta-extractor crashed while traversing its payload; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(lines) >= 4, f"Unexpected meta-extractor output: {result.stdout!r}"
        assert lines[:3] == ["1", "2", "3"], (
            "Payload traversal did not process exactly the three in-bounds bytes"
        )
        try:
            timestamp = int(lines[-1])
        except ValueError as exc:
            raise AssertionError(f"Timestamp is not an integer: {lines[-1]!r}") from exc
        assert timestamp > 2**31 - 1, "Timestamp is still truncated to 32-bit precision"
        tolerance = 60 * 1_000_000_000
        assert before - tolerance <= timestamp <= after + tolerance, (
            f"Timestamp {timestamp} is not a current Unix nanosecond timestamp"
        )


def test_detector_corpus():
    """Verify the detector correctly classifies clean and evil payloads."""
    detector_path = "/home/user/detector"
    assert os.path.isfile(detector_path), f"Detector binary {detector_path} is missing"
    assert os.access(detector_path, os.X_OK), f"Detector binary {detector_path} is not executable"

    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.bin')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.bin')]

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    failed_clean = []
    for f in clean_files:
        res = run([detector_path, f])
        if res.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        res = run([detector_path, f])
        if res.returncode != 1:
            failed_evil.append(os.path.basename(f))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean[:5])}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil[:5])}")

    assert not error_msgs, " | ".join(error_msgs)


def test_detector_parses_payload_not_pathname():
    """Test opaque, path-neutral copies and independently derive their labels."""
    source = "/home/user/detector.go"
    submitted = "/home/user/detector"
    assert os.path.isfile(source), f"Detector source {source} is missing"

    with tempfile.TemporaryDirectory(prefix="payload-check-") as td:
        rebuilt = os.path.join(td, "rebuilt-detector")
        build = run(["go", "build", "-o", rebuilt, source], cwd=td)
        assert build.returncode == 0, f"detector.go failed to compile:\n{build.stderr}"

        originals = []
        for directory in ("/home/user/corpus/clean", "/home/user/corpus/evil"):
            originals.extend(
                os.path.join(directory, name)
                for name in os.listdir(directory)
                if name.endswith(".bin")
            )
        assert originals, "No payload files found"
        random.SystemRandom().shuffle(originals)

        cases = []
        neutral_dir = os.path.join(td, "inputs")
        os.mkdir(neutral_dir)
        for original in originals:
            opaque = os.path.join(neutral_dir, uuid.uuid4().hex + ".dat")
            shutil.copyfile(original, opaque)
            data = open(opaque, "rb").read()
            assert len(data) >= 6 and data[:4] == b"META", f"Malformed corpus fixture: {original}"
            value = struct.unpack(">h", data[4:6])[0]
            expected = 1 if value < 0 else 0
            cases.append((opaque, expected))

        random.SystemRandom().shuffle(cases)
        for detector in (submitted, rebuilt):
            for payload, expected in cases:
                result = run([detector, payload])
                assert result.returncode == expected, (
                    f"{detector} returned {result.returncode} instead of {expected} "
                    f"for an opaque payload path"
                )


def test_red_frame_count():
    """Verify the red frame count is exactly 7."""
    count_file = "/home/user/red_frame_count.txt"
    assert os.path.isfile(count_file), f"{count_file} is missing"

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content == "7", f"Expected red frame count to be '7', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
