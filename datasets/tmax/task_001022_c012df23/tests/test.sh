#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import re
import subprocess

import pytest

SERVICE = "/home/user/service"
SOURCE = os.path.join(SERVICE, "audio_ops.cpp")
BUILD = os.path.join(SERVICE, "build.sh")
LIBRARY = os.path.join(SERVICE, "libaudio.so")
PIPELINE = os.path.join(SERVICE, "pipeline.py")
OUTPUT = os.path.join(SERVICE, "anomaly_score.txt")
INCIDENT = "/app/incident_809.wav"


def exercise_library(path):
    lib = ctypes.CDLL(path)
    fn = lib.calculate_anomaly_score
    fn.argtypes = [ctypes.POINTER(ctypes.c_short), ctypes.c_int]
    fn.restype = ctypes.c_double

    rng = random.SystemRandom()
    cases = [
        [0] * 17,
        [3, -4],
        [rng.randint(-20000, 20000) for _ in range(31)],
        [rng.randint(-30000, 30000) for _ in range(257)],
    ]

    for samples in cases:
        # The extra sentinel makes an i <= num_samples boundary bug observable.
        values = samples + [30000]
        array = (ctypes.c_short * len(values))(*values)
        actual = fn(array, len(samples))
        expected = math.sqrt(sum(x * x for x in samples) / len(samples))
        assert math.isfinite(actual), "Library returned a non-finite score"
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-7), (
            f"calculate_anomaly_score returned {actual}; expected {expected}"
        )


@pytest.fixture(scope="session", autouse=True)
def verify_repair_and_run_pipeline():
    assert os.path.isfile(SOURCE), f"Missing C++ source: {SOURCE}"
    assert os.path.isfile(BUILD), f"Missing build script: {BUILD}"
    assert os.path.isfile(PIPELINE), f"Missing pipeline: {PIPELINE}"
    assert os.path.isfile(INCIDENT), f"Missing incident artifact: {INCIDENT}"

    # Compile the submitted source independently so a build script cannot hide
    # an unfixed audio_ops.cpp behind a different or stale library.
    source_library = "/tmp/libaudio_source_verifier.so"
    result = subprocess.run(
        ["g++", "-fPIC", "-shared", "-o", source_library, SOURCE, "-lm"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"audio_ops.cpp does not compile:\n{result.stdout}"
    exercise_library(source_library)

    # The requested linker fix must be present in the submitted build script.
    with open(BUILD, "r") as f:
        active_build_text = "\n".join(line.split("#", 1)[0] for line in f)
    assert re.search(r"(?:^|\s)-lm(?:\s|$)", active_build_text), (
        "build.sh does not link the math library with -lm"
    )

    if os.path.exists(LIBRARY):
        os.remove(LIBRARY)
    result = subprocess.run(
        ["bash", BUILD],
        cwd=SERVICE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"build.sh failed:\n{result.stdout}"
    assert os.path.isfile(LIBRARY), "build.sh did not create libaudio.so"
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libaudio.so is not an ELF library"
    exercise_library(LIBRARY)

    # Remove any prewritten answer and require the repaired pipeline to produce it.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", PIPELINE, INCIDENT],
        cwd=SERVICE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"Pipeline failed:\n{result.stdout}"
    yield


def test_anomaly_score_metric():
    """Check that the anomaly score is computed correctly within the tolerance."""
    output_file = "/home/user/service/anomaly_score.txt"

    assert os.path.isfile(output_file), f"Output file missing: {output_file}. Did you run the pipeline?"

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content, f"Output file {output_file} is empty."

    try:
        score = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {output_file} as a float. Found: {content}")

    target_value = 7071.06
    tolerance = 0.1
    difference = abs(score - target_value)

    assert difference <= tolerance, (
        f"Anomaly score {score} is not within {tolerance} of the target {target_value}. "
        f"Difference is {difference}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
