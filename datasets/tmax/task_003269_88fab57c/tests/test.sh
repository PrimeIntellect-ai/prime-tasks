#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import stat
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
import yaml
from scipy.stats import gaussian_kde

CLASSIFIER = "/home/user/pipeline/classifier.py"


def test_config_yaml_fixed():
    config_path = "/home/user/pipeline/config.yaml"
    assert os.path.isfile(config_path), f"Configuration file {config_path} does not exist."

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    assert config is not None, "Config file is empty or invalid YAML."
    assert config.get("redis_host") == "localhost", f"redis_host should be localhost, got {config.get('redis_host')}"
    assert config.get("redis_port") == 6380, f"redis_port should be 6380, got {config.get('redis_port')}"
    assert config.get("metrics_url") == "http://localhost:9090/report", f"metrics_url should be http://localhost:9090/report, got {config.get('metrics_url')}"


def test_classifier_exists():
    assert os.path.isfile(CLASSIFIER), f"Classifier script {CLASSIFIER} was not created."
    assert stat.S_ISREG(os.lstat(CLASSIFIER).st_mode), "Classifier must be a regular file, not a symlink."
    assert os.path.getsize(CLASSIFIER) > 0, "Classifier script is empty."


def test_classifier_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.json")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run(["python3", CLASSIFIER, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (expected accept/exit code 0). Offending files: {', '.join(failed_files)}"


def test_classifier_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.json")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run(["python3", CLASSIFIER, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected reject/exit code 1). Offending files: {', '.join(failed_files)}"


def expected_classification(values):
    kde = gaussian_kde(np.asarray(values, dtype=float))
    mass = float(kde.integrate_box_1d(-2.0, 2.0))
    return 1 if mass > 0.05 else 0


def test_classifier_on_hidden_path_independent_inputs():
    # The seed and pathname are created only after the agent has finished. Every
    # case is written to the same path, so its label cannot be inferred from the
    # directory or filename.
    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)
    cases = []

    for _ in range(8):
        n = int(rng.integers(180, 281))
        values = rng.normal(rng.uniform(4.8, 6.8), rng.uniform(0.35, 0.9), n)
        cases.append(values.tolist())

    for _ in range(8):
        n = int(rng.integers(180, 281))
        count_near_zero = int(round(n * rng.uniform(0.20, 0.42)))
        values = np.concatenate([
            rng.normal(rng.uniform(-0.7, 0.7), rng.uniform(0.18, 0.6), count_near_zero),
            rng.normal(rng.uniform(4.8, 6.8), rng.uniform(0.35, 0.9), n - count_near_zero),
        ])
        rng.shuffle(values)
        cases.append(values.tolist())

    expected = [expected_classification(values) for values in cases]
    assert 0 in expected and 1 in expected, "Verifier failed to generate both classifications."

    order = list(range(len(cases)))
    random.Random(seed ^ 0x9E3779B97F4A7C15).shuffle(order)

    with tempfile.TemporaryDirectory(prefix="classifier-check-") as directory:
        input_path = os.path.join(directory, uuid.uuid4().hex)
        for index in order:
            with open(input_path, "w") as f:
                json.dump(cases[index], f)

            result = subprocess.run(
                ["python3", CLASSIFIER, input_path],
                capture_output=True,
                timeout=30,
            )
            assert result.returncode == expected[index], (
                f"Classifier returned {result.returncode}, expected {expected[index]} "
                f"for a generated input whose Gaussian-KDE mass determines the label. "
                f"stderr: {result.stderr.decode(errors='replace')}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
