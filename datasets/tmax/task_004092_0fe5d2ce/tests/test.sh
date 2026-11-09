#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/filter_artifacts.sh"
TARGET_METRIC = "f1_score"


def test_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_clean_corpus_accepted():
    script_path = SCRIPT_PATH
    clean_dir = "/app/clean"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    if not clean_files:
        clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([script_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0): {', '.join(failed_files)}"


def test_evil_corpus_rejected():
    script_path = SCRIPT_PATH
    evil_dir = "/app/evil"

    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    if not evil_files:
        evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([script_path, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed detection (exit code == 0): {', '.join(failed_files)}"


def test_unseen_generated_json_validation():
    token = secrets.token_hex(8)
    valid_objects = [
        {"experiment_id": secrets.randbelow(1000000), "metric": TARGET_METRIC,
         "model_path": f"models/{token}/model_v2-bin"},
        {"metric": TARGET_METRIC, "model_path": f"root/{token}/A1_b-2/checkpoint",
         "extra": {"created_by": "verifier"}},
        {"metric": TARGET_METRIC, "model_path": f"/{token}/nested/path"},
    ]

    invalid_objects = [
        {"metric": TARGET_METRIC + "_other", "model_path": f"models/{token}/model"},
        {"metric": "F1_score", "model_path": f"models/{token}/model"},
        {"metric": " " + TARGET_METRIC, "model_path": f"models/{token}/model"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/../secret"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x;y"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x|y"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x&y"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x$HOME"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x`id`"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/two words"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x\\y"},
        {"metric": TARGET_METRIC, "model_path": f"models/{token}/x*y"},
        {"model_path": f"models/{token}/model"},
        {"metric": TARGET_METRIC},
        {"metric": None, "model_path": f"models/{token}/model"},
        {"metric": TARGET_METRIC, "model_path": None},
        {"metric": TARGET_METRIC, "model_path": 123},
        [TARGET_METRIC, f"models/{token}/model"],
        "not-an-object",
    ]
    malformed_documents = [
        "{",
        '{"metric":"%s","model_path":"safe/path",}' % TARGET_METRIC,
        "this is not json",
    ]

    cases = []
    for obj in valid_objects:
        cases.append((json.dumps(obj), 0))
    for obj in invalid_objects:
        cases.append((json.dumps(obj), 1))
    for document in malformed_documents:
        cases.append((document, 1))
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="artifact-verifier-") as directory:
        paths = []
        for document, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(document)
            paths.append((path, expected))

        random.SystemRandom().shuffle(paths)
        for path, expected in paths:
            try:
                result = subprocess.run([SCRIPT_PATH, path], capture_output=True, timeout=5)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue
            if actual != expected:
                failures.append(
                    f"{os.path.basename(path)} returned {actual}, expected {expected}"
                )

    assert not failures, "Generated validation failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
