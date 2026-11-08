#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/sitecustomize.py
import os

_trace = os.environ.get("DETECTOR_SVD_TRACE")

def _record(kind):
    if _trace:
        with open(_trace, "a", encoding="utf-8") as f:
            f.write(kind + "\n")

try:
    import numpy.linalg as _npl
    _original_numpy_svd = _npl.svd
    def _numpy_svd(*args, **kwargs):
        _record("numpy.linalg.svd")
        return _original_numpy_svd(*args, **kwargs)
    _npl.svd = _numpy_svd
except Exception:
    pass

try:
    import scipy.linalg as _spl
    _original_scipy_svd = _spl.svd
    def _scipy_svd(*args, **kwargs):
        _record("scipy.linalg.svd")
        return _original_scipy_svd(*args, **kwargs)
    _spl.svd = _scipy_svd
except Exception:
    pass

try:
    import scipy.sparse.linalg as _spsl
    _original_sparse_svds = _spsl.svds
    def _sparse_svds(*args, **kwargs):
        _record("scipy.sparse.linalg.svds")
        return _original_sparse_svds(*args, **kwargs)
    _spsl.svds = _sparse_svds
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import uuid

import numpy as np
from scipy.io import wavfile

CLEAN_CORPUS = "/app/corpus/clean/"
EVIL_CORPUS = "/app/corpus/evil/"
DETECTOR_SCRIPT = "/home/user/detector.py"
CLEAN_OUTPUT = "/tmp/clean_results.json"
EVIL_OUTPUT = "/tmp/evil_results.json"


def run_detector(input_dir, output_file, extra_env=None):
    try:
        os.remove(output_file)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["python3", DETECTOR_SCRIPT, "--input", input_dir, "--output", output_file],
        capture_output=True,
        text=True,
        timeout=180,
        env=env,
    )


def test_detector_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"


def test_clean_corpus_classification():
    result = run_detector(CLEAN_CORPUS, CLEAN_OUTPUT)
    assert result.returncode == 0, f"Detector script failed on clean corpus:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.isfile(CLEAN_OUTPUT), f"Output JSON not created at {CLEAN_OUTPUT}"

    with open(CLEAN_OUTPUT, "r", encoding="utf-8") as f:
        clean_results = json.load(f)

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".wav")]
    failures = []
    for cf in clean_files:
        if cf not in clean_results:
            failures.append(f"{cf} (missing)")
        elif clean_results[cf] != "clean":
            failures.append(f"{cf} (got {clean_results[cf]})")

    assert not failures, f"{len(failures)} of {len(clean_files)} clean files modified/misclassified: {', '.join(failures)}"


def test_evil_corpus_classification():
    result = run_detector(EVIL_CORPUS, EVIL_OUTPUT)
    assert result.returncode == 0, f"Detector script failed on evil corpus:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.isfile(EVIL_OUTPUT), f"Output JSON not created at {EVIL_OUTPUT}"

    with open(EVIL_OUTPUT, "r", encoding="utf-8") as f:
        evil_results = json.load(f)

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith(".wav")]
    failures = []
    for ef in evil_files:
        if ef not in evil_results:
            failures.append(f"{ef} (missing)")
        elif evil_results[ef] != "corrupted":
            failures.append(f"{ef} (got {evil_results[ef]})")

    assert not failures, f"{len(failures)} of {len(evil_files)} evil files bypassed/misclassified: {', '.join(failures)}"


def test_randomized_mixed_corpus_and_iterative_svd(tmp_path):
    # Generate fresh examples from the same signal model as the supplied corpus.
    # Both classes use neutral random names in one directory, so neither the input
    # directory nor a filename reveals the expected answer.
    corpus = tmp_path / "mixed"
    corpus.mkdir()
    output = str(tmp_path / "mixed_results.json")
    trace = str(tmp_path / "svd_trace.txt")

    sr = 16000
    t = np.linspace(0.0, 1.0, sr)
    rng = np.random.default_rng(secrets.randbits(128))
    expected = {}

    for _ in range(3):
        clean = (rng.standard_normal(sr) * 0.1).astype(np.float32)
        clean_name = f"{uuid.uuid4().hex}.wav"
        wavfile.write(corpus / clean_name, sr, clean)
        expected[clean_name] = "clean"

        phase1, phase2 = rng.uniform(0.0, 2.0 * np.pi, size=2)
        hum = (0.5 * np.sin(2.0 * np.pi * 60.0 * t + phase1) +
               0.5 * np.sin(2.0 * np.pi * 120.0 * t + phase2))
        corrupted = (clean + hum).astype(np.float32)
        corrupted_name = f"{uuid.uuid4().hex}.wav"
        wavfile.write(corpus / corrupted_name, sr, corrupted)
        expected[corrupted_name] = "corrupted"

    result = run_detector(
        str(corpus),
        output,
        {
            "PYTHONPATH": "/tmp" + (":" + os.environ["PYTHONPATH"] if os.environ.get("PYTHONPATH") else ""),
            "DETECTOR_SVD_TRACE": trace,
        },
    )
    assert result.returncode == 0, f"Detector failed on randomized mixed corpus:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.isfile(output), "Detector did not create JSON for randomized corpus"

    with open(output, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert isinstance(actual, dict), "Output JSON must be a dictionary"
    assert actual == expected, f"Incorrect randomized-corpus classifications: expected {expected}, got {actual}"

    calls = []
    if os.path.isfile(trace):
        with open(trace, "r", encoding="utf-8") as f:
            calls = [line.strip() for line in f if line.strip()]
    minimum_calls = 2 * len(expected)
    assert len(calls) >= minimum_calls, (
        f"Expected iterative SVD decomposition for every file (at least {minimum_calls} SVD calls), "
        f"but observed only {len(calls)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
