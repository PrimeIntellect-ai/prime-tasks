#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from fractions import Fraction

import pytest

VENDORED_SCRIPT = "/app/vendored/bash-datakit/validate_csv.sh"
DETECTOR_SCRIPT = "/home/user/detector.sh"
TRAIN_FILE = "/app/data/train.csv"
CLEAN_DIR = "/app/data/clean/"
EVIL_DIR = "/app/data/evil/"


def test_vendored_script_fixed():
    assert os.path.isfile(VENDORED_SCRIPT), f"Vendored script missing: {VENDORED_SCRIPT}"
    with open(VENDORED_SCRIPT, "r") as f:
        content = f.read()
    assert 'print ""' not in content, "Vendored script still contains the bug 'print \"\"'"
    assert 'print $0' in content or 'print' in content, "Vendored script should print the whole line"


def test_vendored_script_functionally_validates_schema():
    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, "schema.csv")
        with open(input_file, "w") as f:
            f.write("user_id,action,geo\n")
            f.write("1,click,US\n")
            f.write("2,scroll\n")
            f.write("3,type,EU,extra\n")
            f.write(",,\n")
            f.write("4,,ASIA\n")
            f.write("\n")

        result = subprocess.run(
            [VENDORED_SCRIPT, input_file], capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.splitlines() == [
            "user_id,action,geo",
            "1,click,US",
            ",,",
            "4,,ASIA",
        ]


def test_detector_script_exists_and_executable():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script missing: {DETECTOR_SCRIPT}"
    assert os.access(DETECTOR_SCRIPT, os.X_OK), f"Detector script is not executable: {DETECTOR_SCRIPT}"


def test_adversarial_corpus():
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith(".csv")]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith(".csv")]

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}"

    clean_modified = []
    evil_bypassed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for cfile in clean_files:
            out_file = os.path.join(tmpdir, "out_clean_" + os.path.basename(cfile))
            result = subprocess.run([DETECTOR_SCRIPT, cfile, out_file], capture_output=True, text=True)
            if result.returncode != 0:
                clean_modified.append((os.path.basename(cfile), "Script failed with non-zero exit code"))
                continue
            if not os.path.exists(out_file):
                clean_modified.append((os.path.basename(cfile), "Output file not created"))
                continue

            with open(cfile, "r") as f:
                original_lines = [line.strip() for line in f if line.strip()]
            with open(out_file, "r") as f:
                output_lines = [line.strip() for line in f if line.strip()]
            if original_lines != output_lines:
                clean_modified.append((os.path.basename(cfile), f"Expected {len(original_lines)} lines, got {len(output_lines)} lines"))

        for efile in evil_files:
            out_file = os.path.join(tmpdir, "out_evil_" + os.path.basename(efile))
            result = subprocess.run([DETECTOR_SCRIPT, efile, out_file], capture_output=True, text=True)
            if result.returncode != 0:
                evil_bypassed.append((os.path.basename(efile), "Script failed with non-zero exit code"))
                continue
            if not os.path.exists(out_file):
                evil_bypassed.append((os.path.basename(efile), "Output file not created"))
                continue

            with open(efile, "r") as f:
                original_lines = [line.strip() for line in f if line.strip()]
            with open(out_file, "r") as f:
                output_lines = [line.strip() for line in f if line.strip()]
            if len(output_lines) != 1 or output_lines[0] != original_lines[0]:
                evil_bypassed.append((os.path.basename(efile), f"Expected 1 header line, got {len(output_lines)} lines"))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join([f"{x[0]} ({x[1]})" for x in evil_bypassed]))
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: " + ", ".join([f"{x[0]} ({x[1]})" for x in clean_modified]))
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle_preserves(training_rows, action, geo):
    actions = {row[0] for row in training_rows}
    geos = {row[1] for row in training_rows}
    total = len(training_rows)
    scores = {}

    for label in (0, 1):
        class_rows = [row for row in training_rows if row[2] == label]
        class_count = len(class_rows)
        assert class_count > 0
        action_count = sum(1 for a, g, y in class_rows if a == action)
        geo_count = sum(1 for a, g, y in class_rows if g == geo)
        scores[label] = (
            Fraction(class_count, total)
            * Fraction(action_count + 1, class_count + len(actions))
            * Fraction(geo_count + 1, class_count + len(geos))
        )

    return scores[1] <= scores[0]


def run_dynamic_case(tmpdir, case_number, training_rows, test_actions, test_geos):
    train_lines = ["user_id,action,geo,is_bot"]
    for index, (action, geo, label) in enumerate(training_rows, 1):
        train_lines.append(f"{case_number}{index},{action},{geo},{label}")
    training_text = "\n".join(train_lines) + "\n"
    with open(TRAIN_FILE, "w") as f:
        f.write(training_text)

    input_file = os.path.join(tmpdir, f"dynamic_{case_number}.csv")
    output_file = os.path.join(tmpdir, f"dynamic_{case_number}_out.csv")
    input_lines = ["user_id,action,geo"]
    expected_lines = ["user_id,action,geo"]

    row_number = 1000 + case_number * 100
    for action in test_actions:
        for geo in test_geos:
            row_number += 1
            line = f"{row_number},{action},{geo}"
            input_lines.append(line)
            if oracle_preserves(training_rows, action, geo):
                expected_lines.append(line)

    # These malformed rows must be removed by schema validation before scoring.
    input_lines.extend([
        f"{row_number + 1},{test_actions[0]}",
        f"{row_number + 2},{test_actions[0]},{test_geos[0]},extra",
    ])
    with open(input_file, "w") as f:
        f.write("\n".join(input_lines) + "\n")

    result = subprocess.run(
        [DETECTOR_SCRIPT, input_file, output_file], capture_output=True, text=True
    )
    assert result.returncode == 0, f"dynamic case {case_number} failed: {result.stderr}"
    assert os.path.isfile(output_file), f"dynamic case {case_number} did not create output"
    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f"dynamic Naive Bayes case {case_number} mismatch\n"
        f"expected: {expected_lines}\nactual: {actual_lines}"
    )
    with open(TRAIN_FILE, "r") as f:
        assert f.read() == training_text, "Detector modified its training data"


def test_detector_retrains_and_applies_laplace_naive_bayes():
    with open(TRAIN_FILE, "rb") as f:
        original_training = f.read()

    suffix = secrets.token_hex(5)
    a, b, c, unseen_a = [f"act_{name}_{suffix}" for name in ("a", "b", "c", "new")]
    x, y, z, unseen_g = [f"geo_{name}_{suffix}" for name in ("x", "y", "z", "new")]

    cases = [
        ([(a, x, 0)] * 4 + [(b, y, 1)] * 4, [a, b, unseen_a], [x, y, unseen_g]),
        ([(a, x, 1)] * 4 + [(b, y, 0)] * 4, [a, b, unseen_a], [x, y, unseen_g]),
        (
            [(a, x, 0), (a, y, 0), (b, x, 0), (c, x, 0), (c, z, 0),
             (b, y, 1), (b, y, 1), (c, z, 1)],
            [a, b, c, unseen_a],
            [x, y, z, unseen_g],
        ),
    ]

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            for number, (rows, actions, geos) in enumerate(cases, 1):
                run_dynamic_case(tmpdir, number, rows, actions, geos)
    finally:
        with open(TRAIN_FILE, "wb") as f:
            f.write(original_training)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
