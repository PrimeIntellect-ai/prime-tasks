#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import secrets
import shlex
import stat
import subprocess
import tempfile
from contextlib import contextmanager

import pytest

SCRIPT_PATH = "/home/user/filter_dataset.sh"
OUTPUT_PATH = "/home/user/scores.tsv"


def tokenize(text):
    text = text.lower()
    text = re.sub(r'[^a-z]', ' ', text)
    return text.split()


def compute_expected_scores(domain_path, generic_path, target_path):
    with open(domain_path, 'r') as f:
        domain_text = f.read()
    with open(generic_path, 'r') as f:
        generic_text = f.read()
    with open(target_path, 'r') as f:
        target_lines = f.readlines()

    domain_words = tokenize(domain_text)
    generic_words = tokenize(generic_text)
    n_domain = len(domain_words)
    n_generic = len(generic_words)
    vocab = set(domain_words).union(set(generic_words))
    v = len(vocab)

    domain_counts = {}
    for w in domain_words:
        domain_counts[w] = domain_counts.get(w, 0) + 1

    generic_counts = {}
    for w in generic_words:
        generic_counts[w] = generic_counts.get(w, 0) + 1

    expected_output = []
    for i, line in enumerate(target_lines, 1):
        words = tokenize(line)
        score = 0.0
        for w in words:
            c_d = domain_counts.get(w, 0)
            c_g = generic_counts.get(w, 0)
            p_d = (c_d + 1) / (n_domain + v)
            p_g = (c_g + 1) / (n_generic + v)
            score += math.log(p_d) - math.log(p_g)

        classification = "DOMAIN" if score > 0 else "GENERIC"
        expected_output.append(f"{i}\t{score:.4f}\t{classification}")

    return expected_output


@contextmanager
def high_level_interpreters_disabled():
    patterns = (
        "python*", "pypy*", "perl*", "ruby*", "node*", "php*",
        "lua*", "julia*", "R", "Rscript"
    )
    saved_modes = {}
    try:
        for directory in ("/bin", "/usr/bin", "/usr/local/bin"):
            for pattern in patterns:
                for path in glob.glob(os.path.join(directory, pattern)):
                    try:
                        real = os.path.realpath(path)
                        mode = stat.S_IMODE(os.stat(real).st_mode)
                        if real not in saved_modes and mode & 0o111:
                            saved_modes[real] = mode
                            os.chmod(real, mode & ~0o111)
                    except (FileNotFoundError, PermissionError):
                        pass
        yield
    finally:
        for path, mode in saved_modes.items():
            try:
                os.chmod(path, mode)
            except FileNotFoundError:
                pass


def run_script(domain_path, generic_path, target_path):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    with high_level_interpreters_disabled():
        return subprocess.run(
            [SCRIPT_PATH, domain_path, generic_path, target_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )


def assert_output_correct(domain_path, generic_path, target_path):
    result = run_script(domain_path, generic_path, target_path)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."

    with open(OUTPUT_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected_lines = compute_expected_scores(domain_path, generic_path, target_path)
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in output, got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines), 1):
        actual_parts = actual.split()
        expected_parts = expected.split('\t')
        assert len(actual_parts) == 3, f"Line {i} does not have exactly 3 columns: '{actual}'"
        assert actual_parts[0] == expected_parts[0], (
            f"Line {i}: Expected line number {expected_parts[0]}, got {actual_parts[0]}"
        )
        try:
            actual_score = float(actual_parts[1])
        except ValueError:
            pytest.fail(f"Line {i}: Score is not numeric: {actual_parts[1]}")
        expected_score = float(expected_parts[1])
        assert math.isclose(actual_score, expected_score, abs_tol=0.0002), (
            f"Line {i}: Expected score {expected_score:.4f}, got {actual_score:.4f}"
        )
        assert actual_parts[2] == expected_parts[2], (
            f"Line {i}: Expected classification {expected_parts[2]}, got {actual_parts[2]}"
        )


def random_word(rng, used):
    alphabet = "abcdefghijklmnopqrstuvwxyz"
    while True:
        word = ''.join(rng.choice(alphabet) for _ in range(rng.randint(6, 12)))
        if word not in used:
            used.add(word)
            return word


def make_random_case(case_dir, line_count):
    rng = random.SystemRandom()
    used = set()
    domain_vocab = [random_word(rng, used) for _ in range(7)]
    generic_vocab = [random_word(rng, used) for _ in range(8)]
    shared_vocab = [random_word(rng, used) for _ in range(3)]
    unknown_vocab = [random_word(rng, used) for _ in range(4)]

    domain_tokens = []
    generic_tokens = []
    for word in domain_vocab:
        domain_tokens.extend([word] * rng.randint(1, 5))
    for word in generic_vocab:
        generic_tokens.extend([word] * rng.randint(1, 5))
    for word in shared_vocab:
        domain_tokens.extend([word] * rng.randint(1, 4))
        generic_tokens.extend([word] * rng.randint(1, 4))
    rng.shuffle(domain_tokens)
    rng.shuffle(generic_tokens)

    def noisy(tokens):
        pieces = []
        separators = [" ", "!!!", "--", " 123 ", "\t", ", "]
        for token in tokens:
            if rng.choice((True, False)):
                token = token.upper()
            pieces.append(token)
            pieces.append(rng.choice(separators))
        return ''.join(pieces) + "\n"

    target_lines = [
        f"{domain_vocab[0].upper()}!!! {domain_vocab[0]} -- {shared_vocab[0]}\n",
        f"{generic_vocab[1]} 123 {generic_vocab[2].upper()}, {shared_vocab[1]}\n",
        f"{domain_vocab[2]}-{generic_vocab[3]} {unknown_vocab[0]}\n",
        "9876 !!! ---\n",
        f"{unknown_vocab[1]} {unknown_vocab[1]} {domain_vocab[3]}\n",
    ]
    while len(target_lines) < line_count:
        pool = domain_vocab + generic_vocab + shared_vocab + unknown_vocab
        chosen = [rng.choice(pool) for _ in range(rng.randint(1, 8))]
        target_lines.append(noisy(chosen))

    domain_path = os.path.join(case_dir, "domain-" + secrets.token_hex(8) + ".txt")
    generic_path = os.path.join(case_dir, "generic-" + secrets.token_hex(8) + ".txt")
    target_path = os.path.join(case_dir, "target-" + secrets.token_hex(8) + ".txt")
    with open(domain_path, "w") as f:
        f.write(noisy(domain_tokens))
    with open(generic_path, "w") as f:
        f.write(noisy(generic_tokens))
    with open(target_path, "w") as f:
        f.writelines(target_lines)
    return domain_path, generic_path, target_path


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline(4096).decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!"), "Script must have a shell shebang."
    try:
        command = shlex.split(first_line[2:].strip())
    except ValueError:
        command = []
    assert command, "Script has an invalid shebang."
    if os.path.basename(command[0]) == "env":
        command = [item for item in command[1:] if not item.startswith("-")]
    assert command and os.path.basename(command[0]) == "bash", (
        "filter_dataset.sh must be implemented as a Bash script."
    )


def test_output_correctness():
    assert_output_correct(
        "/home/user/domain.txt",
        "/home/user/generic.txt",
        "/home/user/target.txt",
    )


def test_unseen_randomized_inputs():
    with tempfile.TemporaryDirectory(prefix="nb-verifier-") as case_dir:
        for line_count in (5, 7, 9):
            paths = make_random_case(case_dir, line_count)
            assert_output_correct(*paths)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
