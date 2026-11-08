#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
from collections import Counter
from fractions import Fraction

import pytest

SCRIPT = "/home/user/etl_pipeline.py"
TRANSCRIPT = "/home/user/full_transcript.txt"
SAMPLE = "/home/user/stratified_sample.json"


def calculate_wer(reference, hypothesis):
    """Calculate Word Error Rate (WER) using Levenshtein distance at the word level."""
    r = reference.split()
    h = hypothesis.split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]

    for i in range(len(r) + 1):
        for j in range(len(h) + 1):
            if i == 0:
                d[0][j] = j
            elif j == 0:
                d[i][0] = i
            elif r[i - 1] == h[j - 1]:
                d[i][j] = d[i - 1][j - 1]
            else:
                d[i][j] = 1 + min(
                    d[i - 1][j],
                    d[i][j - 1],
                    d[i - 1][j - 1],
                )

    if len(r) == 0:
        return float("inf")
    return d[len(r)][len(h)] / len(r)


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert os.path.exists(SCRIPT), f"ETL script missing: {SCRIPT}"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"ETL script is not a regular file: {SCRIPT}"

    with open(SCRIPT, "rb") as f:
        source = f.read()
    try:
        compile(source, SCRIPT, "exec")
    except SyntaxError as exc:
        pytest.fail(f"ETL script is not valid Python: {exc}")

    # Outputs must be produced by the submitted pipeline, not merely pre-created.
    for path in (TRANSCRIPT, SAMPLE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("ETL script did not finish within 300 seconds.")

    assert result.returncode == 0, (
        f"ETL script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_transcription_accuracy():
    """Test that the transcription accuracy (1.0 - WER) is >= 0.85."""
    ground_truth = "the mathematical foundations of data engineering require careful attention to timestamp alignment and rigorous data stratification when building an etl pipeline one must normalize incoming tokens effectively"
    target_file = TRANSCRIPT

    assert os.path.exists(target_file), f"Transcript file missing: {target_file}"

    with open(target_file, "r") as f:
        predicted = f.read().strip()

    assert predicted, "Transcript is empty."
    assert predicted == predicted.lower(), "Transcript is not lowercase."
    assert re.fullmatch(r"[a-z0-9]+(?: [a-z0-9]+)*", predicted), (
        "Transcript must contain only lowercase alphanumeric words separated by single spaces."
    )

    error = calculate_wer(ground_truth, predicted)
    accuracy = max(0.0, 1.0 - error)

    assert accuracy >= 0.85, f"Transcription accuracy is {accuracy:.2f}, which is below the threshold of 0.85."


def test_cron_job_configured():
    """Test that an active cron entry runs the ETL script at 04:30 AM every day."""
    try:
        cron_check = subprocess.check_output(
            ["crontab", "-l"], stderr=subprocess.DEVNULL
        ).decode("utf-8")
    except subprocess.CalledProcessError:
        cron_check = ""

    # Preserve the original schedule assertion.
    assert "30 4 * * *" in cron_check, "Cron job is not configured correctly. Expected '30 4 * * *' in crontab."

    active_commands = []
    for raw_line in cron_check.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["30", "4", "*", "*", "*"]:
            active_commands.append(fields[5])

    assert active_commands, "No active daily 04:30 cron entry was found."

    invocation = re.compile(
        r"(?:^|(?:&&|;)\s*)"
        r"(?:(?:/usr/bin/env\s+)?(?:\S*/)?python3(?:\.\d+)?\s+)?"
        r"/home/user/etl_pipeline\.py(?:\s|$)"
    )
    assert any(invocation.search(command) for command in active_commands), (
        "The active 04:30 cron entry does not execute /home/user/etl_pipeline.py."
    )


def minimum_stratification_error(full_length_counts, sample_size):
    """Return the minimum L1 distance from exact proportional quotas."""
    total_words = sum(full_length_counts.values())
    quotas = [Fraction(count * sample_size, total_words) for count in full_length_counts.values()]
    dp = {0: Fraction(0)}

    for quota in quotas:
        next_dp = {}
        for allocated, cost in dp.items():
            for amount in range(sample_size - allocated + 1):
                new_total = allocated + amount
                new_cost = cost + abs(Fraction(amount) - quota)
                if new_total not in next_dp or new_cost < next_dp[new_total]:
                    next_dp[new_total] = new_cost
        dp = next_dp

    return dp[sample_size]


def test_stratified_sample():
    """Test that the sample contains transcript words in optimally proportional length strata."""
    sample_file = SAMPLE
    assert os.path.exists(sample_file), f"Stratified sample file missing: {sample_file}"

    with open(sample_file, "r") as f:
        try:
            sample = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Stratified sample file is not valid JSON.")

    # Preserve the original structural assertions.
    assert isinstance(sample, list), "Stratified sample must be a JSON array."
    assert len(sample) == 30, f"Stratified sample must contain exactly 30 words, found {len(sample)}."
    assert all(isinstance(word, str) for word in sample), "All items in the stratified sample must be strings."

    with open(TRANSCRIPT, "r") as f:
        transcript_words = f.read().strip().split()

    assert transcript_words, "Cannot stratify an empty transcript."
    transcript_vocabulary = set(transcript_words)
    assert all(word in transcript_vocabulary for word in sample), (
        "Every sampled word must come from the normalized transcript."
    )

    full_length_counts = Counter(map(len, transcript_words))
    sample_length_counts = Counter(map(len, sample))
    assert set(sample_length_counts).issubset(full_length_counts), (
        "Sample contains a word-length stratum absent from the transcript."
    )

    total_words = len(transcript_words)
    observed_error = sum(
        abs(Fraction(sample_length_counts.get(length, 0)) - Fraction(count * 30, total_words))
        for length, count in full_length_counts.items()
    )
    best_error = minimum_stratification_error(full_length_counts, 30)

    assert observed_error == best_error, (
        "Sample word-length strata are not proportionally matched as closely as possible. "
        f"Observed deviation {float(observed_error):.4f}; minimum is {float(best_error):.4f}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
