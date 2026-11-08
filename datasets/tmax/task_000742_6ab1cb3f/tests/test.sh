#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
from collections import Counter

TOP_WORDS_PATH = "/home/user/data_pipeline/top_words.txt"
VERIFY_SCRIPT_PATH = "/home/user/data_pipeline/verify.sh"
PROCESS_SCRIPT_PATH = "/home/user/data_pipeline/process.sh"
DATA_PATH = "/home/user/data_pipeline/data.tsv"
PIPELINE_DIR = "/home/user/data_pipeline"

EXPECTED_TOP_WORDS = """5 the
3 systematic
2 dog
2 enterprise
2 fox
"""
EXPECTED_LINES = EXPECTED_TOP_WORDS.splitlines()


def read_output_lines():
    with open(TOP_WORDS_PATH, "r") as f:
        content = f.read()
    lines = content.splitlines()
    assert len(lines) == 5, f"Expected exactly 5 lines, got {len(lines)}: {lines!r}"
    for line in lines:
        assert re.fullmatch(r"[0-9]+ [a-z]+", line), \
            f"Invalid output formatting (must be count, one space, word): {line!r}"
    return lines


def test_top_words_exists_and_correct():
    assert os.path.isfile(TOP_WORDS_PATH), f"{TOP_WORDS_PATH} is missing."
    actual_lines = read_output_lines()
    assert actual_lines == EXPECTED_LINES, \
        f"Contents of {TOP_WORDS_PATH} do not match the expected output. Got: {actual_lines}"


def test_process_script_exists_and_processes_derived_inputs():
    assert os.path.isfile(PROCESS_SCRIPT_PATH), f"{PROCESS_SCRIPT_PATH} is missing."

    with open(PROCESS_SCRIPT_PATH, "r") as f:
        process_source = f.read()
    assert process_source.startswith("#!") and "bash" in process_source.splitlines()[0], \
        f"{PROCESS_SCRIPT_PATH} must be a Bash script."
    assert not re.search(r"(^|[;&|]\s*)(python[0-9]*|perl)(\s|$)", process_source, re.MULTILINE), \
        "process.sh must not invoke Python or Perl."

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_top = None
    if os.path.exists(TOP_WORDS_PATH):
        with open(TOP_WORDS_PATH, "rb") as f:
            original_top = f.read()

    alphabet = string.ascii_lowercase

    def random_word():
        return "w" + "".join(secrets.choice(alphabet) for _ in range(11))

    try:
        # Use fresh words on every verifier run, so process.sh must actually
        # derive its answer from data.tsv rather than contain a fixed answer.
        words = []
        while len(words) < 8:
            candidate = random_word()
            if candidate not in words:
                words.append(candidate)

        counts = [11, 9, 7, 7, 5, 4, 3, 1]
        descriptions = [[], [], [], []]
        all_description_text = []
        position = 0
        for word, count in zip(words, counts):
            for occurrence in range(count):
                rendered = word.upper() if occurrence % 2 else word
                # Digits and punctuation must delimit words and must not appear
                # in the resulting tokens.
                token = rendered + ("!!!" if occurrence % 3 else "123")
                descriptions[position % len(descriptions)].append(token)
                all_description_text.append(token)
                position += 1

        rows = ["id\tcategory\tdescription"]
        for index, tokens in enumerate(descriptions, 1):
            # If a solution processes columns other than description, this
            # repeated alphabetic category text will corrupt the result.
            category = " ".join(["categorytrap"] * 20)
            rows.append(f"{index}\t{category}\t{' '.join(tokens)}")
        with open(DATA_PATH, "w") as f:
            f.write("\n".join(rows) + "\n")

        derived_counts = Counter()
        for text in all_description_text:
            derived_counts.update(re.findall(r"[a-z]+", text.lower()))
        expected = [f"{count} {word}" for word, count in
                    sorted(derived_counts.items(), key=lambda item: (-item[1], item[0]))[:5]]

        if os.path.exists(TOP_WORDS_PATH):
            os.remove(TOP_WORDS_PATH)
        result = subprocess.run(
            ["bash", PROCESS_SCRIPT_PATH],
            cwd=PIPELINE_DIR,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"process.sh failed with code {result.returncode}: {result.stderr}"
        assert os.path.isfile(TOP_WORDS_PATH), "process.sh did not create top_words.txt."
        actual = read_output_lines()
        assert actual == expected, \
            f"process.sh produced {actual!r}; expected derived result {expected!r}"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_top is None:
            if os.path.exists(TOP_WORDS_PATH):
                os.remove(TOP_WORDS_PATH)
        else:
            with open(TOP_WORDS_PATH, "wb") as f:
                f.write(original_top)


def test_verify_script_exists_and_executable():
    assert os.path.isfile(VERIFY_SCRIPT_PATH), f"{VERIFY_SCRIPT_PATH} is missing."


def test_verify_script_behavior():
    result_correct = subprocess.run(["bash", VERIFY_SCRIPT_PATH], capture_output=True)
    assert result_correct.returncode == 0, \
        f"{VERIFY_SCRIPT_PATH} should return exit code 0 when top_words.txt is correct."

    with open(TOP_WORDS_PATH, "r") as f:
        original_content = f.read()

    invalid_contents = [
        "5 the\n3 systematic\n2 dog\n2 enterprise\n2 WRONGWORD\n",
        "5 the\n3 systematic\n2 dog\n2 enterprise\n",
        " 5 the\n3 systematic\n2 dog\n2 enterprise\n2 fox\n",
        "5  the\n3 systematic\n2 dog\n2 enterprise\n2 fox\n",
        "5 the \n3 systematic\n2 dog\n2 enterprise\n2 fox\n",
    ]

    try:
        for invalid in invalid_contents:
            with open(TOP_WORDS_PATH, "w") as f:
                f.write(invalid)
            result_incorrect = subprocess.run(["bash", VERIFY_SCRIPT_PATH], capture_output=True)
            assert result_incorrect.returncode == 1, \
                f"verify.sh should reject inaccurate or incorrectly formatted content: {invalid!r}"
    finally:
        with open(TOP_WORDS_PATH, "w") as f:
            f.write(original_content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
