#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

BINARY_PATH = "/home/user/telemetry_classifier/bin/classifier"
PROJECT_DIR = "/home/user/telemetry_classifier"
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")
SOURCE_PATH = os.path.join(PROJECT_DIR, "src", "classifier.cpp")
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EXPECTED_THRESHOLD = 42.73


def run_classifier(path, timeout=2):
    return subprocess.run(
        [BINARY_PATH, path], capture_output=True, text=True, timeout=timeout
    )


def test_build_script_rebuilds_classifier_from_scratch():
    assert os.path.isfile(BUILD_SCRIPT), "build.sh is missing"
    assert os.access(BUILD_SCRIPT, os.X_OK), "build.sh is not executable"

    bin_dir = os.path.join(PROJECT_DIR, "bin")
    shutil.rmtree(bin_dir, ignore_errors=True)

    result = subprocess.run(
        [BUILD_SCRIPT], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), "build.sh did not create bin/classifier"
    assert os.access(BINARY_PATH, os.X_OK), "rebuilt classifier is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/classifier is not a compiled ELF binary"


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Did the build script succeed?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."


def test_threshold_was_extracted_into_source():
    with open(SOURCE_PATH, encoding="utf-8") as f:
        source = f.read()
    match = re.search(
        r"^\s*#\s*define\s+THRESHOLD\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*[fF]?\s*$",
        source,
        re.MULTILINE,
    )
    assert match, "classifier.cpp does not contain a numeric THRESHOLD macro"
    actual = float(match.group(1))
    assert math.isclose(actual, EXPECTED_THRESHOLD, rel_tol=0, abs_tol=1e-6), (
        f"THRESHOLD is {actual}, expected the value extracted from malware_seed.png"
    )


def test_classifier_accuracy():
    assert os.path.isfile(BINARY_PATH), "Binary missing, cannot test accuracy."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        try:
            result = run_classifier(filepath)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_bypassed.append(os.path.basename(filepath))
        except subprocess.TimeoutExpired:
            evil_bypassed.append(f"{os.path.basename(filepath)} (timeout)")
        except Exception as e:
            evil_bypassed.append(f"{os.path.basename(filepath)} (error: {e})")

    for filepath in clean_files:
        try:
            result = run_classifier(filepath)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_modified.append(os.path.basename(filepath))
        except subprocess.TimeoutExpired:
            clean_modified.append(f"{os.path.basename(filepath)} (timeout)")
        except Exception as e:
            clean_modified.append(f"{os.path.basename(filepath)} (error: {e})")

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:10])}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:10])}")

    assert not evil_bypassed and not clean_modified, "Classifier accuracy failed:\n" + "\n".join(error_messages)


def test_classifier_on_unlabeled_generated_inputs_and_repeated_runs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="classifier-check-") as temp_dir:
        cases = []

        # Copies of corpus contents under neutral randomized paths defeat path-label dispatch.
        for corpus_dir, expected in ((EVIL_CORPUS_DIR, "EVIL"), (CLEAN_CORPUS_DIR, "CLEAN")):
            for entry in os.listdir(corpus_dir):
                source = os.path.join(corpus_dir, entry)
                if os.path.isfile(source):
                    destination = os.path.join(temp_dir, uuid.uuid4().hex + ".dat")
                    shutil.copyfile(source, destination)
                    cases.append((destination, expected))

        # Fresh payloads vary count, signs, whitespace, and totals. Expected answers are
        # independently derived from the generated numeric contents.
        targets = [
            rng.uniform(-30.0, 35.0) for _ in range(12)
        ] + [
            rng.uniform(50.0, 120.0) for _ in range(12)
        ]
        rng.shuffle(targets)

        for target in targets:
            count = rng.randint(2, 9)
            values = [rng.uniform(-15.0, 25.0) for _ in range(count - 1)]
            values.append(target - sum(values))
            rendered = [f"{value:.6f}" for value in values]
            parsed_sum = sum(float(value) for value in rendered)
            assert abs(parsed_sum - EXPECTED_THRESHOLD) > 1.0
            expected = "EVIL" if parsed_sum >= EXPECTED_THRESHOLD else "CLEAN"
            path = os.path.join(temp_dir, uuid.uuid4().hex + ".bin")
            separators = [" ", "\n", "\t", "  \n"]
            with open(path, "w", encoding="ascii") as f:
                for index, value in enumerate(rendered):
                    if index:
                        f.write(rng.choice(separators))
                    f.write(value)
                f.write("\n")
            cases.append((path, expected))

        for path, expected in cases:
            observed = []
            for _ in range(8):
                result = run_classifier(path)
                assert result.returncode == 0, f"classifier exited {result.returncode} for generated input"
                assert result.stderr == "", f"classifier wrote unexpected stderr: {result.stderr!r}"
                assert result.stdout == expected + "\n", (
                    f"generated payload expected {expected}, got {result.stdout!r}"
                )
                observed.append(result.stdout)
            assert len(set(observed)) == 1, "classification changed across identical repeated runs"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
