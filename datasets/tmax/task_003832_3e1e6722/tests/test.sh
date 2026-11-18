#!/bin/bash
set -e
mkdir -p /logs/verifier

# The oracle is intentionally available while the agent works, but must not be
# callable by the submitted script during verification.
rm -f /app/score_oracle
chmod 700 /tests 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/score.sh"
NUMERIC_OUTPUT = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\n?")
ANIMALS = ("cat", "dog", "bird", "fish")
WEIGHTS = {"cat": 2.5, "dog": 1.2, "bird": -0.8, "fish": 0.5}


def expected_score(text):
    counts = dict.fromkeys(ANIMALS, 0)
    for token in text.split():
        clean = token.translate(str.maketrans("", "", ".,!?")).lower()
        if clean in counts:
            counts[clean] += 1
    return 1.0 + sum(WEIGHTS[word] * counts[word] for word in ANIMALS)


def random_case(word):
    return "".join(ch.upper() if secrets.randbelow(2) else ch.lower() for ch in word)


def generate_text():
    ordinary = ["apple", "tree", "car", "house", "river", "stone", "cloud", "green"]
    decoys = ["cats", "dogma", "birdhouse", "fishing", "cat-dog", "(cat)", "fish/bird"]
    tokens = []

    for animal in ANIMALS:
        for _ in range(secrets.randbelow(15)):
            token = random_case(animal)
            for _ in range(secrets.randbelow(4)):
                pos = secrets.randbelow(len(token) + 1)
                token = token[:pos] + secrets.choice(".,!?") + token[pos:]
            tokens.append(token)

    for _ in range(20 + secrets.randbelow(50)):
        tokens.append(secrets.choice(ordinary + decoys))

    # Fisher-Yates shuffle using system randomness, so outputs cannot be tied to
    # a fixed seeded hold-out set.
    for i in range(len(tokens) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        tokens[i], tokens[j] = tokens[j], tokens[i]

    separators = [" ", "  ", "\n", "\t", " \n "]
    return "".join(token + (secrets.choice(separators) if i + 1 < len(tokens) else "")
                   for i, token in enumerate(tokens))


def test_score_script_mse():
    assert os.path.exists(SCRIPT_PATH), f"User script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    mse = 0.0
    n = 40
    test_dir = "/tmp/score_holdout"
    os.makedirs(test_dir, mode=0o755, exist_ok=True)

    for i in range(n):
        text = generate_text()
        test_file = os.path.join(test_dir, f"case_{secrets.token_hex(12)}.txt")
        with open(test_file, "w") as f:
            f.write(text)
        os.chmod(test_file, 0o644)

        expected = expected_score(text)
        try:
            result = subprocess.run(
                ["runuser", "-u", "user", "--", "bash", SCRIPT_PATH, test_file],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=True,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"User script failed on hold-out case: {e}")

        assert NUMERIC_OUTPUT.fullmatch(result.stdout), \
            f"User output is not strictly numerical: {result.stdout!r}"
        try:
            agent_val = float(result.stdout)
        except ValueError:
            pytest.fail(f"User output is not a float: {result.stdout!r}")

        diff = expected - agent_val
        mse += diff * diff

    mse /= n
    threshold = 0.05
    assert mse <= threshold, f"MSE {mse:.5f} exceeds the threshold of {threshold}"
TEST_EOF
chmod 600 /tmp/test_final_state.py

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
