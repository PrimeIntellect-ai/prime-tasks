#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import shutil
import stat
import subprocess
import tempfile
from collections import Counter

CORPUS_PATH = "/home/user/corpus.txt"
RESULT_PATH = "/home/user/result.txt"
SOURCE_PATH = "/home/user/prep_data.go"

CANONICAL_CORPUS = """the quick brown fox jumps over the lazy dog
a quick brown dog jumps
machine learning is a subset of artificial intelligence
data science encompasses machine learning and statistics
artificial intelligence and machine learning are the future
statistics is the foundation of data science
deep learning is a type of machine learning
natural language processing deals with text
tokenization is the first step in natural language processing
machine learning models require high quality data
"""


def compute_expected_result(corpus_text):
    docs = [line.strip().lower().split() for line in corpus_text.splitlines() if line.strip()]

    tfs = []
    for doc in docs:
        counts = Counter(doc)
        total = len(doc)
        tfs.append({k: v / total for k, v in counts.items()})

    max_sim = -1.0
    best_i, best_j = -1, -1
    for i in range(len(tfs)):
        for j in range(i + 1, len(tfs)):
            keys = set(tfs[i]) | set(tfs[j])
            dot = sum(tfs[i].get(k, 0) * tfs[j].get(k, 0) for k in keys)
            norm_a = sum(v * v for v in tfs[i].values())
            norm_b = sum(v * v for v in tfs[j].values())
            sim = 0.0 if norm_a == 0 or norm_b == 0 else dot / (math.sqrt(norm_a) * math.sqrt(norm_b))
            if sim > max_sim:
                max_sim = sim
                best_i, best_j = i, j

    return f"{best_i},{best_j},{max_sim:.4f}"


def read_result():
    assert os.path.exists(RESULT_PATH), (
        f"Result file missing at {RESULT_PATH}. The Go script might not have been executed successfully."
    )
    assert stat.S_ISREG(os.stat(RESULT_PATH, follow_symlinks=False).st_mode), "Result must be a regular file"
    with open(RESULT_PATH, "r") as f:
        return f.read().strip()


def assert_result(corpus_text):
    expected_content = compute_expected_result(corpus_text)
    actual_content = read_result()
    assert actual_content == expected_content, (
        "Result file content is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{actual_content}'\n"
        "Check if the integer division bug was properly fixed and the script was recompiled/run."
    )


def run_binary(binary, corpus_text):
    with open(CORPUS_PATH, "w") as f:
        f.write(corpus_text)
    if os.path.lexists(RESULT_PATH):
        os.unlink(RESULT_PATH)
    subprocess.run([binary], check=True, timeout=15)
    with open(CORPUS_PATH, "r") as f:
        assert f.read() == corpus_text, "The program modified the input corpus"
    assert_result(corpus_text)


def generated_corpus():
    tokens = ["tok" + secrets.token_hex(6) for _ in range(12)]
    docs = [
        [tokens[0], tokens[1], tokens[2], tokens[3], tokens[4]],
        [tokens[0], tokens[1], tokens[2], tokens[3]],
        [tokens[5], tokens[6], tokens[7]],
        [tokens[0], tokens[5], tokens[8]],
        [tokens[9], tokens[10], tokens[11]],
        [tokens[2], tokens[6], tokens[9], tokens[11]],
    ]
    random.SystemRandom().shuffle(docs)
    return "\n".join(" ".join(doc) for doc in docs) + "\n"


def main():
    # Preserve the original checks and additionally ensure the supplied fixture
    # was not changed to manipulate the recomputed answer.
    assert os.path.exists(CORPUS_PATH), f"Corpus file missing at {CORPUS_PATH}"
    with open(CORPUS_PATH, "r") as f:
        current_corpus = f.read()
    assert current_corpus == CANONICAL_CORPUS, "The provided corpus.txt fixture was modified"
    assert_result(current_corpus)

    assert os.path.exists(SOURCE_PATH), f"Go source missing at {SOURCE_PATH}"
    source_stat = os.stat(SOURCE_PATH, follow_symlinks=False)
    assert stat.S_ISREG(source_stat.st_mode), "prep_data.go must be a regular Go source file"
    assert not os.path.islink(SOURCE_PATH), "prep_data.go must not be a symbolic link"

    with tempfile.TemporaryDirectory(prefix="verify_prep_") as workdir:
        copied_source = os.path.join(workdir, "prep_data.go")
        shutil.copyfile(SOURCE_PATH, copied_source)

        # Directly verify that getTF computes fractional term frequencies, not
        # zero vectors or unnormalised token counts.
        with open(os.path.join(workdir, "prep_data_test.go"), "w") as f:
            f.write(r'''package main

import (
    "math"
    "testing"
)

func TestGetTFFractions(t *testing.T) {
    tokens := []string{"alpha", "alpha", "beta", "gamma"}
    vocab := []string{"alpha", "beta", "gamma", "missing"}
    got := getTF(tokens, vocab)
    want := []float64{0.5, 0.25, 0.25, 0.0}
    if len(got) != len(want) {
        t.Fatalf("getTF returned length %d, want %d", len(got), len(want))
    }
    for i := range want {
        if math.Abs(got[i]-want[i]) > 1e-12 {
            t.Fatalf("getTF[%d] = %v, want %v", i, got[i], want[i])
        }
    }
}
''')

        env = os.environ.copy()
        env["GO111MODULE"] = "off"
        subprocess.run(["go", "test"], cwd=workdir, env=env, check=True, timeout=30)

        binary = os.path.join(workdir, "prep_data_verified")
        subprocess.run(["go", "build", "-o", binary, copied_source], env=env, check=True, timeout=30)
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Go source did not produce an executable"

        try:
            # Exercise the compiled submission on verifier-generated inputs so
            # a prewritten result for the public fixture cannot pass.
            run_binary(binary, generated_corpus())
            run_binary(binary, generated_corpus())
            # Run once more on the required fixture and leave its result in place.
            run_binary(binary, CANONICAL_CORPUS)
        finally:
            with open(CORPUS_PATH, "w") as f:
                f.write(CANONICAL_CORPUS)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
