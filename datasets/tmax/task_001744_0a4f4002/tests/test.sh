#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid

import numpy as np
import pandas as pd


def test_detector_script_exists_and_executable():
    script_path = "/home/user/detector.py"
    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK) or os.access(script_path, os.R_OK), f"Script at {script_path} must be readable/executable"


def test_adversarial_corpus():
    script_path = "/home/user/detector.py"
    clean_corpus = "/app/test_corpus/clean"
    evil_corpus = "/app/test_corpus/evil"

    assert os.path.exists(clean_corpus), f"Missing clean corpus dir: {clean_corpus}"
    assert os.path.exists(evil_corpus), f"Missing evil corpus dir: {evil_corpus}"

    clean_batches = sorted([os.path.join(clean_corpus, d) for d in os.listdir(clean_corpus) if os.path.isdir(os.path.join(clean_corpus, d))])
    evil_batches = sorted([os.path.join(evil_corpus, d) for d in os.listdir(evil_corpus) if os.path.isdir(os.path.join(evil_corpus, d))])

    assert len(clean_batches) > 0, "No clean batches found in test corpus."
    assert len(evil_batches) > 0, "No evil batches found in test corpus."

    # Present every fixed batch through an opaque path that does not disclose its label.
    with tempfile.TemporaryDirectory(prefix="detector_eval_") as staged_root:
        staged_clean = []
        staged_evil = []
        for source in clean_batches:
            destination = os.path.join(staged_root, uuid.uuid4().hex)
            shutil.copytree(source, destination)
            staged_clean.append(destination)
        for source in evil_batches:
            destination = os.path.join(staged_root, uuid.uuid4().hex)
            shutil.copytree(source, destination)
            staged_evil.append(destination)

        clean_failed = []
        for batch in staged_clean:
            result = subprocess.run(["python3", script_path, batch], capture_output=True)
            if result.returncode != 0:
                clean_failed.append(os.path.basename(batch))

        evil_bypassed = []
        for batch in staged_evil:
            result = subprocess.run(["python3", script_path, batch], capture_output=True)
            if result.returncode != 1:
                evil_bypassed.append(os.path.basename(batch))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_batches)} clean modified (rejected instead of accepted): {', '.join(clean_failed)}")
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_batches)} evil bypassed (accepted instead of rejected): {', '.join(evil_bypassed)}")

    assert not error_messages, " | ".join(error_messages)


def test_fresh_opaque_batches():
    script_path = "/home/user/detector.py"
    rng = np.random.default_rng()
    chooser = secrets.SystemRandom()
    labels = [False] * 10 + [True] * 10
    chooser.shuffle(labels)

    failures = []
    with tempfile.TemporaryDirectory(prefix="detector_unseen_") as root:
        cases = []
        for anomalous in labels:
            batch = os.path.join(root, uuid.uuid4().hex)
            os.makedirs(batch)
            n = 100
            ids = np.arange(1, n + 1)
            mu_a, sig_a = 12.5, 1.5
            mu_b, sig_b = -4.2, 0.8
            mu_c, sig_c = 100.0, 5.0

            if anomalous:
                shifted = chooser.choice(["A", "B", "C"])
                if shifted == "A":
                    mu_a += 3 * sig_a
                elif shifted == "B":
                    mu_b += 3 * sig_b
                else:
                    mu_c += 3 * sig_c

            readings = pd.DataFrame({
                "id": ids,
                "Sensor_A": rng.normal(mu_a, sig_a, n),
                "Sensor_B": rng.normal(mu_b, sig_b, n),
            })
            metadata = pd.DataFrame({
                "id": ids,
                "Sensor_C": rng.normal(mu_c, sig_c, n),
            })
            readings.to_csv(os.path.join(batch, "readings.csv"), index=False)
            metadata.to_csv(os.path.join(batch, "metadata.csv"), index=False)
            cases.append((batch, 1 if anomalous else 0))

        # Labels and invocation order are randomized, and no path contains a class name.
        chooser.shuffle(cases)
        for batch, expected in cases:
            result = subprocess.run(["python3", script_path, batch], capture_output=True)
            if result.returncode != expected:
                failures.append(f"{os.path.basename(batch)} expected exit {expected}, got {result.returncode}")

    assert not failures, "Fresh unseen batch failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
