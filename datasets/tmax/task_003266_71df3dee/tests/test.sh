#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')

EXPECTED_MAKEFILE = '''CC=gcc
CFLAGS=-I./include -lm

all: app

generator: src/generator.c
\t$(CC) src/generator.c -o generator $(CFLAGS)

tables: generator
\t# In a real run, this would be: cat data/inputs.txt | xargs -P 4 ...
\t# We are hardcoding the script that contains the failed log state for the task
\tbash ./generate.sh || exit 1

app: tables src/main.c
\t$(CC) src/main.c -o app $(CFLAGS)

clean:
\trm -f generator app include/tables.h build.log
'''

EXPECTED_GENERATE_SH = '''#!/bin/bash
set -e
mkdir -p include
echo "// Generated tables" > include/tables.h
while IFS= read -r value; do
    [ -z "$value" ] || ./generator "$value" >> include/tables.h
done < data/inputs.txt
'''


def run_app_and_check(app_path):
    assert os.path.isfile(app_path), f"The compiled binary {app_path} is missing. Did you run 'make'?"
    assert os.access(app_path, os.X_OK), f"{app_path} is not executable."
    with open(app_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{app_path} is not a compiled ELF binary."
    try:
        result = subprocess.run([app_path], capture_output=True, text=True, timeout=2)
        assert result.returncode == 0, f"Running {app_path} failed with return code {result.returncode}."
        assert "Application initialized successfully." in result.stdout, f"Unexpected output from {app_path}: {result.stdout}"
    except subprocess.TimeoutExpired:
        pytest.fail(f"Running {app_path} timed out. There might be an infinite loop in the generator or app.")
    except Exception as e:
        pytest.fail(f"Failed to run {app_path}: {e}")


def test_mre_txt_contains_correct_value():
    mre_path = PROJECT / 'mre.txt'
    assert os.path.isfile(mre_path), f"{mre_path} is missing. You must create it."
    content = mre_path.read_text().strip()

    # Preserve the original timeline assertion and additionally require the requested exact MRE.
    assert "16.0" in content, f"{mre_path} does not contain the correct failing input value. Check the build.log timeline carefully."
    assert content == "16.0", f"{mre_path} must contain only the exact failing input value 16.0."


def test_build_system_was_not_changed():
    assert (PROJECT / 'Makefile').read_text() == EXPECTED_MAKEFILE, 'The Makefile was changed.'
    assert (PROJECT / 'generate.sh').read_text() == EXPECTED_GENERATE_SH, 'generate.sh was changed.'


def test_generator_c_is_fixed():
    generator_path = PROJECT / 'src/generator.c'
    assert os.path.isfile(generator_path), f"{generator_path} is missing."
    content = generator_path.read_text()

    # Preserve the original source assertion.
    assert "double df = 2.0;" not in content, "The bug in src/generator.c has not been fixed. The derivative of x^2 - n is 2x, not 2."


def test_submitted_app_already_exists_and_runs():
    run_app_and_check(str(PROJECT / 'app'))


def test_generator_numerically_computes_square_roots():
    source = PROJECT / 'src/generator.c'
    binary = '/tmp/verified_generator'
    compile_result = subprocess.run(
        ['gcc', str(source), '-o', binary, '-I' + str(PROJECT / 'include'), '-lm'],
        capture_output=True, text=True, timeout=10
    )
    assert compile_result.returncode == 0, f"generator.c does not compile:\n{compile_result.stderr}"

    values = [0.01, 0.25, 1.0, 2.0, 3.0, 4.0, 16.0, 25.0, 64.0, 81.0, 10000.0]
    rng = random.Random(734921)
    values.extend(10 ** rng.uniform(-2, 6) for _ in range(24))

    for value in values:
        try:
            result = subprocess.run([binary, format(value, '.17g')], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail(f"generator timed out for positive input {value}")
        assert result.returncode == 0, (
            f"generator failed for positive input {value} with status {result.returncode}: {result.stderr}"
        )
        match = re.search(r'(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*$', result.stdout)
        assert match, f"generator produced malformed output for {value}: {result.stdout!r}"
        actual = float(match.group(1))
        expected = math.sqrt(value)
        assert math.isfinite(actual) and math.isclose(actual, expected, rel_tol=2e-5, abs_tol=2e-6), (
            f"generator returned {actual} for {value}; expected approximately {expected}"
        )


def test_make_rebuilds_real_application_and_tables():
    result = subprocess.run(
        ['make', '-B', 'all'], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"A full make rebuild failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    # Recheck that executing the submitted generator did not rewrite the build system.
    assert (PROJECT / 'Makefile').read_text() == EXPECTED_MAKEFILE, 'The build changed the Makefile.'
    assert (PROJECT / 'generate.sh').read_text() == EXPECTED_GENERATE_SH, 'The build changed generate.sh.'

    tables = (PROJECT / 'include/tables.h').read_text()
    for value in (4, 16, 25, 64):
        match = re.search(rf'^#define\s+SQRT_{value}\s+(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*$', tables, re.MULTILINE)
        assert match, f"tables.h is missing the generated square root for {value}."
        assert math.isclose(float(match.group(1)), math.sqrt(value), rel_tol=1e-6, abs_tol=1e-6)

    run_app_and_check(str(PROJECT / 'app'))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
