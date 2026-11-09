#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import string
import pytest
from transformers import AutoTokenizer


def compute_wer(reference, hypothesis):
    ref_words = reference.split()
    hyp_words = hypothesis.split()

    if len(ref_words) == 0:
        return float('inf')

    # Levenshtein distance for words
    d = [[0] * (len(hyp_words) + 1) for _ in range(len(ref_words) + 1)]
    for i in range(len(ref_words) + 1):
        d[i][0] = i
    for j in range(len(hyp_words) + 1):
        d[0][j] = j

    for i in range(1, len(ref_words) + 1):
        for j in range(1, len(hyp_words) + 1):
            if ref_words[i-1] == hyp_words[j-1]:
                cost = 0
            else:
                cost = 1
            d[i][j] = min(
                d[i-1][j] + 1,      # deletion
                d[i][j-1] + 1,      # insertion
                d[i-1][j-1] + cost  # substitution
            )

    return d[len(ref_words)][len(hyp_words)] / float(len(ref_words))


def clean_transcript(text):
    text = text.lower()
    text = text.translate(str.maketrans('', '', string.punctuation))
    text = re.sub(r'\b(?:um|uh|like)\b', '', text)
    return ' '.join(text.split())


def normalize_raw_for_wer(text):
    text = text.lower()
    text = text.translate(str.maketrans('', '', string.punctuation))
    return ' '.join(text.split())


def test_final_state():
    log_path = "/home/user/experiment_log.json"
    assert os.path.exists(log_path), f"Experiment log file {log_path} was not created."

    with open(log_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {log_path} does not contain valid JSON.")

    expected_keys = {"raw_transcript", "cleaned_text", "total_tokens", "chunk_count"}
    assert expected_keys.issubset(data.keys()), f"JSON is missing required keys. Expected {expected_keys}, found {set(data.keys())}."

    raw_transcript = data["raw_transcript"]
    assert isinstance(raw_transcript, str), "The 'raw_transcript' value must be a string."

    agent_cleaned = data["cleaned_text"]
    assert isinstance(agent_cleaned, str), "The 'cleaned_text' value must be a string."

    ground_truth_raw = "We collected seventy two data points, um, and found a high variance in the quarterly metrics. Uh, the standard deviation was roughly four point five, like, which indicates significant outliers. We should probably review the logging pipeline to ensure data integrity."
    raw_wer = compute_wer(
        normalize_raw_for_wer(ground_truth_raw),
        normalize_raw_for_wer(raw_transcript),
    )
    assert raw_wer <= 0.15, f"Raw transcript Word Error Rate (WER) is {raw_wer:.4f}, which exceeds the maximum allowed threshold of 0.15."

    recomputed_cleaned = clean_transcript(raw_transcript)
    assert agent_cleaned == recomputed_cleaned, "The 'cleaned_text' value does not result from applying the required cleaning rules to 'raw_transcript'."

    ground_truth_cleaned = "we collected seventy two data points and found a high variance in the quarterly metrics the standard deviation was roughly four point five which indicates significant outliers we should probably review the logging pipeline to ensure data integrity"

    wer = compute_wer(ground_truth_cleaned, agent_cleaned)
    assert wer <= 0.15, f"Word Error Rate (WER) is {wer:.4f}, which exceeds the maximum allowed threshold of 0.15."

    total_tokens = data["total_tokens"]
    chunk_count = data["chunk_count"]

    assert isinstance(total_tokens, int), "The 'total_tokens' value must be an integer."
    assert isinstance(chunk_count, int), "The 'chunk_count' value must be an integer."

    expected_chunk_count = total_tokens // 15
    assert chunk_count == expected_chunk_count, f"Invalid chunk_count: expected {expected_chunk_count} (total_tokens // 15), got {chunk_count}."

    tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")
    recomputed_total_tokens = len(tokenizer.encode(agent_cleaned, add_special_tokens=False))
    assert total_tokens == recomputed_total_tokens, f"Invalid total_tokens: expected {recomputed_total_tokens} from bert-base-uncased tokenization, got {total_tokens}."
TEST_EOF

install_ok=1
if ! python3 -c 'import transformers' >/dev/null 2>&1; then
    if ! pip3 install --quiet --disable-pip-version-check 'transformers>=4.30,<5'; then
        install_ok=0
    fi
fi

if [ "$install_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
