#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import subprocess
import sys

import pandas as pd
from scipy.stats import ttest_ind
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT_PATH = "/home/user/analyze.py"
REPORT_PATH = "/home/user/report.json"
CSV_PATHS = [
    "/home/user/golden.csv",
    "/home/user/exp_A.csv",
    "/home/user/exp_B.csv",
]
REQUIRED_KEYS = {
    "t_stat",
    "p_value",
    "exp_A_success_alpha",
    "exp_A_success_beta",
}


def run_analysis():
    assert os.path.exists(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file"
    assert os.path.getsize(SCRIPT_PATH) > 0, f"{SCRIPT_PATH} is empty"

    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Missing file: {REPORT_PATH}. The report was not generated."

    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {REPORT_PATH} is not valid JSON: {exc}")


def test_report_json_exists_and_correct():
    data = run_analysis()

    missing_keys = REQUIRED_KEYS - set(data.keys())
    assert not missing_keys, f"Missing keys in report.json: {missing_keys}"

    # Ground truth values derived from the task definition
    expected_t_stat = 1.3406
    expected_p_value = 0.2312
    expected_alpha = 4
    expected_beta = 3

    assert math.isclose(data["t_stat"], expected_t_stat, abs_tol=1e-3), \
        f"Expected t_stat around {expected_t_stat}, got {data['t_stat']}"

    assert math.isclose(data["p_value"], expected_p_value, abs_tol=1e-3), \
        f"Expected p_value around {expected_p_value}, got {data['p_value']}"

    assert data["exp_A_success_alpha"] == expected_alpha, \
        f"Expected exp_A_success_alpha to be {expected_alpha}, got {data['exp_A_success_alpha']}"

    assert data["exp_A_success_beta"] == expected_beta, \
        f"Expected exp_A_success_beta to be {expected_beta}, got {data['exp_A_success_beta']}"


def expected_report(golden, exp_a, exp_b):
    vectorizer = TfidfVectorizer()
    golden_vectors = vectorizer.fit_transform(golden["text"])
    a_vectors = vectorizer.transform(exp_a["text"])
    b_vectors = vectorizer.transform(exp_b["text"])

    a_scores = cosine_similarity(a_vectors, golden_vectors).max(axis=1)
    b_scores = cosine_similarity(b_vectors, golden_vectors).max(axis=1)
    result = ttest_ind(a_scores, b_scores, equal_var=False)

    successes = int((a_scores > 0.5).sum())
    return {
        "t_stat": float(result.statistic),
        "p_value": float(result.pvalue),
        "exp_A_success_alpha": 1 + successes,
        "exp_A_success_beta": 1 + len(a_scores) - successes,
    }


def random_word():
    return "w" + secrets.token_hex(8)


def make_random_case():
    rng = secrets.SystemRandom()
    vocab = [random_word() for _ in range(22)]
    unknown = [random_word() for _ in range(8)]

    golden_texts = []
    for i in range(5):
        words = rng.sample(vocab[1:], rng.randint(3, 7))
        if i < 4:
            words.append(vocab[0])
        for _ in range(rng.randint(0, 2)):
            words.append(rng.choice(words))
        rng.shuffle(words)
        golden_texts.append(" ".join(words))

    a_texts = [
        golden_texts[0],
        golden_texts[1],
        " ".join(golden_texts[2].split()[:-1] + [unknown[0]]),
        " ".join(rng.sample(vocab, 5)),
        " ".join(rng.sample(vocab, 2) + unknown[1:4]),
        " ".join(unknown[4:]),
        " ".join(rng.sample(vocab, 7) + [rng.choice(vocab)]),
    ]
    b_texts = [
        " ".join(unknown[:3]),
        " ".join([rng.choice(vocab), unknown[3], unknown[4]]),
        " ".join(rng.sample(vocab, 3) + unknown[5:7]),
        " ".join(rng.sample(vocab, 6)),
        " ".join(rng.sample(vocab, 2)),
        " ".join(rng.sample(vocab, 4) + [unknown[7]]),
    ]

    def frame(texts):
        return pd.DataFrame({"id": range(1, len(texts) + 1), "text": texts})

    return frame(golden_texts), frame(a_texts), frame(b_texts)


def assert_matches(actual, expected):
    assert set(actual.keys()) == REQUIRED_KEYS, (
        f"report.json must contain exactly {sorted(REQUIRED_KEYS)}, got {sorted(actual.keys())}"
    )
    for key in ("t_stat", "p_value"):
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), \
            f"{key} must be numeric"
        assert math.isfinite(float(actual[key])), f"{key} must be finite"
        assert math.isclose(float(actual[key]), expected[key], rel_tol=1e-9, abs_tol=1e-10), \
            f"Incorrect {key}: expected {expected[key]}, got {actual[key]}"
    for key in ("exp_A_success_alpha", "exp_A_success_beta"):
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), \
            f"{key} must be numeric"
        assert actual[key] == expected[key], \
            f"Incorrect {key}: expected {expected[key]}, got {actual[key]}"


def test_script_computes_results_for_unseen_inputs():
    saved = {path: open(path, "rb").read() for path in CSV_PATHS}
    saved_report = open(REPORT_PATH, "rb").read() if os.path.isfile(REPORT_PATH) else None

    try:
        for _ in range(2):
            golden, exp_a, exp_b = make_random_case()
            expected = expected_report(golden, exp_a, exp_b)
            assert math.isfinite(expected["t_stat"])
            assert math.isfinite(expected["p_value"])

            golden.to_csv(CSV_PATHS[0], index=False)
            exp_a.to_csv(CSV_PATHS[1], index=False)
            exp_b.to_csv(CSV_PATHS[2], index=False)

            actual = run_analysis()
            assert_matches(actual, expected)
    finally:
        for path, contents in saved.items():
            with open(path, "wb") as f:
                f.write(contents)
        if saved_report is None:
            if os.path.lexists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(saved_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
