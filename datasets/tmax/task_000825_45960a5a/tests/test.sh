#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/classify.sh"


def run_script(*args):
    return subprocess.run(
        ["bash", SCRIPT_PATH, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), f"Script {SCRIPT_PATH} cannot be read/executed."


def test_hidden_corpus_classification():
    hidden_clean_dir = "/app/hidden_corpus/clean"
    hidden_evil_dir = "/app/hidden_corpus/evil"

    clean_files = glob.glob(os.path.join(hidden_clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(hidden_evil_dir, "*.csv"))

    assert len(clean_files) > 0, f"No clean files found in {hidden_clean_dir}."
    assert len(evil_files) > 0, f"No evil files found in {hidden_evil_dir}."

    clean_failed = []
    evil_failed = []

    for f in clean_files:
        result = run_script(f)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            clean_failed.append(os.path.basename(f))

    for f in evil_files:
        result = run_script(f)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "EVIL":
            evil_failed.append(os.path.basename(f))

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")

    assert not error_messages, " | ".join(error_messages)


def make_csv(path, beta_values):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_alpha", "sensor_beta", "sensor_gamma"])
        for i, beta in enumerate(beta_values):
            writer.writerow([f"{i / 10:.1f}", 35 + (i % 11), beta, 780 + (i % 41)])


def test_generated_path_independent_classification_and_exact_threshold():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="classifier_inputs_") as directory:
        cases = []

        # Explicitly exercise both sides of the exact strict threshold.
        cases.append([50, 75, 149, 150, 100])
        cases.append([50, 75, 151, 100])
        cases.append([150])
        cases.append([151])

        # Generate additional cases at verification time with anomalies in
        # unpredictable rows and labels that are derived from their contents.
        for _ in range(36):
            values = [rng.randint(50, 150) for _ in range(rng.randint(3, 35))]
            if rng.randrange(2):
                values[rng.randrange(len(values))] = rng.randint(151, 180)
            cases.append(values)

        rng.shuffle(cases)
        generated = []
        for values in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            make_csv(path, values)
            generated.append((path, "EVIL" if any(v > 150 for v in values) else "CLEAN"))

        assert any(expected == "CLEAN" for _, expected in generated)
        assert any(expected == "EVIL" for _, expected in generated)

        for path, expected in generated:
            result = run_script(path)
            assert result.returncode == 0, f"Nonzero exit code for valid input {path}: {result.returncode}"
            assert result.stdout == expected + "\n", f"Expected exactly {expected!r} for {path}, got {result.stdout!r}"


def test_requires_exactly_one_argument():
    with tempfile.TemporaryDirectory(prefix="classifier_arity_") as directory:
        path = os.path.join(directory, secrets.token_hex(12) + ".csv")
        make_csv(path, [50, 100, 150])

        no_args = run_script()
        two_args = run_script(path, path)

        assert no_args.stdout.strip() not in {"CLEAN", "EVIL"}, "Script classified input when called with no argument"
        assert two_args.stdout.strip() not in {"CLEAN", "EVIL"}, "Script accepted more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
