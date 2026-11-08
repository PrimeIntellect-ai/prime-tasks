#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import re
import csv
import stat
import secrets
import string
import subprocess
import pytest

SOURCE_PATH = "/home/user/process.cpp"
EXECUTABLE_PATH = "/home/user/process"
CORPUS_PATH = "/home/user/corpus.txt"
QUERIES_PATH = "/home/user/queries.txt"
SUMMARY_PATH = "/home/user/summary.csv"

def tokenize(text):
    text = text.lower()
    text = re.sub(r'[^a-z0-9 ]', '', text)
    return [t for t in text.split(' ') if t]

def bow(tokens):
    vec = {}
    for t in tokens:
        vec[t] = vec.get(t, 0) + 1
    return vec

def dot(v1, v2):
    return sum(v1.get(k, 0) * v2.get(k, 0) for k in v1)

def norm(v):
    return math.sqrt(sum(val**2 for val in v.values()))

def cosine(v1, v2):
    n1 = norm(v1)
    n2 = norm(v2)
    if n1 == 0 or n2 == 0: return 0.0
    return dot(v1, v2) / (n1 * n2)

def compute_expected_results():
    corpus_path = "/home/user/corpus.txt"
    queries_path = "/home/user/queries.txt"

    with open(corpus_path, 'r') as f:
        corpus = [bow(tokenize(line)) for line in f]

    with open(queries_path, 'r') as f:
        queries = [bow(tokenize(line)) for line in f]

    top_scores = []
    results = []
    for q_idx, q in enumerate(queries):
        best_idx = -1
        best_score = -1.0
        for c_idx, c in enumerate(corpus):
            score = cosine(q, c)
            if score > best_score:
                best_score = score
                best_idx = c_idx
        top_scores.append(best_score)
        results.append((q_idx, best_idx, best_score))

    N = len(top_scores)
    mean = sum(top_scores) / N
    variance = sum((x - mean)**2 for x in top_scores) / (N - 1)
    std_dev = math.sqrt(variance)

    ci_margin = 1.96 * (std_dev / math.sqrt(N))
    ci_lower = mean - ci_margin
    ci_upper = mean + ci_margin

    return results, mean, ci_lower, ci_upper

def run_program():
    result = subprocess.run(
        [EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Submitted executable failed with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(SUMMARY_PATH), "Program did not create /home/user/summary.csv"

def assert_strict_summary():
    expected_results, expected_mean, expected_ci_lower, expected_ci_upper = compute_expected_results()
    with open(SUMMARY_PATH, 'r') as f:
        lines = [line.rstrip('\r\n') for line in f]

    expected_lines = ["QueryIndex,TopCorpusIndex,CosineSimilarity"]
    expected_lines.extend(
        f"{q_idx},{c_idx},{score:.4f}" for q_idx, c_idx, score in expected_results
    )
    expected_lines.append("Mean,CI_Lower,CI_Upper")
    expected_lines.append(
        f"{expected_mean:.4f},{expected_ci_lower:.4f},{expected_ci_upper:.4f}"
    )
    assert lines == expected_lines, (
        "summary.csv did not contain the exact four-decimal results for the supplied inputs\n"
        f"Expected: {expected_lines}\nGot: {lines}"
    )

def test_00_submitted_program_exists_compiles_and_runs():
    assert os.path.isfile(SOURCE_PATH), f"Expected source file {SOURCE_PATH} does not exist."
    assert not os.path.islink(SOURCE_PATH), f"Expected {SOURCE_PATH} to be a regular source file."
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), f"Expected {SOURCE_PATH} to be a regular file."

    assert os.path.isfile(EXECUTABLE_PATH), f"Expected compiled executable {EXECUTABLE_PATH} does not exist."
    assert not os.path.islink(EXECUTABLE_PATH), f"Expected {EXECUTABLE_PATH} to be a regular executable."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"Expected {EXECUTABLE_PATH} to be executable."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"process.cpp failed to compile: {compile_result.stderr}"
    run_program()

def test_summary_file_exists():
    summary_path = "/home/user/summary.csv"
    assert os.path.isfile(summary_path), f"Expected output file {summary_path} does not exist."

def test_summary_contents():
    summary_path = "/home/user/summary.csv"
    assert os.path.isfile(summary_path), f"Expected output file {summary_path} does not exist."

    expected_results, expected_mean, expected_ci_lower, expected_ci_upper = compute_expected_results()

    with open(summary_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_results) + 3, "Incorrect number of lines in summary.csv"

    assert lines[0] == "QueryIndex,TopCorpusIndex,CosineSimilarity", "Header for results is incorrect."

    for i in range(len(expected_results)):
        parts = lines[i+1].split(',')
        assert len(parts) == 3, f"Line {i+1} does not have 3 columns."
        q_idx, c_idx, score = expected_results[i]

        assert int(parts[0]) == q_idx, f"Expected QueryIndex {q_idx}, got {parts[0]}"
        assert int(parts[1]) == c_idx, f"Expected TopCorpusIndex {c_idx}, got {parts[1]}"
        assert math.isclose(float(parts[2]), score, abs_tol=1e-3), f"Expected CosineSimilarity {score:.4f}, got {parts[2]}"

    assert lines[-2] == "Mean,CI_Lower,CI_Upper", "Header for statistics is incorrect."

    stat_parts = lines[-1].split(',')
    assert len(stat_parts) == 3, "Statistics line does not have 3 columns."

    assert math.isclose(float(stat_parts[0]), expected_mean, abs_tol=1e-3), f"Expected Mean {expected_mean:.4f}, got {stat_parts[0]}"
    assert math.isclose(float(stat_parts[1]), expected_ci_lower, abs_tol=1e-3), f"Expected CI_Lower {expected_ci_lower:.4f}, got {stat_parts[1]}"
    assert math.isclose(float(stat_parts[2]), expected_ci_upper, abs_tol=1e-3), f"Expected CI_Upper {expected_ci_upper:.4f}, got {stat_parts[2]}"

def test_zz_program_handles_varied_inputs():
    with open(CORPUS_PATH, 'r') as f:
        original_corpus = f.read()
    with open(QUERIES_PATH, 'r') as f:
        original_queries = f.read()

    words = []
    while len(words) < 20:
        word = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(10))
        if word not in words:
            words.append(word)

    a, b, c, d, e, fword, g, h, i, j, k, m, n, p, q, r, s, u, v, w = words
    cases = [
        (
            [
                f"{a.upper()}!!! {a} {b} 101",
                f"{c} {d} {d} {e}",
                f"{b} {fword} 202 {fword}",
                f"{g} {h} {i} {g} {g}",
                f"{j} {k}",
            ],
            [
                f"{a.upper()}, {a} 101",
                f"{d} {d} {c}",
                f"{fword} {fword} 202 {b}",
                f"{g} {g} {h}",
            ],
        ),
        (
            [
                f"{m}-{n}",
                f"{p}___{q} {q} 77",
                f"{r} {r} {s} 88",
                f"{u} {v} {w}",
            ],
            [
                f"{m.upper()}-{n.upper()}",
                f"{p}___{q} {q} 77",
                f"{r.upper()} {r} {s} 88",
            ],
        ),
    ]

    try:
        for corpus, queries in cases:
            with open(CORPUS_PATH, 'w') as fobj:
                fobj.write('\n'.join(corpus) + '\n')
            with open(QUERIES_PATH, 'w') as fobj:
                fobj.write('\n'.join(queries) + '\n')
            if os.path.exists(SUMMARY_PATH):
                os.remove(SUMMARY_PATH)
            run_program()
            assert_strict_summary()
    finally:
        with open(CORPUS_PATH, 'w') as fobj:
            fobj.write(original_corpus)
        with open(QUERIES_PATH, 'w') as fobj:
            fobj.write(original_queries)
        try:
            run_program()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
