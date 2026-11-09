#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import string
import subprocess
import tempfile

AGENT_SCRIPT = "/home/user/robust_filter.py"
LEGACY_FILTER = "/app/legacy_filter"
rng = secrets.SystemRandom()


def expected_output(content, column):
    output = []
    for line in content.splitlines(keepends=True):
        logical = line[:-1] if line.endswith("\n") else line
        words = re.findall(r"[^ \t]+", logical)
        if 0 <= column - 1 < len(words):
            word = words[column - 1]
            if len(word) >= 2 and word == word[::-1]:
                output.append(line)
    return "".join(output)


def run_agent(content, column):
    with tempfile.NamedTemporaryFile(mode="w", delete=False, newline="") as f:
        f.write(content)
        path = f.name
    try:
        result = subprocess.run(
            ["python3", AGENT_SCRIPT, str(column), path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"robust_filter exited with {result.returncode}; stderr={result.stderr!r}"
        )
        assert result.stdout == expected_output(content, column), (
            f"Incorrect output for column {column}. "
            f"Expected {expected_output(content, column)!r}, got {result.stdout!r}"
        )
    finally:
        os.remove(path)


def random_word(min_len=3, max_len=18):
    return "".join(rng.choice(string.ascii_lowercase) for _ in range(rng.randint(min_len, max_len)))


def palindrome():
    half = random_word(2, 10)
    return half + rng.choice(string.ascii_lowercase) + half[::-1]


def non_palindrome():
    while True:
        word = random_word(3, 20)
        if word != word[::-1]:
            return word


def test_required_artifacts_and_legacy_repair():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert stat.S_IMODE(os.stat(AGENT_SCRIPT).st_mode) & 0o111, (
        f"{AGENT_SCRIPT} is not executable"
    )

    assert os.path.exists(LEGACY_FILTER), f"Legacy filter not found at {LEGACY_FILTER}"
    assert os.path.isfile(LEGACY_FILTER), f"{LEGACY_FILTER} is not a file"
    assert stat.S_IMODE(os.stat(LEGACY_FILTER).st_mode) & 0o111, (
        f"{LEGACY_FILTER} was not made executable"
    )

    marker = random_word()
    pal = palindrome()
    other = non_palindrome()
    content = f"{marker} {pal} tail\n{random_word()} {other} tail\n"
    with tempfile.NamedTemporaryFile(mode="w", delete=False, newline="") as f:
        f.write(content)
        path = f.name
    try:
        result = subprocess.run(
            [LEGACY_FILTER, "2", path], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, (
            f"legacy_filter did not run successfully: return code {result.returncode}, "
            f"stderr={result.stderr!r}"
        )
        assert result.stdout == expected_output(content, 2), (
            "legacy_filter produced incorrect output on a safe smoke test"
        )
    finally:
        os.remove(path)


def test_original_accuracy_case_exactly():
    test_log_content = """\
123 abc racecar def
456 def hello world
789 ghi level jkl
101 jkl noon mno
112 mno a pqr
131 pqr radar stu
long_line_start """ + "a" * 150 + """ kayak end
short
another_long_line """ + "b" * 150 + """ notpalindrome end
"""
    run_agent(test_log_content, 3)


def test_randomized_columns_order_duplicates_and_long_lines():
    for column in (1, 2, 3, 5, rng.randint(1, 7), rng.randint(1, 7)):
        matching_lines = []
        lines = []

        for i in range(18):
            enough_columns = rng.choice([True, True, True, False])
            count = rng.randint(column, column + 4) if enough_columns else rng.randint(0, max(0, column - 1))
            words = [random_word() for _ in range(count)]
            should_match = enough_columns and rng.choice([True, False])
            if enough_columns:
                words[column - 1] = palindrome() if should_match else non_palindrome()

            if i == 4 and words:
                words[0] = random_word() * 30
            separator = rng.choice([" ", "  ", "\t", " \t "])
            line = separator.join(words) + "\n"
            lines.append(line)
            if should_match:
                matching_lines.append(line)

        # Guarantee matches and duplicate-line semantics, while retaining their order.
        duplicate_words = [random_word() for _ in range(max(column, 3))]
        duplicate_words[column - 1] = palindrome()
        duplicate_line = "\t".join(duplicate_words) + "\n"
        insert_at = rng.randint(0, len(lines))
        lines[insert_at:insert_at] = [duplicate_line, duplicate_line]

        # Exercise a physical line far beyond the legacy C buffer size.
        long_words = [random_word() for _ in range(max(column, 4))]
        long_words[column - 1] = palindrome()
        long_words[-1] = random_word() * 80
        lines.append("  ".join(long_words) + "\n")

        rng.shuffle(lines)
        # Also verify preservation of a final matching line without a trailing newline.
        final_words = [random_word() for _ in range(max(column, 2))]
        final_words[column - 1] = palindrome()
        content = "".join(lines) + " ".join(final_words)
        run_agent(content, column)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
