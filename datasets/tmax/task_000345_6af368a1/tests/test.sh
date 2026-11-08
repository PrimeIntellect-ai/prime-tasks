#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile


def run_sanitizer(script_path, data_path):
    return subprocess.run(
        ["bash", script_path, data_path],
        capture_output=True,
        timeout=5,
    ).returncode


def test_crash_time():
    crash_file = "/home/user/crash_time.txt"
    assert os.path.isfile(crash_file), f"File {crash_file} is missing."
    with open(crash_file, "r") as f:
        content = f.read().strip()
    assert content == "16", f"Expected crash time to be 16, but got {content}."


def test_sanitize_script_exists_and_executable():
    script_path = "/home/user/sanitize.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_adversarial_corpus():
    script_path = "/home/user/sanitize.sh"
    clean_dir = "/app/verifier/clean"
    evil_dir = "/app/verifier/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        if run_sanitizer(script_path, cf) != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if run_sanitizer(script_path, ef) != 1:
            evil_failures.append(os.path.basename(ef))

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    assert not clean_failures and not evil_failures, "Adversarial corpus verification failed:\n" + "\n".join(errors)


def make_file(total, scores, primer_lengths, invalid_score=None):
    lines = [f"Total_Score: {total}"]
    for i, (score, primer_len) in enumerate(zip(scores, primer_lengths), 1):
        rendered_score = invalid_score if invalid_score is not None and i == 1 else score
        primer = ("ATCG" * 8)[:primer_len]
        target = ("GCTA" * 8)[:20]
        lines.append(f"Alignment {i}: Primer={primer} Target={target} Score={rendered_score}")
    return "\n".join(lines) + "\n"


def test_generated_hidden_corpus():
    script_path = "/home/user/sanitize.sh"
    rng = random.SystemRandom()
    cases = []

    # Explicit edge cases for the tolerance and primer-length boundaries.
    cases.extend([
        (make_file("1.001", ["1.000"], [15]), 0),
        (make_file("-1.001", ["-1.000"], [30]), 0),
        (make_file("1.002", ["1.000"], [20]), 1),
        (make_file("0.998", ["1.000"], [20]), 1),
        (make_file("NaN", ["0.000"], [20]), 1),
        (make_file("Inf", ["0.000"], [20]), 1),
        (make_file("-Inf", ["0.000"], [20]), 1),
        (make_file("0.000", ["0.000"], [20], "NaN"), 1),
        (make_file("0.000", ["0.000"], [20], "Inf"), 1),
        (make_file("0.000", ["0.000"], [20], "-Inf"), 1),
    ])

    # Generate fresh mixed clean and evil inputs whose random paths disclose no label.
    for _ in range(48):
        kind = rng.choice(["clean", "clean", "sum_high", "sum_low", "short", "long", "bad_value"])
        count = rng.randint(1, 5)
        score_units = [rng.randint(-5000, 5000) for _ in range(count)]
        scores = [f"{value / 1000:.3f}" for value in score_units]
        total_units = sum(score_units)
        primer_lengths = [rng.randint(15, 30) for _ in range(count)]
        invalid_score = None
        expected = 0

        if kind == "sum_high":
            total_units += rng.randint(2, 30)
            expected = 1
        elif kind == "sum_low":
            total_units -= rng.randint(2, 30)
            expected = 1
        elif kind == "short":
            primer_lengths[rng.randrange(count)] = rng.randint(1, 14)
            expected = 1
        elif kind == "long":
            primer_lengths[rng.randrange(count)] = rng.randint(31, 32)
            expected = 1
        elif kind == "bad_value":
            invalid_score = rng.choice(["NaN", "Inf", "-Inf"])
            expected = 1

        total = f"{total_units / 1000:.3f}"
        cases.append((make_file(total, scores, primer_lengths, invalid_score), expected))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="sanitizer-corpus-") as corpus_dir:
        for content, expected in cases:
            path = os.path.join(corpus_dir, secrets.token_hex(12))
            with open(path, "w") as f:
                f.write(content)
            actual = run_sanitizer(script_path, path)
            if actual != expected:
                failures.append((content, expected, actual))

    assert not failures, "Generated corpus failures:\n" + "\n---\n".join(
        f"expected exit {expected}, got {actual}\n{content}" for content, expected, actual in failures[:5]
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
