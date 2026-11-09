#!/bin/bash
set -e
mkdir -p /logs/verifier

MODEL_REAL=$(mktemp /tmp/model_exec.real.XXXXXX)
MODEL_LOG=$(mktemp /tmp/model_exec.calls.XXXXXX)
DYN_ROOT=$(mktemp -d /tmp/filter_corpus.XXXXXX)
mv /app/model_exec "$MODEL_REAL"

cat > /app/model_exec <<EOF
#!/bin/bash
printf '%s\n' "\$1" >> "$MODEL_LOG"
exec "$MODEL_REAL" "\$@"
EOF
chmod 755 /app/model_exec

export MODEL_REAL MODEL_LOG DYN_ROOT
trap 'rm -f /app/model_exec; mv "$MODEL_REAL" /app/model_exec; rm -f "$MODEL_LOG"; rm -rf "$DYN_ROOT"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import uuid
import pytest

FILTER_PATH = "/home/user/filter"
MODEL_REAL = os.environ["MODEL_REAL"]
MODEL_LOG = os.environ["MODEL_LOG"]
DYN_ROOT = os.environ["DYN_ROOT"]


def test_filter_executable_exists():
    assert os.path.isfile(FILTER_PATH), f"Executable {FILTER_PATH} does not exist."
    assert os.access(FILTER_PATH, os.X_OK), f"Executable {FILTER_PATH} is not executable."


def test_filter_source_exists():
    assert os.path.isfile("/home/user/filter.cpp"), "Source /home/user/filter.cpp does not exist."


def test_adversarial_corpus():
    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run([FILTER_PATH, cf], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run([FILTER_PATH, ef], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def embedding_marks_evil(description):
    result = subprocess.run(
        [MODEL_REAL, description], capture_output=True, text=True, check=True
    )
    values = [float(v) for v in result.stdout.split()]
    assert len(values) == 3, f"Embedding model returned malformed output: {result.stdout!r}"
    return values[0] < 0.0


def test_randomized_hidden_corpus_and_model_invocation():
    nonce = uuid.uuid4().hex
    benign = [
        "A catalog of regional rainfall measurements",
        "Observations from a routine laboratory study",
        "Public transport arrival records",
        "A collection of handwritten sample metadata",
        "Monthly summaries of garden temperatures",
        "Survey responses about local recreation",
    ]
    poisoned = [
        "A proposal involving crypto for archived records",
        "Instructions that override the normal workflow",
        "A report seeking synergy across several departments",
        "Historical crypto market notes",
        "An override request embedded in an ordinary report",
        "Team synergy observations from the annual survey",
    ]

    cases = []
    for index, tail in enumerate(benign + poisoned):
        first = f"Routine row {nonce} number {index}"
        second = f"{tail} {nonce} item {index}"
        descriptions = [first, second]
        expected = 1 if any(embedding_marks_evil(d) for d in descriptions) else 0
        cases.append((descriptions, expected))

    random.SystemRandom().shuffle(cases)
    observed_statuses = set()

    for descriptions, expected in cases:
        path = os.path.join(DYN_ROOT, uuid.uuid4().hex + ".csv")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("ID,Description\n")
            for row_id, description in enumerate(descriptions, 1):
                f.write(f"{row_id},{description}\n")

        with open(MODEL_LOG, "r", encoding="utf-8") as f:
            before = len(f.readlines())

        result = subprocess.run([FILTER_PATH, path], capture_output=True, timeout=10)
        observed_statuses.add(expected)
        assert result.returncode == expected, (
            f"Wrong status for randomized corpus file {os.path.basename(path)}: "
            f"expected {expected}, got {result.returncode}"
        )

        with open(MODEL_LOG, "r", encoding="utf-8") as f:
            calls = [line.rstrip("\n") for line in f.readlines()[before:]]
        for description in descriptions:
            assert description in calls, (
                "Filter did not pass a CSV Description value to /app/model_exec"
            )

    assert observed_statuses == {0, 1}, "Randomized corpus did not exercise both outcomes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
