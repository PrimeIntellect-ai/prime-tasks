#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from fractions import Fraction

import pytest


def test_clean_logs_exists_and_content():
    """Check if /home/user/clean_logs.txt exists and has the correct cleaned content."""
    file_path = "/home/user/clean_logs.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_lines = [
        "database connection failed due to timeout",
        "user authentication successful",
        "critical server overload detected impending crash",
        "warning high memory usage on server",
        "server crash reported by user",
        "disk space critical on server"
    ]

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        actual_normalized = " ".join(actual.split())
        assert actual_normalized == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual_normalized}'."


def test_jaccard_c_and_executable_exist():
    """Check if the C source file and compiled executable exist."""
    c_file = "/home/user/jaccard.c"
    exe_file = "/home/user/jaccard"

    assert os.path.isfile(c_file), f"C source file {c_file} does not exist."
    assert os.path.isfile(exe_file), f"Compiled executable {exe_file} does not exist."
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable."


def test_best_match_content():
    """Check if /home/user/best_match.txt contains the correct best match."""
    file_path = "/home/user/best_match.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_match = "critical server overload detected impending crash"

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    content_normalized = " ".join(content.split())
    assert content_normalized == expected_match, f"Content of {file_path} is incorrect. Expected '{expected_match}', got '{content_normalized}'."


@pytest.fixture(scope="session")
def executables(tmp_path_factory):
    rebuilt = tmp_path_factory.mktemp("build") / "jaccard"
    result = subprocess.run(
        ["gcc", "/home/user/jaccard.c", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"jaccard.c did not compile with gcc:\n{result.stderr}"
    return ["/home/user/jaccard", str(rebuilt)]


def oracle(query, lines):
    query_words = set(query.split())
    best_line = None
    best_score = Fraction(-1, 1)
    for line in lines:
        line_words = set(line.split())
        union = query_words | line_words
        score = Fraction(len(query_words & line_words), len(union)) if union else Fraction(1, 1)
        if score > best_score:
            best_score = score
            best_line = line
    return best_line


def generated_cases():
    rng = secrets.SystemRandom()

    # Duplicate words must be treated as one set member.
    words = ["w" + secrets.token_hex(7) for _ in range(8)]
    a, b, c, x, y, z, n1, n2 = words
    yield f"{a} {b} {c}", [
        f"{a} {a} {a} {a}",
        f"{a} {b} {x}",
        f"{b} {c} {y} {z}",
        f"{n1} {n2}",
    ]

    # The first of two equal-scoring lines must win, preserving its exact text.
    words = ["t" + secrets.token_hex(7) for _ in range(8)]
    a, b, c, x, y, z, n1, n2 = words
    yield f"{a} {b} {c}", [
        f"{a} {a} {b} {x}",
        f"{a} {c} {y}",
        f"{a} {b} {z} {n1}",
        f"{n1} {n2}",
    ]

    # Additional unpredictable cases exercise arbitrary queries and input data.
    for _ in range(6):
        vocab = ["v" + secrets.token_hex(8) for _ in range(16)]
        query_words = rng.sample(vocab, rng.randint(3, 6))
        if rng.randrange(2):
            query_words.insert(rng.randrange(len(query_words) + 1), query_words[0])
        query = " ".join(query_words)

        lines = []
        for _ in range(10):
            selected = rng.sample(vocab, rng.randint(1, 8))
            if rng.randrange(3) == 0:
                selected.insert(rng.randrange(len(selected) + 1), selected[0])
            lines.append(" ".join(selected))
        rng.shuffle(lines)
        yield query, lines


def test_program_jaccard_behavior(executables):
    cases = list(generated_cases())
    for executable in executables:
        for query, lines in cases:
            expected = oracle(query, lines)
            result = subprocess.run(
                [executable, query],
                input="\n".join(lines) + "\n",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, f"{executable} failed for a valid query: {result.stderr}"
            assert result.stdout in (expected, expected + "\n"), (
                f"{executable} returned {result.stdout!r}; expected only the first "
                f"highest-Jaccard input line {expected!r}"
            )


def test_program_requires_exactly_one_argument(executables):
    for executable in executables:
        no_arg = subprocess.run(executable, input="a b\n", text=True, capture_output=True, timeout=5)
        two_args = subprocess.run([executable, "a", "b"], input="a b\n", text=True, capture_output=True, timeout=5)
        assert no_arg.returncode != 0, f"{executable} accepted zero command-line arguments"
        assert two_args.returncode != 0, f"{executable} accepted two command-line arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
