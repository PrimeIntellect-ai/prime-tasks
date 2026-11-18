#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
from collections import Counter, defaultdict


def expected_outputs(lines):
    n_documents = 0
    document_frequency = defaultdict(int)
    outputs = []

    for line in lines:
        n_documents += 1
        tokens = line.lower().split()
        counts = Counter(tokens)

        for token in counts:
            document_frequency[token] += 1

        if not tokens:
            outputs.append("0.0000")
            continue

        length = len(tokens)
        squared_norm = 0.0
        for token, count in counts.items():
            tf = count / length
            idf = math.log(n_documents / document_frequency[token]) + 1.0
            weight = tf * idf
            squared_norm += weight * weight

        outputs.append(f"{math.sqrt(squared_norm):.4f}")

    return outputs


def run_agent(lines, case_name):
    agent_script = "/home/user/online_tfidf.py"
    input_text = "\n".join(lines) + "\n"
    proc = subprocess.run(
        ["python3", agent_script],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode == 0, f"Agent script failed on {case_name}:\n{proc.stderr}"

    actual = proc.stdout.splitlines()
    assert len(actual) == len(lines), (
        f"Wrong output line count on {case_name}: expected {len(lines)}, "
        f"got {len(actual)}. Output:\n{proc.stdout}"
    )
    for value in actual:
        assert re.fullmatch(r"(?:0|[1-9][0-9]*)\.[0-9]{4}", value), (
            f"Output is not a floating-point value with exactly four decimals: {value!r}"
        )

    expected = expected_outputs(lines)
    assert actual == expected, (
        f"Mismatch on {case_name}.\nInput lines: {lines!r}\n"
        f"Expected: {expected!r}\nGot: {actual!r}\nStderr: {proc.stderr}"
    )


def test_transcription_and_features_exist():
    transcription_path = "/home/user/transcription.txt"
    features_path = "/home/user/features.txt"

    assert os.path.isfile(transcription_path), f"Missing transcription file: {transcription_path}"
    assert os.path.isfile(features_path), f"Missing features file: {features_path}"

    with open(transcription_path, "r") as f:
        transcription_lines = f.readlines()
    with open(features_path, "r") as f:
        features_lines = f.readlines()

    assert len(transcription_lines) == len(features_lines), (
        f"Line count mismatch: transcription has {len(transcription_lines)} lines, "
        f"but features has {len(features_lines)} lines."
    )


def test_online_tfidf_fuzz_equivalence():
    agent_script = "/home/user/online_tfidf.py"
    assert os.path.isfile(agent_script), f"Missing agent script: {agent_script}"

    run_agent(
        [
            "",
            "Alpha alpha BETA",
            "",
            "beta gamma",
            "GAMMA gamma alpha",
            "   ",
            "alpha",
        ],
        "fixed causal and empty-line case",
    )

    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    vocabulary = ["alpha", "BETA", "Gamma", "delta", "Echo", "x1", "Token"]

    for case_idx in range(100):
        lines = []
        for _ in range(rng.randint(1, 50)):
            words = []
            for _ in range(rng.randint(0, 20)):
                if rng.random() < 0.75:
                    word = rng.choice(vocabulary)
                    word = "".join(c.upper() if rng.random() < 0.5 else c.lower() for c in word)
                else:
                    word = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 12)))
                words.append(word)

            if not words:
                line = rng.choice(["", " ", "   ", "\t", " \t "])
            else:
                line = words[0]
                for word in words[1:]:
                    line += rng.choice([" ", "  ", "\t", " \t "]) + word
                if rng.random() < 0.3:
                    line = rng.choice([" ", "\t", "  "]) + line
                if rng.random() < 0.3:
                    line += rng.choice([" ", "\t", "  "])
            lines.append(line)

        run_agent(lines, f"fuzz case {case_idx} (seed {seed})")


def test_features_are_generated_by_online_script():
    transcription_path = "/home/user/transcription.txt"
    features_path = "/home/user/features.txt"
    agent_script = "/home/user/online_tfidf.py"

    with open(transcription_path, "rb") as f:
        transcription = f.read()
    with open(features_path, "rb") as f:
        features = f.read()

    proc = subprocess.run(
        ["python3", agent_script],
        input=transcription,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Agent script failed on transcription:\n{proc.stderr.decode(errors='replace')}"
    assert proc.stdout == features, (
        "features.txt does not exactly match online_tfidf.py output for transcription.txt"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
