#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid
import urllib.error
import urllib.request

import numpy as np
import pandas as pd
import redis
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

UPLOAD_URL = "http://127.0.0.1:8080/upload"
DETECTOR = "/home/user/app/detector.py"


def post_multipart(url, file_path, field_name="file", upload_name=None):
    boundary = uuid.uuid4().hex
    with open(file_path, "rb") as f:
        file_content = f.read()

    filename = upload_name or os.path.basename(file_path)
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"{field_name}\"; filename=\"{filename}\"\r\n"
        f"Content-Type: text/csv\r\n\r\n"
    ).encode() + file_content + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(url, data=body)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def expected_exit_code(data):
    scaled = StandardScaler().fit_transform(data)
    ratio = PCA().fit(scaled).explained_variance_ratio_[0]
    return 1 if ratio > 0.95 else 0


def generated_cases():
    seed = int.from_bytes(os.urandom(8), "big")
    rng = np.random.default_rng(seed)
    cases = []

    for _ in range(3):
        rows = int(rng.integers(70, 130))
        cols = int(rng.integers(4, 8))
        cases.append(rng.normal(size=(rows, cols)))

    for _ in range(3):
        rows = int(rng.integers(70, 130))
        cols = int(rng.integers(4, 8))
        base = rng.normal(size=rows)
        noise = float(rng.uniform(0.001, 0.02))
        cases.append(np.column_stack([base + rng.normal(0, noise, rows) for _ in range(cols)]))

    # For two standardized features, correlations just below and above 0.9
    # place the first-PC ratio just below and above the strict 0.95 cutoff.
    raw = rng.normal(size=(120, 2))
    raw -= raw.mean(axis=0)
    q, _ = np.linalg.qr(raw)
    x, z = q[:, 0], q[:, 1]
    for correlation in (0.899, 0.901):
        y = correlation * x + np.sqrt(1.0 - correlation ** 2) * z
        cases.append(np.column_stack((x, y)))

    results = [(data, expected_exit_code(data)) for data in cases]
    assert {code for _, code in results} == {0, 1}
    return results


def redis_count():
    value = redis.Redis(host="127.0.0.1", port=6379, db=0).get("processed_files")
    return int(value or 0)


def write_csv(path, data):
    pd.DataFrame(data, columns=[f"sensor_{i}" for i in range(data.shape[1])]).to_csv(path, index=False)


def test_detector_exists():
    assert os.path.isfile(DETECTOR), f"Detector script {DETECTOR} is missing."


def test_detector_standalone_on_unseen_inputs():
    with tempfile.TemporaryDirectory() as directory:
        for data, expected in generated_cases():
            # Deliberately give each class a misleading filename.
            prefix = "clean_bait" if expected == 1 else "evil_bait"
            path = os.path.join(directory, f"{prefix}_{uuid.uuid4().hex}.csv")
            write_csv(path, data)
            result = subprocess.run(
                ["python3", DETECTOR, os.path.abspath(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert result.returncode == expected, (
                f"Detector returned {result.returncode}, expected {expected}; "
                f"stderr={result.stderr.decode(errors='replace')}"
            )


def test_clean_corpus():
    clean_dir = "/home/user/data/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
    assert len(files) > 0, "No clean corpus files found."

    failed_files = []
    for f in files:
        path = os.path.join(clean_dir, f)
        status = post_multipart(UPLOAD_URL, path)
        if status != 200:
            failed_files.append(f)

    assert not failed_files, f"{len(failed_files)} of {len(files)} clean modified/rejected: {failed_files}"


def test_evil_corpus():
    evil_dir = "/home/user/data/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert len(files) > 0, "No evil corpus files found."

    failed_files = []
    for f in files:
        path = os.path.join(evil_dir, f)
        status = post_multipart(UPLOAD_URL, path)
        if status != 400:
            failed_files.append(f)

    assert not failed_files, f"{len(failed_files)} of {len(files)} evil bypassed: {failed_files}"


def test_upload_on_unseen_inputs_and_redis_behavior():
    before = redis_count()
    accepted = 0
    with tempfile.TemporaryDirectory() as directory:
        for data, expected in generated_cases():
            prefix = "clean_bait" if expected == 1 else "evil_bait"
            path = os.path.join(directory, f"payload_{uuid.uuid4().hex}.csv")
            write_csv(path, data)
            status = post_multipart(
                UPLOAD_URL,
                path,
                upload_name=f"{prefix}_{uuid.uuid4().hex}.csv",
            )
            wanted_status = 400 if expected == 1 else 200
            assert status == wanted_status, f"Upload returned {status}, expected {wanted_status}"
            if expected == 0:
                accepted += 1

    after = redis_count()
    assert after == before + accepted, (
        "Redis processed_files must increment exactly once per accepted upload "
        "and not increment for rejected uploads"
    )


def test_flask_actually_invokes_detector_path():
    original = open(DETECTOR, "rb").read()
    original_mode = stat.S_IMODE(os.stat(DETECTOR).st_mode)
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))

    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, f"payload_{uuid.uuid4().hex}.csv")
        write_csv(path, rng.normal(size=(80, 5)))
        upload_name = f"neutral_{uuid.uuid4().hex}.csv"
        before = redis_count()
        try:
            with open(DETECTOR, "w") as f:
                f.write("#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n")
            os.chmod(DETECTOR, 0o755)
            rejected_status = post_multipart(UPLOAD_URL, path, upload_name=upload_name)
            after_reject = redis_count()

            with open(DETECTOR, "w") as f:
                f.write("#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n")
            os.chmod(DETECTOR, 0o755)
            accepted_status = post_multipart(UPLOAD_URL, path, upload_name=upload_name)
            after_accept = redis_count()
        finally:
            with open(DETECTOR, "wb") as f:
                f.write(original)
            os.chmod(DETECTOR, original_mode)

    assert rejected_status == 400, "Flask did not honor detector.py exit code 1"
    assert after_reject == before, "Rejected data was written to Redis"
    assert accepted_status == 200, "Flask did not honor detector.py exit code 0"
    assert after_accept == before + 1, "Accepted data was not saved to Redis"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
