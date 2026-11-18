#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/detect.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
VIDEO_PATH = "/app/spectroscopy.mp4"


def run_detector(c_file, timeout=180):
    return subprocess.run(
        [SCRIPT_PATH, c_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_detect_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Detector script missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Detector script is not executable: {SCRIPT_PATH}"


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.c"))
    assert len(clean_files) > 0, "No clean corpus files found to test."

    rejected = []
    for c_file in clean_files:
        result = run_detector(c_file)
        if result.returncode != 0:
            rejected.append(os.path.basename(c_file))

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean rejected: {', '.join(rejected)}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.c"))
    assert len(evil_files) > 0, "No evil corpus files found to test."

    bypassed = []
    for c_file in evil_files:
        result = run_detector(c_file)
        if result.returncode == 0:
            bypassed.append(os.path.basename(c_file))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def extracted_signal():
    cap = cv2.VideoCapture(VIDEO_PATH)
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(frame, dtype=np.float64)))
    cap.release()
    assert len(values) == 300, f"Expected 300 video frames, found {len(values)}"
    return values


def make_probe_source(path, marker, values, stable):
    expected = ",".join(f"{v:.9g}f" for v in values)
    accumulation = (
        "double sum = 0.0;\n"
        "        for (int i = 0; i < n; ++i) {\n"
        "            float want = expected[i % frames];\n"
        "            if (fabsf(data[i] - want) > 2.0f) valid = 0;\n"
        "            sum += (double)data[i];\n"
        "        }\n"
        "        result = (float)sum;"
        if stable else
        "float sum = 0.0f;\n"
        "        for (int i = 0; i < n; ++i) {\n"
        "            float want = expected[i % frames];\n"
        "            if (fabsf(data[i] - want) > 2.0f) valid = 0;\n"
        "            sum += data[i];\n"
        "        }\n"
        "        result = sum;"
    )
    source = f'''#include <math.h>
#include <stdio.h>

float integrate(float *data, int n) {{
    static const float expected[] = {{{expected}}};
    const int frames = (int)(sizeof(expected) / sizeof(expected[0]));
    const int required_n = frames * 100000;
    int valid = (data != NULL && n == required_n);
    float result = 0.0f;

    if (data != NULL && n > 0) {{
        {accumulation}
    }} else {{
        valid = 0;
    }}

    FILE *fp = fopen("{marker}", "wb");
    if (fp != NULL) {{
        fputs(valid ? "OK" : "BAD", fp);
        fclose(fp);
    }}
    return result;
}}
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(source)


def test_hidden_implementations_are_compiled_run_and_numerically_classified():
    values = extracted_signal()
    with tempfile.TemporaryDirectory(prefix="spectral_probe_") as work:
        cases = []
        for stable in (True, False):
            token = secrets.token_hex(12)
            source = os.path.join(work, token + ".c")
            marker = os.path.join(work, token + ".ran")
            make_probe_source(source, marker, values, stable)
            cases.append((source, marker, stable))

        for source, marker, stable in cases:
            result = run_detector(source)
            assert os.path.isfile(marker), (
                "The supplied integrate implementation was not executed; "
                f"detector output was stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            with open(marker, "rb") as f:
                marker_value = f.read()
            assert marker_value == b"OK", (
                "The harness did not pass the extracted 300-frame signal repeated "
                "100,000 times to integrate"
            )
            if stable:
                assert result.returncode == 0, (
                    "A hidden numerically stable implementation was rejected: "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
            else:
                assert result.returncode == 1, (
                    "A hidden naive float reduction was not rejected with exit code 1: "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
