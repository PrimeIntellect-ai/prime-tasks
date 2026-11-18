#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import math
import numpy as np


def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def compute_expected_results():
    raw_path = '/home/user/raw_texts.txt'
    priors_path = '/home/user/word_priors.csv'

    assert os.path.isfile(raw_path), "raw_texts.txt is missing."
    assert os.path.isfile(priors_path), "word_priors.csv is missing."

    priors = {}
    with open(priors_path, 'r') as f:
        header = f.readline()
        for line in f:
            w, p = line.strip().split(',')
            priors[w] = float(p)

    with open(raw_path, 'r') as f:
        raw_lines = [l.strip() for l in f]

    expected_cleaned_lines = []
    replacement_fractions = []

    for line in raw_lines:
        tokens = line.split()
        cleaned_tokens = []
        replaced_count = 0
        for t in tokens:
            best_w = None
            best_score = -1

            for w, p in priors.items():
                dist = levenshtein(t, w)
                score = (0.1 ** dist) * p
                if score > best_score:
                    best_score = score
                    best_w = w
                elif score == best_score:
                    if best_w is None or w < best_w:
                        best_w = w

            cleaned_tokens.append(best_w)
            if best_w != t:
                replaced_count += 1

        expected_cleaned_lines.append(" ".join(cleaned_tokens))
        if tokens:
            replacement_fractions.append(replaced_count / len(tokens))
        else:
            replacement_fractions.append(0.0)

    return expected_cleaned_lines, replacement_fractions


def test_cleaned_texts():
    cleaned_path = '/home/user/cleaned_texts.txt'
    assert os.path.isfile(cleaned_path), "cleaned_texts.txt is missing."

    expected_cleaned_lines, _ = compute_expected_results()

    with open(cleaned_path, 'r') as f:
        actual_cleaned_lines = [l.strip() for l in f]

    assert len(actual_cleaned_lines) == len(expected_cleaned_lines), "Number of lines in cleaned_texts.txt is incorrect."

    for i, (actual, expected) in enumerate(zip(actual_cleaned_lines, expected_cleaned_lines)):
        assert actual == expected, f"Line {i+1} in cleaned_texts.txt is incorrect. Expected: '{expected}', Got: '{actual}'"


def test_bootstrap_ci():
    ci_path = '/home/user/bootstrap_ci.txt'
    assert os.path.isfile(ci_path), "bootstrap_ci.txt is missing."

    with open(ci_path, 'r') as f:
        content = f.read().strip()

    # Check format: [lower, upper]
    match = re.match(r'^\[\s*([0-9\.]+)\s*,\s*([0-9\.]+)\s*\]$', content)
    assert match is not None, f"bootstrap_ci.txt format is incorrect. Expected '[lower, upper]', got '{content}'"

    lower = float(match.group(1))
    upper = float(match.group(2))

    assert lower <= upper, "Lower bound of CI is greater than upper bound."

    # The bounds should be valid probabilities between 0 and 1
    assert 0.0 <= lower <= 1.0, "Lower bound is out of valid range [0, 1]."
    assert 0.0 <= upper <= 1.0, "Upper bound is out of valid range [0, 1]."

    # The length of the confidence interval should be relatively small
    assert upper - lower < 0.5, "Confidence interval is suspiciously wide."

    # Independently recompute the required seeded bootstrap confidence interval.
    _, replacement_fractions = compute_expected_results()
    assert replacement_fractions, "Cannot bootstrap an empty set of sentences."

    np.random.seed(42)
    bootstrap_means = []
    sample_size = len(replacement_fractions)
    for _ in range(10000):
        sample = np.random.choice(replacement_fractions, size=sample_size, replace=True)
        bootstrap_means.append(np.mean(sample))

    expected_lower, expected_upper = np.percentile(bootstrap_means, [2.5, 97.5])
    expected_content = f"[{expected_lower:.4f}, {expected_upper:.4f}]"
    assert content == expected_content, (
        f"bootstrap_ci.txt is incorrect. Expected '{expected_content}', got '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
