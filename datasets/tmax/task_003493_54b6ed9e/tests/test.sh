#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import uuid
import pytest

BINARY_PATH = "/home/user/validator/target/release/validator"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_validator(filepath):
    return subprocess.run(
        [BINARY_PATH, filepath],
        capture_output=True,
        timeout=10,
    )


def test_validator_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Validator binary not found at {BINARY_PATH}. Did you compile it in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"Validator binary at {BINARY_PATH} is not executable."


def test_clean_corpus_accepted():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Validator binary not found.")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(('.yaml', '.yml'))]
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = run_validator(filepath)
        if result.returncode != 0:
            failed_files.append(filename)

    assert len(failed_files) == 0, (
        f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (modified/flagged). "
        f"Offending files: {', '.join(failed_files)}"
    )


def test_evil_corpus_rejected():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Validator binary not found.")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(('.yaml', '.yml'))]
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = run_validator(filepath)
        if result.returncode == 0:
            failed_files.append(filename)

    assert len(failed_files) == 0, (
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed the check (were accepted). "
        f"Offending files: {', '.join(failed_files)}"
    )


def test_generated_hidden_manifests():
    token = secrets.token_hex(8)
    clean_pod = f"""apiVersion: v1
kind: Pod
metadata:
  name: pod-{token}
spec:
  containers:
    - name: app
      image: nginx
"""
    false_pod = f"""apiVersion: v1
kind: Pod
metadata:
  name: pod-false-{token}
spec:
  hostNetwork: false
  containers:
    - name: app
      image: nginx
"""
    evil_pod = f"""apiVersion: v1
kind: Pod
metadata:
  name: pod-block-{token}
spec:
  containers:
    - name: app
      image: nginx
  hostNetwork: true
"""
    evil_flow_pod = f"""apiVersion: v1
kind: Pod
metadata: {{name: pod-flow-{token}}}
spec: {{containers: [{{name: app, image: nginx}}], hostNetwork: true}}
"""
    clean_deployment = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-{token}
spec:
  selector:
    matchLabels:
      app: demo-{token}
  template:
    metadata:
      labels:
        app: demo-{token}
    spec:
      hostNetwork: false
      containers:
        - name: app
          image: nginx
"""
    evil_deployment = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-block-{token}
spec:
  selector:
    matchLabels:
      app: blocked-{token}
  template:
    metadata:
      labels:
        app: blocked-{token}
    spec:
      containers:
        - name: app
          image: nginx
      hostNetwork: true
"""
    decoy_configmap = f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: config-{token}
data:
  hostNetwork: "true"
  note: "This is configuration data, not a pod spec"
"""

    cases = [
        (clean_pod, False),
        (false_pod, False),
        (evil_pod, True),
        (evil_flow_pod, True),
        (clean_deployment, False),
        (evil_deployment, True),
        (decoy_configmap, False),
        (decoy_configmap + "---\n" + clean_pod, False),
        (clean_pod + "---\n" + evil_deployment, True),
        (evil_pod + "---\n" + clean_deployment, True),
    ]
    secrets.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"validator-{uuid.uuid4().hex}-") as directory:
        for manifest, should_reject in cases:
            filepath = os.path.join(directory, f"{uuid.uuid4().hex}.yaml")
            with open(filepath, "w", encoding="utf-8") as manifest_file:
                manifest_file.write(manifest)

            result = run_validator(filepath)
            rejected = result.returncode != 0
            if rejected != should_reject:
                failures.append(
                    f"{os.path.basename(filepath)} expected "
                    f"{'rejection' if should_reject else 'acceptance'}, got exit {result.returncode}"
                )

    assert not failures, "Generated manifest checks failed: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
