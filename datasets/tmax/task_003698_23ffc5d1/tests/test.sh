#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"


def run_detector(executable, directory):
    try:
        return subprocess.run(
            [executable, os.path.abspath(directory)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=4,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out while scanning {directory}")


@pytest.fixture(scope="session")
def rebuilt_detector():
    assert os.path.exists(SOURCE), f"Missing file: {SOURCE}"
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"C source is not a regular file: {SOURCE}"

    tempdir = tempfile.TemporaryDirectory(prefix="detector-build-")
    output = os.path.join(tempdir.name, "detector-from-source")
    result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "detector.c did not compile successfully:\n"
        + result.stderr.decode(errors="replace")
    )
    assert os.access(output, os.X_OK)
    yield output
    tempdir.cleanup()


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector"
    assert os.path.exists(detector_path), f"Missing file: {detector_path}"
    assert os.path.isfile(detector_path), f"Not a file: {detector_path}"
    assert os.access(detector_path, os.X_OK), f"File is not executable: {detector_path}"
    assert stat.S_ISREG(os.lstat(detector_path).st_mode), "Detector must be a regular file"
    with open(detector_path, "rb") as detector_file:
        assert detector_file.read(4) == b"\x7fELF", "Detector must be a compiled native executable"


def test_detector_clean_corpus():
    detector_path = "/home/user/detector"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    subdirs = [os.path.join(clean_dir, d) for d in os.listdir(clean_dir) if os.path.isdir(os.path.join(clean_dir, d))]
    assert len(subdirs) > 0, f"No subdirectories found in {clean_dir}"

    failed_clean = []
    for subdir in subdirs:
        result = run_detector(detector_path, subdir)
        if result != 0:
            failed_clean.append(os.path.basename(subdir))

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(subdirs)} clean modified/rejected. Offending: {', '.join(failed_clean)}")


def test_detector_evil_corpus():
    detector_path = "/home/user/detector"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    subdirs = [os.path.join(evil_dir, d) for d in os.listdir(evil_dir) if os.path.isdir(os.path.join(evil_dir, d))]
    assert len(subdirs) > 0, f"No subdirectories found in {evil_dir}"

    failed_evil = []
    for subdir in subdirs:
        result = run_detector(detector_path, subdir)
        if result != 1:
            failed_evil.append(os.path.basename(subdir))

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(subdirs)} evil bypassed. Offending: {', '.join(failed_evil)}")


def make_case(parent, kind):
    base = Path(parent) / uuid.uuid4().hex
    base.mkdir()
    timestamp = "[2026-08-17 09:08:07] entry"

    if kind == "simple_safe":
        (base / "log.txt").write_text(timestamp + "\ncontinuation\n", encoding="utf-8")
    elif kind == "recursive_safe":
        nested = base / uuid.uuid4().hex / uuid.uuid4().hex
        nested.mkdir(parents=True)
        (nested / "log.txt").write_text(timestamp + "\n", encoding="utf-8")
    elif kind == "fifty_line_safe":
        lines = [timestamp] + [f"continuation {i}" for i in range(49)]
        lines += ["[2026-08-17 09:08:08] next", "last"]
        (base / "log.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    elif kind == "internal_symlink_safe":
        nested = base / uuid.uuid4().hex
        nested.mkdir()
        (nested / "target.log").write_text(timestamp + "\n", encoding="utf-8")
        os.symlink(os.path.relpath(nested / "target.log", base), base / uuid.uuid4().hex)
    elif kind == "hardlink":
        original = base / uuid.uuid4().hex
        original.write_text(timestamp + "\n", encoding="utf-8")
        os.link(original, base / uuid.uuid4().hex)
    elif kind == "long_record":
        lines = [timestamp] + [f"continuation {i}" for i in range(50)]
        (base / "log.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    elif kind == "null_byte":
        nested = base / uuid.uuid4().hex
        nested.mkdir()
        (nested / "log.txt").write_bytes(timestamp.encode() + b"\npart\x00part\n")
    elif kind == "absolute_escape":
        outside = Path(parent) / (uuid.uuid4().hex + ".log")
        outside.write_text(timestamp + "\n", encoding="utf-8")
        os.symlink(str(outside), base / uuid.uuid4().hex)
    elif kind == "relative_escape":
        outside = Path(parent) / (uuid.uuid4().hex + ".log")
        outside.write_text(timestamp + "\n", encoding="utf-8")
        os.symlink(os.path.relpath(outside, base), base / uuid.uuid4().hex)
    elif kind == "symlink_loop":
        first = uuid.uuid4().hex
        second = uuid.uuid4().hex
        os.symlink(second, base / first)
        os.symlink(first, base / second)
    elif kind == "broken_symlink":
        os.symlink(uuid.uuid4().hex, base / uuid.uuid4().hex)
    else:
        raise AssertionError(f"Unknown fixture kind: {kind}")
    return base


def exercise_generated_cases(executable):
    specifications = [
        ("simple_safe", 0),
        ("recursive_safe", 0),
        ("fifty_line_safe", 0),
        ("internal_symlink_safe", 0),
        ("hardlink", 1),
        ("long_record", 1),
        ("null_byte", 1),
        ("absolute_escape", 1),
        ("relative_escape", 1),
        ("symlink_loop", 1),
        ("broken_symlink", 1),
    ]
    random.SystemRandom().shuffle(specifications)

    with tempfile.TemporaryDirectory(prefix="validator-fixtures-") as workspace:
        for kind, expected in specifications:
            case = make_case(workspace, kind)
            actual = run_detector(executable, case)
            assert actual == expected, (
                f"Detector returned {actual} for generated {kind} case; expected {expected}"
            )


def test_generated_behavior_and_compiled_source(rebuilt_detector):
    exercise_generated_cases(DETECTOR)
    exercise_generated_cases(rebuilt_detector)


def test_exactly_one_argument(rebuilt_detector):
    for executable in (DETECTOR, rebuilt_detector):
        no_args = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4)
        two_args = subprocess.run(
            [executable, "/tmp", "/tmp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=4,
        )
        assert no_args.returncode != 0, "Detector accepted zero directory arguments"
        assert two_args.returncode != 0, "Detector accepted more than one directory argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
