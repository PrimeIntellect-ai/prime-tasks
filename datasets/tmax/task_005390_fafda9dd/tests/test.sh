#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
DATASET_PATH = "/home/user/dataset.csv"


def expected_output():
    truth_script = r'''
set -o pipefail
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
/usr/bin/gawk -F, '
NR>1 { z[++n] = $1 * $2 }
END {
    srand(123);
    for (i=1; i<=1000; i++) {
        sum = 0;
        for (j=1; j<=n; j++) {
            idx = int(rand() * n) + 1;
            sum += z[idx];
        }
        mean = sum / n;
        printf "%.6f\n", mean;
    }
}' /home/user/dataset.csv | /usr/bin/sort -n > "$tmp"
LOWER=$(/usr/bin/head -n 25 "$tmp" | /usr/bin/tail -n 1)
UPPER=$(/usr/bin/head -n 975 "$tmp" | /usr/bin/tail -n 1)
printf "CI: [%.4f, %.4f]\n" "$LOWER" "$UPPER"
'''
    result = subprocess.run(
        ["bash", "-c", truth_script], capture_output=True, text=True
    )
    assert result.returncode == 0, f"Truth computation failed: {result.stderr}"
    return result.stdout.strip()


def run_student():
    result = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    return result.stdout.strip()


def begin_blocks(source):
    blocks = []
    for match in re.finditer(r"\bBEGIN\s*\{", source):
        start = source.find("{", match.start())
        depth = 0
        for pos in range(start, len(source)):
            if source[pos] == "{":
                depth += 1
            elif source[pos] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(source[start + 1:pos])
                    break
    return blocks


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_analyze_script_no_python_or_r():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read().lower()

    assert "python" not in content, "Script must not use Python."
    assert "rscript" not in content, "Script must not use R."


def test_required_gawk_rng_source():
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()

    # Remove comments so required constructs cannot be satisfied by comments alone.
    checked = re.sub(r"#.*$", "", source, flags=re.MULTILINE)
    assert re.search(r"\bgawk\b", checked), "Sampling must be performed with gawk."

    srand_calls = re.findall(r"\bsrand\s*\([^)]*\)", checked)
    assert len(srand_calls) == 1, "srand must be called exactly once."
    assert re.fullmatch(r"srand\s*\(\s*123\s*\)", srand_calls[0]), \
        "The single srand call must be srand(123)."

    blocks = begin_blocks(checked)
    assert any(re.search(r"\bsrand\s*\(\s*123\s*\)", block) for block in blocks), \
        "srand(123) must be called in a gawk BEGIN block."

    rand_calls = re.findall(r"\brand\s*\(\s*\)", checked)
    assert len(rand_calls) == 1, "The sampling expression must contain one rand() call."
    formula = re.compile(
        r"\bidx\s*=\s*int\s*\(\s*rand\s*\(\s*\)\s*\*\s*[A-Za-z_]\w*\s*\)\s*\+\s*1\b"
    )
    assert formula.search(checked), \
        "Sampling must use idx = int(rand() * N) + 1."


def test_analyze_script_output():
    expected = expected_output()
    student_output = run_student()
    assert student_output == expected, \
        f"Expected output '{expected}', but got '{student_output}'"


def test_pipeline_on_additional_datasets():
    with open(DATASET_PATH, "rb") as f:
        original = f.read()

    rng = random.SystemRandom()
    try:
        # Powers of two keep bootstrap means exactly representable at the
        # requested precision while varying both the data and row count.
        for n in (1, 4, 8, 16):
            rows = ["X,Y"]
            for _ in range(n):
                x = rng.randint(1, 40)
                y = rng.randint(1, 40)
                rows.append(f"{x},{y}")
            with open(DATASET_PATH, "w") as f:
                f.write("\n".join(rows) + "\n")

            expected = expected_output()
            student_output = run_student()
            assert student_output == expected, \
                f"For a generated {n}-row dataset, expected '{expected}', got '{student_output}'"
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
