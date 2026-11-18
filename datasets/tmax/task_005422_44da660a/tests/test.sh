#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

DATASET = '/home/user/dataset.csv'
SOURCE = '/home/user/naive_bayes.cpp'
EXECUTABLE = '/home/user/nb_classifier'
RESULTS = '/home/user/results.txt'
OUTPUT_RE = re.compile(r'Vocab Size: (\d+)\nTest Accuracy: ([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\n?\Z')


def run_program(path):
    proc = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5, check=False
    )
    assert proc.returncode == 0, f"{path} exited with {proc.returncode}: {proc.stderr}"
    match = OUTPUT_RE.fullmatch(proc.stdout)
    assert match is not None, (
        "Program output must contain exactly the two specified lines; got: "
        + repr(proc.stdout)
    )
    vocab = int(match.group(1))
    accuracy = float(match.group(2))
    assert math.isfinite(accuracy) and 0.0 <= accuracy <= 1.0
    return vocab, accuracy, proc.stdout


def reference_metrics(csv_text):
    docs = []
    for line in csv_text.strip().splitlines()[1:]:
        text, label = line.rsplit(',', 1)
        docs.append((text.split(), int(label)))

    split_idx = int(len(docs) * 0.8)
    train = docs[:split_idx]
    test = docs[split_idx:]
    vocab = {token for tokens, _ in train for token in tokens}

    spam_docs = sum(label == 1 for _, label in train)
    ham_docs = len(train) - spam_docs
    assert spam_docs and ham_docs and test

    spam_counts = {}
    ham_counts = {}
    for tokens, label in train:
        counts = spam_counts if label == 1 else ham_counts
        for token in tokens:
            counts[token] = counts.get(token, 0) + 1

    spam_total = sum(spam_counts.values())
    ham_total = sum(ham_counts.values())
    p_spam = math.log(spam_docs / len(train))
    p_ham = math.log(ham_docs / len(train))

    correct = 0
    for tokens, label in test:
        score_spam = p_spam
        score_ham = p_ham
        for token in tokens:
            if token not in vocab:
                continue
            score_spam += math.log((spam_counts.get(token, 0) + 1.0) /
                                   (spam_total + len(vocab)))
            score_ham += math.log((ham_counts.get(token, 0) + 1.0) /
                                  (ham_total + len(vocab)))
        prediction = 1 if score_spam > score_ham else 0
        correct += prediction == label

    return len(vocab), correct / len(test)


def assert_expected(path, csv_text):
    expected_vocab, expected_accuracy = reference_metrics(csv_text)
    vocab, accuracy, _ = run_program(path)
    assert vocab == expected_vocab, (
        f"Expected training-only vocabulary size {expected_vocab}, got {vocab}"
    )
    assert abs(accuracy - expected_accuracy) <= 1e-6, (
        f"Expected test accuracy {expected_accuracy}, got {accuracy}"
    )


def test_results_file_exists():
    assert os.path.isfile(RESULTS), "/home/user/results.txt does not exist. Did you pipe the output to this file?"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "/home/user/nb_classifier does not exist. Did you compile the C++ code to this executable?"
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/nb_classifier is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/nb_classifier is not a compiled executable."


def test_source_code_modified():
    assert os.path.isfile(SOURCE), "/home/user/naive_bayes.cpp is missing."
    with open(SOURCE, 'r') as f:
        content = f.read()
    assert len(content) > 0, "naive_bayes.cpp is empty."


def test_results_content_and_current_execution():
    with open(RESULTS, 'r') as f:
        saved_output = f.read()

    match = OUTPUT_RE.fullmatch(saved_output)
    assert match is not None, "results.txt must use exactly the specified two-line output format."
    assert int(match.group(1)) == 33, (
        f"Expected Vocab Size to be 33 (training set only), but got {match.group(1)}."
    )

    with open(DATASET, 'r') as f:
        canonical_csv = f.read()
    expected_vocab, expected_accuracy = reference_metrics(canonical_csv)
    vocab, accuracy, actual_output = run_program(EXECUTABLE)
    assert actual_output == saved_output, "results.txt is not the output of the submitted executable on dataset.csv."
    assert vocab == expected_vocab == 33
    assert abs(accuracy - expected_accuracy) <= 1e-6


def test_training_only_fit_and_oov_handling():
    challenges = [
        """text,label
s s s s s s s s s s,1
s s s s s s s s s s,1
s s s s s s s s s s,1
s s s s s s s s s s,1
h,0
h,0
h,0
h,0
s unseen,1
h another,0
""",
        """text,label
alpha alpha,1
beta alpha,1
offer deal,1
alpha deal,1
quiet home,0
home quiet,0
family home,0
quiet family,0
alpha testonlyword,1
quiet othernewword othernewword,0
""",
    ]

    with open(DATASET, 'rb') as f:
        original_dataset = f.read()

    compiled_source = '/tmp/nb_from_submitted_source'
    compile_proc = subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-o', compiled_source],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, (
        "naive_bayes.cpp does not compile with g++ -std=c++17: " + compile_proc.stderr
    )

    try:
        for csv_text in challenges:
            with open(DATASET, 'w') as f:
                f.write(csv_text)
            assert_expected(EXECUTABLE, csv_text)
            assert_expected(compiled_source, csv_text)
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
