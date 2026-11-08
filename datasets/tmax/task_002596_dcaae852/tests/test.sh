#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import string
import secrets
import subprocess
from pathlib import Path


def test_corpus_exists_and_correct():
    """Check that corpus.txt exists and contains the exact 5 lines."""
    corpus_path = "/home/user/corpus.txt"
    assert os.path.exists(corpus_path), f"File {corpus_path} does not exist."

    expected_lines = [
        "Deploying a machine learning model to production is hard.",
        "Deep learning models require a lot of data.",
        "We are learning how to deploy deep neural networks.",
        "The deployment of a deep learning model is a critical step.",
        "Data science involves analyzing data to find patterns."
    ]

    with open(corpus_path, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {corpus_path} do not match the expected 5 lines."


def test_script_exists():
    """Check that the bash script exists and is a regular file."""
    script_path = "/home/user/extract_similar.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Script {script_path} is not a regular file."


def test_top_matches_exists_and_correct():
    """Check that top_matches.txt exists and contains the correct sorted output."""
    matches_path = "/home/user/top_matches.txt"
    assert os.path.exists(matches_path), f"File {matches_path} does not exist."

    expected_lines = [
        "The deployment of a deep learning model is a critical step.",
        "Deep learning models require a lot of data.",
        "Deploying a machine learning model to production is hard."
    ]

    with open(matches_path, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {matches_path} do not match the expected top 3 matches."


def tokenize(text):
    cleaned = re.sub(r"[^a-z ]", "", text.lower())
    return cleaned.split()


def expected_top(lines, target):
    target_words = set(tokenize(target))
    ranked = []
    for index, line in enumerate(lines):
        score = len(target_words.intersection(tokenize(line)))
        ranked.append((-score, index, line))
    ranked.sort(key=lambda item: (item[0], item[1]))
    return [item[2] for item in ranked[:3]]


def test_script_behavior_on_unseen_input(tmp_path):
    """Execute the submitted script on unseen data and verify tokenization, scoring, and stable sorting."""
    alphabet = string.ascii_lowercase

    def random_word():
        return "".join(secrets.choice(alphabet) for _ in range(14))

    words = []
    while len(words) < 3:
        candidate = random_word()
        if candidate not in words:
            words.append(candidate)
    first, second, third = words

    lines = [
        f"Prelude :: {first.upper()} !! {second} {second} -- keep  TWO spaces",
        f"{third} ... {first} ? untouched\tTAB",
        f"{second}; {third.upper()} -- original #3",
        f"winner {first} {second.upper()} {third} deluxe",
        "no overlaps here"
    ]
    target = f"{first.upper()}, {first}!!! {second}... {third}"
    expected = expected_top(lines, target)

    input_path = tmp_path / "unseen_corpus.txt"
    input_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    output_path = Path("/home/user/top_matches.txt")
    previous_output = output_path.read_bytes() if output_path.exists() else None
    try:
        if output_path.exists():
            output_path.unlink()

        result = subprocess.run(
            ["bash", "/home/user/extract_similar.sh", str(input_path), target],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script exited with status {result.returncode}. stderr: {result.stderr}"
        )
        assert output_path.exists(), "Script did not generate /home/user/top_matches.txt."
        actual = output_path.read_text(encoding="utf-8").splitlines()
        assert actual == expected, f"Unexpected output for unseen corpus: {actual!r}; expected {expected!r}"
    finally:
        if previous_output is None:
            if output_path.exists():
                output_path.unlink()
        else:
            output_path.write_bytes(previous_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
