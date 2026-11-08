#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import random
import re
import secrets
import shutil
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "classifier.go")
BINARY = "/tmp/classifier_submission"
RESULTS = os.path.join(HOME, "results.json")
DATASET = os.path.join(HOME, "dataset")
CLASSES = ("spam", "ham")


def run_classifier():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd=HOME, text=True, capture_output=True, timeout=20
    )
    assert completed.returncode == 0, (
        "classifier exited unsuccessfully:\n"
        + completed.stdout + "\n" + completed.stderr
    )
    assert os.path.isfile(RESULTS), "The file /home/user/results.json does not exist."
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(
                "The file /home/user/results.json does not contain valid JSON."
            ) from exc


def assert_result_shape(data):
    assert "vocab_size" in data, "The key 'vocab_size' is missing from results.json."
    assert "test_accuracy" in data, "The key 'test_accuracy' is missing from results.json."
    assert isinstance(data["vocab_size"], (int, float)) and not isinstance(data["vocab_size"], bool)
    assert isinstance(data["test_accuracy"], (int, float)) and not isinstance(data["test_accuracy"], bool)
    assert math.isfinite(float(data["vocab_size"]))
    assert math.isfinite(float(data["test_accuracy"]))


def tokenize(text):
    return re.sub(r"[^a-z0-9]", " ", text.lower()).split()


def expected_result():
    train_docs = {c: [] for c in CLASSES}
    counts = {c: collections.Counter() for c in CLASSES}
    vocab = set()

    for cls in CLASSES:
        directory = os.path.join(DATASET, "train", cls)
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            with open(path, "r") as f:
                tokens = tokenize(f.read())
            train_docs[cls].append(tokens)
            counts[cls].update(tokens)
            vocab.update(tokens)

    total_docs = sum(len(train_docs[c]) for c in CLASSES)
    assert total_docs > 0 and all(train_docs[c] for c in CLASSES)
    totals = {c: sum(counts[c].values()) for c in CLASSES}
    priors = {c: len(train_docs[c]) / total_docs for c in CLASSES}

    correct = 0
    tested = 0
    for actual in CLASSES:
        directory = os.path.join(DATASET, "test", actual)
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            with open(path, "r") as f:
                tokens = tokenize(f.read())
            scores = {}
            for cls in CLASSES:
                score = math.log(priors[cls])
                denominator = totals[cls] + len(vocab)
                for token in tokens:
                    if token in vocab:
                        score += math.log((counts[cls][token] + 1) / denominator)
                scores[cls] = score
            predicted = "spam" if scores["spam"] > scores["ham"] else "ham"
            correct += int(predicted == actual)
            tested += 1

    assert tested > 0
    return {"vocab_size": len(vocab), "test_accuracy": correct / tested}


def reset_dataset():
    if os.path.exists(DATASET):
        shutil.rmtree(DATASET)
    for split in ("train", "test"):
        for cls in CLASSES:
            os.makedirs(os.path.join(DATASET, split, cls), exist_ok=True)


def write_doc(split, cls, index, text):
    path = os.path.join(DATASET, split, cls, f"{index}.txt")
    with open(path, "w") as f:
        f.write(text)


def render(tokens, rng):
    if not tokens:
        return ""
    rendered = [t.upper() if rng.randrange(2) else t for t in tokens]
    text = rendered[0]
    for token in rendered[1:]:
        text += rng.choice([" ", "!!!", "---", ",,,", "\n"]) + token
    return text


def assert_matches_oracle(data, expected):
    assert_result_shape(data)
    assert data["vocab_size"] == expected["vocab_size"], (
        f"Expected vocab_size to be {expected['vocab_size']}, got {data['vocab_size']}."
    )
    assert abs(float(data["test_accuracy"]) - expected["test_accuracy"]) <= 1e-12, (
        f"Expected test_accuracy to be {expected['test_accuracy']}, "
        f"got {data['test_accuracy']}."
    )


def test_classifier_program_and_results():
    assert os.path.isfile(SOURCE), "The file /home/user/classifier.go does not exist."
    assert os.path.getsize(SOURCE) > 0, "/home/user/classifier.go is empty."

    built = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd=HOME, text=True, capture_output=True, timeout=60
    )
    assert built.returncode == 0, (
        "classifier.go does not compile:\n" + built.stdout + "\n" + built.stderr
    )

    # Retain the original assertions, but require the compiled program to produce them.
    original = run_classifier()
    assert_result_shape(original)
    assert original["vocab_size"] == 16, (
        f"Expected vocab_size to be 16, got {original['vocab_size']}."
    )
    assert original["test_accuracy"] == 1.0, (
        f"Expected test_accuracy to be 1.0, got {original['test_accuracy']}."
    )

    # Exercise OOV handling and the required ham tie-break with unpredictable tokens.
    rng = random.Random(secrets.randbits(128))
    nonce = secrets.token_hex(6)
    reset_dataset()
    write_doc("train", "spam", 0, f"S{nonce} S{nonce}")
    write_doc("train", "ham", 0, f"H{nonce} H{nonce}")
    write_doc("test", "spam", 0, f"UNKNOWN{nonce}!!!")
    write_doc("test", "ham", 0, f"OTHER{nonce}???")
    expected = expected_result()
    assert_matches_oracle(run_classifier(), expected)

    # Repeated hidden corpora check tokenization, priors, token frequencies,
    # Laplace smoothing, vocabulary construction, and evaluation.
    for trial in range(5):
        reset_dataset()
        vocab_count = rng.randint(6, 11)
        words = [f"w{nonce}{trial}{i}x" for i in range(vocab_count)]

        for cls_index, cls in enumerate(CLASSES):
            for doc_index in range(rng.randint(2, 5)):
                length = rng.randint(5, 13)
                tokens = []
                for _ in range(length):
                    if rng.random() < 0.68:
                        pool = words[cls_index::2] or words
                    else:
                        pool = words
                    tokens.append(rng.choice(pool))
                if cls == "spam" and doc_index == 0:
                    tokens.extend(words)
                write_doc("train", cls, doc_index, render(tokens, rng))

        label_offset = rng.randrange(2)
        for doc_index in range(7):
            actual = CLASSES[(doc_index + label_offset) % 2]
            tokens = [rng.choice(words) for _ in range(rng.randint(2, 8))]
            if rng.random() < 0.7:
                tokens.insert(rng.randrange(len(tokens) + 1), f"oov{nonce}{trial}{doc_index}")
            write_doc("test", actual, doc_index, render(tokens, rng))

        expected = expected_result()
        assert_matches_oracle(run_classifier(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
