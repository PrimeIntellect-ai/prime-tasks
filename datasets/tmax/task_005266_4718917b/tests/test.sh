#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import statistics
import subprocess
import tempfile
import urllib.request
import uuid

import pytest


def test_detector_compiled():
    """Verify that the C++ detector has been compiled and is executable."""
    detector_path = "/app/worker/detector"
    assert os.path.isfile(detector_path), f"{detector_path} binary does not exist. C++ program not compiled."
    assert os.access(detector_path, os.X_OK), f"{detector_path} is not executable."
    with open(detector_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{detector_path} is not a compiled ELF executable."

    source_path = "/app/worker/detector.cpp"
    assert os.path.isfile(source_path), f"{source_path} C++ source does not exist."


def classify_csv(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))

    vectors = [
        (float(r["signal"]), float(r["background"]), float(r["noise"]))
        for r in rows
    ]

    for i in range(len(vectors)):
        for j in range(i + 1, len(vectors)):
            a, b = vectors[i], vectors[j]
            na = math.sqrt(sum(x * x for x in a))
            nb = math.sqrt(sum(x * x for x in b))
            similarity = sum(x * y for x, y in zip(a, b)) / (na * nb)
            if similarity >= 0.999:
                return "ANOMALOUS"

    signals = [v[0] for v in vectors]
    mean = statistics.mean(signals)
    sample_sd = statistics.stdev(signals)
    sem = sample_sd / math.sqrt(len(signals))
    low = mean - 3.29 * sem
    high = mean + 3.29 * sem
    if 50.0 < low or 50.0 > high:
        return "ANOMALOUS"
    return "VALID"


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "signal", "background", "noise"])
        for i, row in enumerate(rows):
            writer.writerow([i, *row])


def run_detector(executable, path, expected):
    result = subprocess.run(
        [executable, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=False, text=True
    )
    assert result.returncode == 0, (
        f"Detector failed for generated input {path}: {result.stderr}"
    )
    assert result.stdout in (expected, expected + "\n"), (
        f"Detector returned {result.stdout!r}, expected exactly {expected!r}"
    )


def call_api(path):
    data = json.dumps({"filepath": path}).encode("utf-8")
    req = urllib.request.Request(
        "http://localhost:5000/validate",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8")).get("status")


def test_generated_unseen_inputs_through_detector_and_pipeline():
    """Exercise the stated rules on unpredictable paths and independently compiled source."""
    source = "/app/worker/detector.cpp"
    deployed = "/app/worker/detector"
    assert os.path.isfile(source), f"{source} C++ source does not exist."

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="detector-verifier-") as workdir:
        rebuilt = os.path.join(workdir, "rebuilt-detector")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, text=True
        )
        assert compile_result.returncode == 0, (
            f"detector.cpp does not compile: {compile_result.stderr}"
        )

        radius = rng.uniform(90.0, 140.0)
        phase = rng.uniform(0.0, 2.0 * math.pi)
        deviations = [-2.0, -1.5, -1.0, -0.5, 0.5, 1.0, 1.5, 2.0]
        rng.shuffle(deviations)

        valid_rows = []
        drift_rows = []
        for i, deviation in enumerate(deviations):
            angle = phase + i * math.pi / 4.0
            background = radius * math.cos(angle)
            noise = radius * math.sin(angle)
            valid_rows.append((50.0 + deviation, background, noise))
            drift_rows.append((58.0 + deviation, background, noise))

        # The first two rows are distinct but proportional, so their cosine
        # similarity is exactly 1 even though their values are not duplicates.
        similarity_rows = [
            (40.0, 30.0, 20.0),
            (80.0, 60.0, 40.0),
            (45.0, radius, 0.0),
            (45.0, 0.0, radius),
            (45.0, -radius, 0.0),
            (45.0, 0.0, -radius),
            (50.0, radius / math.sqrt(2.0), radius / math.sqrt(2.0)),
            (50.0, -radius / math.sqrt(2.0), -radius / math.sqrt(2.0)),
        ]

        generated = []
        for rows in (valid_rows, drift_rows, similarity_rows):
            path = os.path.join(workdir, f"{uuid.uuid4().hex}.csv")
            write_csv(path, rows)
            generated.append(path)

        rng.shuffle(generated)
        observed = set()
        for path in generated:
            expected = classify_csv(path)
            observed.add(expected)
            run_detector(deployed, path, expected)
            run_detector(rebuilt, path, expected)
            assert call_api(path) == expected, (
                f"Pipeline returned the wrong result for generated input {path}"
            )

        assert observed == {"VALID", "ANOMALOUS"}


def test_adversarial_corpus():
    """Verify the data filtering pipeline against the clean and evil corpora."""
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean CSV files found."
    assert len(evil_files) > 0, "No evil CSV files found."

    clean_modified = []
    evil_bypassed = []

    url = "http://localhost:5000/validate"

    # Test Clean Corpus
    for filepath in clean_files:
        data = json.dumps({"filepath": filepath}).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                res = json.loads(response.read().decode('utf-8'))
                if res.get('status') != 'VALID':
                    clean_modified.append(os.path.basename(filepath))
        except Exception:
            clean_modified.append(os.path.basename(filepath))

    # Test Evil Corpus
    for filepath in evil_files:
        data = json.dumps({"filepath": filepath}).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                res = json.loads(response.read().decode('utf-8'))
                if res.get('status') != 'ANOMALOUS':
                    evil_bypassed.append(os.path.basename(filepath))
        except Exception:
            evil_bypassed.append(os.path.basename(filepath))

    error_msg = ""
    if evil_bypassed:
        error_msg += f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}. "
    if clean_modified:
        error_msg += f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}."

    assert not evil_bypassed and not clean_modified, error_msg.strip()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
