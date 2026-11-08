#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/validate_deployment.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
DEPLOYMENTS_DIR = "/home/user/deployments"
IMAGES_DIR = "/home/user/images"
AUTHORITATIVE_CLUSTER_ID = "VMC-992-KAPPA"

def run_validator(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True
    )

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), f"Script at {SCRIPT_PATH} is not readable/executable"

def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True
        )
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            bypassed.append(filename)

    assert not bypassed, f"{len(bypassed)} out of {len(evil_files)} evil files bypassed validation: {bypassed}"

def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed = []
    side_effect_failures = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)

        with open(filepath, 'r') as f:
            config = json.load(f)

        service_name = config.get("service_name")
        vm_image_path = config.get("vm_image_path")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True
        )

        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            failed.append(filename)
            continue

        # Verify side effects
        service_dir = os.path.join(DEPLOYMENTS_DIR, service_name)
        symlink_path = os.path.join(service_dir, "latest")
        expected_target = os.path.normpath(os.path.join(IMAGES_DIR, vm_image_path))

        if not os.path.isdir(service_dir):
            side_effect_failures.append(f"{filename}: directory {service_dir} missing")
            continue

        if not os.path.islink(symlink_path):
            side_effect_failures.append(f"{filename}: symlink {symlink_path} missing")
            continue

        actual_target = os.readlink(symlink_path)
        if actual_target != expected_target:
            side_effect_failures.append(f"{filename}: symlink points to {actual_target}, expected {expected_target}")

    assert not failed, f"{len(failed)} out of {len(clean_files)} clean files were incorrectly rejected: {failed}"
    assert not side_effect_failures, f"Side effect validation failed for clean files: {side_effect_failures}"

def test_generated_path_neutral_configurations():
    token = uuid.uuid4().hex
    request_dir = tempfile.mkdtemp(prefix="requests_", dir="/tmp")

    ordinary_rel = f"generated_{token}/disk.qcow2"
    ordinary_abs = os.path.join(IMAGES_DIR, ordinary_rel)
    os.makedirs(os.path.dirname(ordinary_abs), exist_ok=True)
    with open(ordinary_abs, "wb") as f:
        f.write(b"test image")

    outside_dir = tempfile.mkdtemp(prefix="storage_", dir="/tmp")
    outside_image = os.path.join(outside_dir, "disk.qcow2")
    with open(outside_image, "wb") as f:
        f.write(b"outside image")

    escape_link_name = f"generated_link_{token}"
    escape_link = os.path.join(IMAGES_DIR, escape_link_name)
    os.symlink(outside_dir, escape_link)

    def config(port, image_path, cluster_id):
        return {
            "service_name": f"svc-{uuid.uuid4().hex}",
            "vnc_port": port,
            "vm_image_path": image_path,
            "cluster_id": cluster_id,
        }

    cases = [
        (True, config(5900, ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (True, config(5999, ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5899, ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (False, config(6000, ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (False, config("5900", ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900.0, ordinary_rel, AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900, ordinary_rel, "VMC-992-KAPPB")),
        (False, config(5900, ordinary_rel, AUTHORITATIVE_CLUSTER_ID + " ")),
        (False, config(5900, f"../{os.path.basename(outside_dir)}/disk.qcow2", AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900, ordinary_abs, AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900, f"{escape_link_name}/disk.qcow2", AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900, "", AUTHORITATIVE_CLUSTER_ID)),
        (False, config(5900, ".", AUTHORITATIVE_CLUSTER_ID)),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    for should_accept, data in cases:
        filepath = os.path.join(request_dir, f"{uuid.uuid4().hex}.json")
        with open(filepath, "w") as f:
            json.dump(data, f)

        # Invoke accepted cases twice to verify idempotent preparation.
        attempts = 2 if should_accept else 1
        for attempt in range(attempts):
            result = run_validator(filepath)
            expected_code = 0 if should_accept else 1
            expected_output = "ACCEPT" if should_accept else "REJECT"
            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                failures.append(
                    f"case {data!r}, attempt {attempt + 1}: got code "
                    f"{result.returncode}, stdout {result.stdout!r}, stderr {result.stderr!r}"
                )
                break

        if should_accept:
            service_dir = os.path.join(DEPLOYMENTS_DIR, data["service_name"])
            latest = os.path.join(service_dir, "latest")
            expected_target = os.path.realpath(os.path.join(IMAGES_DIR, data["vm_image_path"]))
            if not os.path.isdir(service_dir):
                failures.append(f"generated accepted case missing directory {service_dir}")
            elif not os.path.islink(latest):
                failures.append(f"generated accepted case missing symlink {latest}")
            elif os.readlink(latest) != expected_target:
                failures.append(
                    f"generated accepted case symlink points to {os.readlink(latest)!r}, "
                    f"expected {expected_target!r}"
                )

    assert not failures, "Generated configuration checks failed:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
