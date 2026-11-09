#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal

import pytest

BASE_DIR = "/home/user/ticket_8831"
PROCESSOR_CPP = os.path.join(BASE_DIR, "processor.cpp")
PROCESSOR = os.path.join(BASE_DIR, "processor")
DATA_TXT = os.path.join(BASE_DIR, "data.txt")
TEST_SH = os.path.join(BASE_DIR, "test.sh")
RESOLUTION_LOG = os.path.join(BASE_DIR, "resolution.log")
VERIFIED_PROCESSOR = "/tmp/ticket_8831_verified_processor"


def expected_output(values):
    total = sum((Decimal(v) for v in values), Decimal(0))
    return f"{total:.6f}\n"


def read_values(path):
    with open(path, "r") as f:
        return f.read().split()


def run_processor(executable, data_path):
    result = subprocess.run(
        [executable, data_path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"processor failed for {data_path} with code {result.returncode}: "
        f"{result.stderr}"
    )
    return result.stdout


def compile_verified_processor():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O0", "-Wall", "-Wextra", PROCESSOR_CPP,
         "-o", VERIFIED_PROCESSOR],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"processor.cpp did not compile: {result.stderr}"


def strip_comments_and_literals(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def test_processor_cpp_fixed():
    """Test that processor.cpp has been fixed according to requirements."""
    assert os.path.isfile(PROCESSOR_CPP), f"File {PROCESSOR_CPP} does not exist."

    with open(PROCESSOR_CPP, 'r') as f:
        content = f.read()

    # Preserve the original source requirements.
    assert "std::vector<double>" in content or "vector<double>" in content, "Did not find vector<double> in processor.cpp"
    assert "float" not in content, "Found 'float' in processor.cpp, it should be completely replaced with 'double'"
    assert "i = 1" not in content, "Loop still appears to start at 1 (off-by-one error)."
    assert "<= n" not in content, "Loop still appears to go up to <= n (off-by-one error)."
    assert content.count("assert(") >= 2, "processor.cpp must contain at least two assert() statements."

    # Ensure the assertions are actual source expressions, not comments or strings.
    active_source = strip_comments_and_literals(content)
    assert len(re.findall(r"\bassert\s*\(", active_source)) >= 2, (
        "processor.cpp must contain at least two active assert() statements"
    )

    compile_verified_processor()


def test_processor_behavior_on_derived_inputs():
    """Compile and exercise the submitted source on independently derived cases."""
    compile_verified_processor()

    cases = [
        ["7.25"],                         # catches skipping index zero
        ["16777216", "1"],               # distinguishes double from float
        ["1.25", "2.50", "3.75", "4"],
    ]

    # Add an unpredictable exact-binary-fraction case whose answer is derived here.
    random_values = []
    for _ in range(31):
        numerator = secrets.randbelow(80001) - 40000
        random_values.append(str(Decimal(numerator) / Decimal(4)))
    cases.append(random_values)

    with tempfile.TemporaryDirectory(prefix="ticket8831_cases_") as tmp:
        for index, values in enumerate(cases):
            path = os.path.join(tmp, f"case_{index}_{secrets.token_hex(6)}.txt")
            with open(path, "w") as f:
                f.write("\n".join(values) + "\n")
            actual = run_processor(VERIFIED_PROCESSOR, path)
            assert actual == expected_output(values), (
                f"Incorrect output for derived case {index}: {actual!r}"
            )


def test_test_sh_exists_and_executable():
    """Test that test.sh exists and is executable."""
    assert os.path.isfile(TEST_SH), f"File {TEST_SH} does not exist."
    assert os.access(TEST_SH, os.X_OK), f"File {TEST_SH} is not executable."


def test_test_sh_execution():
    """Verify test.sh freshly compiles processor.cpp and actually runs it."""
    marker = f"/tmp/ticket8831_run_{secrets.token_hex(16)}"
    source_backup = PROCESSOR_CPP + ".verifier_backup"
    shutil.copyfile(PROCESSOR_CPP, source_backup)

    try:
        with open(PROCESSOR_CPP, "r") as f:
            source = f.read()
        instrumented, replacements = re.subn(
            r"(\bint\s+main\s*\([^)]*\)\s*\{)",
            lambda m: m.group(1) + f'\n    std::ofstream("{marker}").put(\'1\');',
            source,
            count=1,
            flags=re.S,
        )
        assert replacements == 1, "Could not instrument main() to verify execution"
        with open(PROCESSOR_CPP, "w") as f:
            f.write(instrumented)

        if os.path.lexists(PROCESSOR):
            os.remove(PROCESSOR)

        result = subprocess.run(
            [TEST_SH], cwd=BASE_DIR, capture_output=True, text=True, timeout=45
        )
        assert result.returncode == 0, (
            f"test.sh failed to execute with exit code 0. Stderr: {result.stderr}"
        )
        assert os.path.isfile(PROCESSOR), "test.sh did not create the processor executable"
        assert os.access(PROCESSOR, os.X_OK), "processor created by test.sh is not executable"
        with open(PROCESSOR, "rb") as f:
            assert f.read(4) == b"\x7fELF", "test.sh did not produce a compiled executable"
        assert os.path.isfile(marker), "test.sh compiled but did not run the processor"

        expected = expected_output(read_values(DATA_TXT))
        assert run_processor(PROCESSOR, DATA_TXT) == expected, (
            "processor produced by test.sh gives an incorrect result"
        )
    finally:
        if os.path.exists(source_backup):
            shutil.move(source_backup, PROCESSOR_CPP)
        if os.path.exists(marker):
            os.remove(marker)


def test_resolution_log():
    """Test that resolution.log is the exact standard output of the fixed program."""
    assert os.path.isfile(RESOLUTION_LOG), f"File {RESOLUTION_LOG} does not exist."

    with open(RESOLUTION_LOG, 'r') as f:
        content = f.read().strip()

    # Preserve the original fixed-dataset assertion.
    expected_sum = "100001000.000000"
    assert expected_sum in content, f"resolution.log does not contain the correct sum '{expected_sum}'. Content found: '{content}'"

    compile_verified_processor()
    actual_stdout = run_processor(VERIFIED_PROCESSOR, DATA_TXT)
    derived_expected = expected_output(read_values(DATA_TXT))
    assert actual_stdout == derived_expected, "The compiled processor gives an incorrect dataset total"

    with open(RESOLUTION_LOG, "r") as f:
        log_text = f.read()
    assert log_text == actual_stdout, (
        "resolution.log must contain exactly the processor's standard output"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
