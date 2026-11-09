#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import os
import random
import secrets
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/validate_logs.py"


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_classification(path, expected_valid):
    result = run_validator(path)
    expected_code = 0 if expected_valid else 1
    expected_output = "VALID" if expected_valid else "INVALID"
    assert result.returncode == expected_code, (
        f"Validator returned {result.returncode} for a case expected to be "
        f"{expected_output}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Expected exact output {expected_output!r}, got {result.stdout!r}"
    )


@pytest.fixture(scope="module")
def protobuf_module():
    build_dir = tempfile.mkdtemp(prefix="validator_proto_")
    schema_path = os.path.join(build_dir, "video_events.proto")
    with open(schema_path, "w") as f:
        f.write('''syntax = "proto3";
message Event {
  int64 start_time_ms = 1;
  int64 end_time_ms = 2;
  string event_type = 3;
}
message VideoEventLog {
  repeated Event events = 1;
}
''')
    subprocess.run(
        ["protoc", f"-I{build_dir}", f"--python_out={build_dir}", schema_path],
        check=True,
        capture_output=True,
        text=True,
    )
    sys.path.insert(0, build_dir)
    try:
        yield importlib.import_module("video_events_pb2")
    finally:
        sys.path.remove(build_dir)
        sys.modules.pop("video_events_pb2", None)


def write_log(pb, path, events):
    log = pb.VideoEventLog()
    for start, end, event_type in events:
        event = log.events.add()
        event.start_time_ms = start
        event.end_time_ms = end
        event.event_type = event_type
    with open(path, "wb") as f:
        f.write(log.SerializeToString())


def test_validate_logs_clean_corpus():
    """Preserve the supplied clean-corpus check with exact output matching."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"

    clean_corpus_dir = "/app/eval_corpus/clean"
    assert os.path.isdir(clean_corpus_dir), f"Clean corpus directory not found: {clean_corpus_dir}"
    clean_files = [
        os.path.join(clean_corpus_dir, name)
        for name in os.listdir(clean_corpus_dir)
        if os.path.isfile(os.path.join(clean_corpus_dir, name))
    ]
    assert clean_files, "No files found in clean corpus directory."
    for path in clean_files:
        assert_classification(path, True)


def test_validate_logs_evil_corpus():
    """Preserve the supplied evil-corpus check with exact output matching."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"

    evil_corpus_dir = "/app/eval_corpus/evil"
    assert os.path.isdir(evil_corpus_dir), f"Evil corpus directory not found: {evil_corpus_dir}"
    evil_files = [
        os.path.join(evil_corpus_dir, name)
        for name in os.listdir(evil_corpus_dir)
        if os.path.isfile(os.path.join(evil_corpus_dir, name))
    ]
    assert evil_files, "No files found in evil corpus directory."
    for path in evil_files:
        assert_classification(path, False)


def test_validator_on_fresh_unlabeled_cases(protobuf_module):
    """Exercise all invariants using fresh files whose paths do not reveal answers."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"
    rng = random.Random(secrets.randbits(128))

    base = rng.randint(20, 2000)
    duration = rng.randint(2, 100)
    valid_bulk = []
    cursor = rng.randint(0, 30)
    for index in range(rng.randint(5, 10)):
        length = rng.randint(1, 80)
        valid_bulk.append((cursor, cursor + length, f"bulk-{index}"))
        cursor += length + rng.randint(0, 25)
    rng.shuffle(valid_bulk)

    overlap_start = base + rng.randint(1, duration - 1)
    cases = [
        ([], True),
        ([(0, 1, "single")], True),
        ([(base, base + duration, "single")], True),
        ([(base, base + duration, "a"), (base + duration, base + duration + 7, "b")], True),
        ([(base + duration + 20, base + duration + 30, "later"), (base, base + duration, "earlier")], True),
        (valid_bulk, True),
        ([(-rng.randint(1, 100), rng.randint(1, 100), "negative")], False),
        ([(base, base, "zero")], False),
        ([(base + duration, base, "reverse")], False),
        ([(base, base + duration, "a"), (overlap_start, base + duration + 10, "b")], False),
        ([(overlap_start, base + duration + 10, "b"), (base, base + duration, "a")], False),
        ([(base, base + duration + 20, "outer"), (base + 2, base + 3, "inner")], False),
        ([(0, 10, "a"), (30, 40, "c"), (9, 31, "b")], False),
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="protobuf_inputs_") as case_dir:
        materialized = []
        for events, expected_valid in cases:
            path = os.path.join(case_dir, uuid.uuid4().hex + ".dat")
            write_log(protobuf_module, path, events)
            materialized.append((path, expected_valid))
        rng.shuffle(materialized)
        for path, expected_valid in materialized:
            assert_classification(path, expected_valid)


def test_black_frames_count():
    """Verify the black frames count is correct."""
    count_file = "/home/user/black_frames_count.txt"
    assert os.path.exists(count_file), f"Black frames count file not found: {count_file}"

    with open(count_file, "r") as f:
        content = f.read().strip()

    try:
        student_count = int(content)
    except ValueError:
        pytest.fail(f"Content of {count_file} is not a valid integer: {content!r}")

    video_path = "/app/reference_video.mp4"
    assert os.path.exists(video_path), f"Reference video not found: {video_path}"

    cmd = f"ffmpeg -i {video_path} -vf blackframe -f null - 2>&1 | grep blackframe | wc -l"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    try:
        expected_count = int(result.stdout.strip())
    except ValueError:
        pytest.fail("Failed to compute expected black frames count using ffmpeg.")

    assert student_count == expected_count, (
        f"Expected {expected_count} black frames, but found {student_count} in {count_file}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
