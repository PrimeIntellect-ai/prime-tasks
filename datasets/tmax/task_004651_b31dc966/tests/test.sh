#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import signal
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import uuid

import h5py
import numpy as np
import pytest
import redis

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
DETECTOR_SCRIPT = "/home/user/detector.py"
UPLOAD_URL = "http://localhost:5000/upload"
UPLOAD_DIR = "/tmp/uploads"


def post_file(url, file_path, upload_filename=None):
    boundary = "----VerifierBoundary" + uuid.uuid4().hex

    with open(file_path, "rb") as f:
        file_data = f.read()

    filename = upload_filename or os.path.basename(file_path)
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        f"Content-Type: application/x-hdf5\r\n\r\n"
    ).encode("utf-8") + file_data + f"\r\n--{boundary}--\r\n".encode("utf-8")

    req = urllib.request.Request(url, data=body)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")

    try:
        response = urllib.request.urlopen(req, timeout=5)
        return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def expected_classification(x):
    condition = np.linalg.cond(x.T @ x)
    return "EVIL" if not np.isfinite(condition) or condition >= 1e5 else "CLEAN"


def generate_unseen_cases(directory):
    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)
    cases = []

    # These produce Gram-matrix condition numbers on both sides of the threshold.
    targets = [1.5, 75.0, 8.0e4, 1.25e5, 2.0e6]
    for target in targets:
        q, _ = np.linalg.qr(rng.normal(size=(48, 8)))
        v, _ = np.linalg.qr(rng.normal(size=(8, 8)))
        singular_values = np.geomspace(1.0, 1.0 / np.sqrt(target), 8)
        x = q @ np.diag(singular_values) @ v.T
        path = os.path.join(directory, uuid.uuid4().hex + ".h5")
        with h5py.File(path, "w") as f:
            f.create_dataset("matrix_X", data=x)
            f.create_dataset("unrelated", data=rng.normal(size=7))
        cases.append((path, x, expected_classification(x)))

    q, _ = np.linalg.qr(rng.normal(size=(48, 8)))
    v, _ = np.linalg.qr(rng.normal(size=(8, 8)))
    singular_values = np.linspace(1.0, 0.2, 8)
    singular_values[-1] = 0.0
    x = q @ np.diag(singular_values) @ v.T
    path = os.path.join(directory, uuid.uuid4().hex + ".h5")
    with h5py.File(path, "w") as f:
        f.create_dataset("matrix_X", data=x)
    cases.append((path, x, expected_classification(x)))

    rng.shuffle(cases)
    assert any(item[2] == "CLEAN" for item in cases)
    assert any(item[2] == "EVIL" for item in cases)
    return cases


def stop_compute_workers():
    victims = []
    for entry in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            pid = int(entry.split("/")[2])
            if pid == os.getpid():
                continue
            with open(entry, "rb") as f:
                cmdline = f.read()
            if b"/app/worker/worker.py" in cmdline:
                os.kill(pid, signal.SIGTERM)
                victims.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"


def test_detector_on_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.h5"))
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for fpath in clean_files:
        result = subprocess.run(
            ["python3", DETECTOR_SCRIPT, fpath],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if output != "CLEAN":
            failed_files.append(os.path.basename(fpath))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (expected CLEAN). Offending files: {failed_files}"


def test_detector_on_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.h5"))
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for fpath in evil_files:
        result = subprocess.run(
            ["python3", DETECTOR_SCRIPT, fpath],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if output != "EVIL":
            failed_files.append(os.path.basename(fpath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected EVIL). Offending files: {failed_files}"


def test_api_clean_uploads():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.h5"))
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for fpath in clean_files:
        status = post_file(UPLOAD_URL, fpath)
        if status != 200:
            failed_files.append((os.path.basename(fpath), status))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files failed to upload via API. Offending files and status codes: {failed_files}"


def test_api_evil_uploads():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.h5"))
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for fpath in evil_files:
        status = post_file(UPLOAD_URL, fpath)
        if status != 400:
            failed_files.append((os.path.basename(fpath), status))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed API validation. Offending files and status codes: {failed_files}"


def test_detector_on_unseen_randomized_matrices():
    with tempfile.TemporaryDirectory(prefix="matrix_inputs_") as directory:
        for path, _x, expected in generate_unseen_cases(directory):
            result = subprocess.run(
                ["python3", DETECTOR_SCRIPT, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected


def test_api_unseen_inputs_queue_and_deletion_behavior():
    stop_compute_workers()
    broker = redis.Redis(host="localhost", port=6379, db=0)
    assert broker.ping()
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="uploaded_sources_") as directory:
        cases = generate_unseen_cases(directory)
        for source_path, source_x, expected in cases:
            broker.delete("task_queue")
            before = set(glob.glob(os.path.join(UPLOAD_DIR, "*")))
            neutral_name = uuid.uuid4().hex + ".h5"
            status = post_file(UPLOAD_URL, source_path, neutral_name)
            time.sleep(0.1)
            after = set(glob.glob(os.path.join(UPLOAD_DIR, "*")))

            if expected == "CLEAN":
                assert status == 200
                queued = broker.lrange("task_queue", 0, -1)
                assert len(queued) == 1, "A clean upload must add exactly one queue item"
                queued_path = queued[0].decode("utf-8")
                new_files = after - before
                assert new_files == {queued_path}
                assert os.path.isfile(queued_path)
                with h5py.File(queued_path, "r") as f:
                    np.testing.assert_array_equal(f["matrix_X"][:], source_x)
            else:
                assert status == 400
                assert broker.llen("task_queue") == 0, "A rejected upload must not be queued"
                assert after == before, "A rejected upload must be deleted"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
