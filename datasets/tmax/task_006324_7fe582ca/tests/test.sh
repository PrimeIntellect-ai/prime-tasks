#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "align_fit.c")


def read_text(path):
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_bottleneck_txt():
    path = os.path.join(HOME, "bottleneck.txt")
    content = read_text(path).strip()
    assert content == "waste_time", f"Expected 'waste_time' in {path}, but got '{content}'"


def test_align_fit_optimized():
    content = read_text(SOURCE)

    # Preserve the original assertion.
    assert "waste_time();" not in content.replace(" ", ""), \
        "The call to waste_time() was not removed from align_fit.c"

    # Also inspect the complete score_alignment body so whitespace cannot hide the call.
    match = re.search(r"\bscore_alignment\s*\([^)]*\)\s*\{", content)
    assert match, "Could not find a definition of score_alignment"
    start = match.end() - 1
    depth = 0
    end = None
    for pos in range(start, len(content)):
        if content[pos] == "{":
            depth += 1
        elif content[pos] == "}":
            depth -= 1
            if depth == 0:
                end = pos
                break
    assert end is not None, "score_alignment has an unterminated function body"
    body = content[start + 1:end]
    assert not re.search(r"\bwaste_time\s*\(", body), \
        "The call to waste_time() was not removed from score_alignment"


def test_compiled_program_and_score_alignment():
    with tempfile.TemporaryDirectory() as td:
        program = os.path.join(td, "align_fit")
        obj = os.path.join(td, "align_fit.o")
        harness_c = os.path.join(td, "harness.c")
        harness = os.path.join(td, "harness")

        # Compile and execute the submitted artifact as the requested optimized program.
        subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", program],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        run = subprocess.run(
            [program], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10
        )

        regression_path = os.path.join(HOME, "regression_result.txt")
        assert os.path.isfile(regression_path), f"File {regression_path} is missing."
        with open(regression_path, "rb") as f:
            regression = f.read()
        assert run.stdout == regression, \
            "regression_result.txt is not the actual stdout of the optimized program"

        expected_path = os.path.join(HOME, "expected_result.txt")
        assert os.path.isfile(expected_path), f"File {expected_path} is missing."
        with open(expected_path, "rb") as f:
            expected = f.read()
        assert regression == expected, \
            "regression_result.txt does not exactly match expected_result.txt"

        # Exercise score_alignment on verifier-generated inputs rather than trusting
        # only the fixed regression output.
        subprocess.run(
            ["gcc", "-O2", "-Dmain=align_fit_program_main", "-c", SOURCE, "-o", obj],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        with open(harness_c, "w", encoding="utf-8") as f:
            f.write(
                '#include <stdio.h>\n'
                'int score_alignment(const char *primer);\n'
                'int main(int argc, char **argv) {\n'
                '  for (int i = 1; i < argc; ++i) printf("%d\\n", score_alignment(argv[i]));\n'
                '  return 0;\n'
                '}\n'
            )
        subprocess.run(
            ["gcc", "-O2", harness_c, obj, "-o", harness],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )

        alphabet = "ACGT"
        lengths = [0, 1, 2, 3, 5, 8, 13, 21, 34, 55]
        primers = ["".join(secrets.choice(alphabet) for _ in range(n)) for n in lengths]
        checked = subprocess.run(
            [harness] + primers, check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        scores = [int(line) for line in checked.stdout.splitlines()]
        assert scores == [2 * len(primer) for primer in primers], \
            "score_alignment does not calculate the required scores on verifier-generated inputs"


def test_regression_result_txt():
    path = os.path.join(HOME, "regression_result.txt")
    content = read_text(path).strip()
    assert content == "Slope: 2.00, Intercept: 0.00", \
        f"Expected 'Slope: 2.00, Intercept: 0.00' in {path}, but got '{content}'"


def test_test_status_txt():
    path = os.path.join(HOME, "test_status.txt")
    content = read_text(path).strip()
    assert content == "PASS", f"Expected 'PASS' in {path}, but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
