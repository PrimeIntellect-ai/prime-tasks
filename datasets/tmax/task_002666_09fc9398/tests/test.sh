#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_submission.py
import builtins
import io
import os
import runpy
import shutil
import sys
import zipfile

script, marker, cwd, *script_args = sys.argv[1:]
os.chdir(cwd)
sys.argv = [script] + script_args

_original_open = builtins.open
_original_io_open = io.open
_original_os_open = os.open

def mark_and_fail(*args, **kwargs):
    with _original_open(marker, "w") as f:
        f.write("extraction or filesystem write attempted")
    raise RuntimeError("archive extraction/filesystem writes are forbidden")

def guarded_open(file, mode="r", *args, **kwargs):
    if any(c in str(mode) for c in "wax+"):
        return mark_and_fail()
    return _original_open(file, mode, *args, **kwargs)

def guarded_io_open(file, mode="r", *args, **kwargs):
    if any(c in str(mode) for c in "wax+"):
        return mark_and_fail()
    return _original_io_open(file, mode, *args, **kwargs)

def guarded_os_open(path, flags, *args, **kwargs):
    write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
    if flags & write_flags:
        return mark_and_fail()
    return _original_os_open(path, flags, *args, **kwargs)

builtins.open = guarded_open
io.open = guarded_io_open
os.open = guarded_os_open
zipfile.ZipFile.extract = mark_and_fail
zipfile.ZipFile.extractall = mark_and_fail
shutil.unpack_archive = mark_and_fail

try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    code = exc.code
    if code is None:
        code = 0
    elif not isinstance(code, int):
        code = 1
    raise SystemExit(code)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid
import zipfile

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/verify_archive.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VIDEO_PATH = "/app/test_run.mp4"
RUNNER_PATH = "/tmp/run_submission.py"


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def run_script(zip_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, zip_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    return result.returncode


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.zip')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for f in clean_files:
        zip_path = os.path.join(CLEAN_CORPUS_DIR, f)
        exit_code = run_script(zip_path)
        if exit_code != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.zip')]
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed_files = []
    for f in evil_files:
        zip_path = os.path.join(EVIL_CORPUS_DIR, f)
        exit_code = run_script(zip_path)
        if exit_code == 0:
            bypassed_files.append(f)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def make_zip(path, entries):
    with zipfile.ZipFile(path, "w") as zf:
        for name, content in entries:
            zf.writestr(name, content)


def guarded_run(args, base_dir):
    work = tempfile.mkdtemp(prefix="empty-work-", dir=base_dir)
    marker = os.path.join(base_dir, "write-marker-" + uuid.uuid4().hex)
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        result = subprocess.run(
            ["python3", RUNNER_PATH, SCRIPT_PATH, marker, work] + list(args),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            env=env,
        )
        assert not os.path.exists(marker), (
            "The submission attempted to extract the archive or write to disk.\n"
            + result.stderr
        )
        assert os.listdir(work) == [], "The submission created extracted files in its working directory."
        return result.returncode
    finally:
        shutil.rmtree(work, ignore_errors=True)
        if os.path.exists(marker):
            os.unlink(marker)


def write_video(path, frame_count, blue_index):
    out = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 30, (100, 100))
    assert out.isOpened(), "Could not create verifier video"
    for i in range(frame_count):
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        if i == blue_index:
            frame[:] = (255, 0, 0)
        out.write(frame)
    out.release()


def derive_blue_frame(path):
    cap = cv2.VideoCapture(path)
    scores = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = frame.astype(np.float32).mean(axis=(0, 1))
        scores.append(float(b - max(g, r)))
    cap.release()
    assert scores
    winner = int(np.argmax(scores))
    assert scores[winner] > 100
    return winner


def test_generated_archives_argument_contract_video_and_no_extraction():
    with tempfile.TemporaryDirectory(prefix="verifier-cases-") as case_dir:
        assert guarded_run([], case_dir) == 1, "No arguments must exit with code 1"
        assert guarded_run(["one", "two"], case_dir) == 1, "Two arguments must exit with code 1"

        backup = os.path.join(case_dir, "original-video.mp4")
        shutil.copy2(VIDEO_PATH, backup)
        chosen = secrets.randbelow(10) + 2
        try:
            write_video(VIDEO_PATH, 14, chosen)
            expected_frame = derive_blue_frame(VIDEO_PATH)
            assert expected_frame == chosen

            good_log = f"header\n[EVENT]\nStatus: SUCCESS\nSync-Frame: {expected_frame}\nfooter\n"
            wrong_log = f"[EVENT]\nStatus: SUCCESS\nSync-Frame: {(expected_frame + 1) % 14}\n"
            absolute_target = os.path.join(case_dir, "absolute-escape-" + uuid.uuid4().hex)

            cases = []
            def add(label, entries, expected):
                path = os.path.join(case_dir, uuid.uuid4().hex + ".zip")
                make_zip(path, entries)
                cases.append((label, path, expected))

            add("ordinary valid archive", [("build.log", good_log), ("src/main.txt", "ok")], 0)
            add("safe normalized member", [("build.log", good_log), ("dir/../inside.txt", "ok")], 0)
            add("parent escape", [("build.log", good_log), ("../escape.txt", "bad")], 1)
            add("deep parent escape", [("build.log", good_log), ("dir/../../escape.txt", "bad")], 1)
            add("absolute path", [("build.log", good_log), (absolute_target, "bad")], 1)
            add("missing root log", [("nested/build.log", good_log), ("safe.txt", "ok")], 1)
            add("wrong frame", [("build.log", wrong_log)], 1)
            add("malformed event", [("build.log", f"[EVENT]\nStatus: FAILED\nSync-Frame: {expected_frame}\n")], 1)
            add("non-text log", [("build.log", b"\xff\xfe\x00\x81")], 1)

            corrupt = os.path.join(case_dir, uuid.uuid4().hex + ".zip")
            with open(corrupt, "wb") as f:
                f.write(secrets.token_bytes(80))
            cases.append(("non-ZIP input", corrupt, 1))

            for label, path, expected in cases:
                actual = guarded_run([path], case_dir)
                assert actual == expected, f"{label}: expected exit {expected}, got {actual}"
                assert not os.path.exists(absolute_target), "An archive member was extracted outside the working directory"
        finally:
            shutil.copy2(backup, VIDEO_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
