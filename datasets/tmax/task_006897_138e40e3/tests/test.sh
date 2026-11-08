#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/evaluate.cpp"
EXE_PATH = "/home/user/evaluate"
REPORT_PATH = "/home/user/report.txt"


def assert_correct_report(path):
    assert os.path.isfile(path), f"File {path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content, f"File {path} is empty."
    assert re.search(r"Best Threshold:\s*0\.1", content), \
        f"Could not find 'Best Threshold: 0.1' in {path}. Found:\n{content}"
    assert re.search(r"Accuracy:\s*1(\.0*)?", content), \
        f"Could not find 'Accuracy: 1' (or 1.0) in {path}. Found:\n{content}"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."

    work = tempfile.mkdtemp(prefix="evaluate_verify_")
    rebuilt = os.path.join(work, "evaluate_from_source")
    compile_result = subprocess.run(
        ["g++", "-std=c++14", SOURCE_PATH, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, \
        f"evaluate.cpp does not compile with g++ -std=c++14:\n{compile_result.stderr}"

    source_run_dir = os.path.join(work, "source_run")
    os.mkdir(source_run_dir)
    rebuilt_run = subprocess.run(
        [rebuilt], cwd=source_run_dir,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert rebuilt_run.returncode == 0, \
        f"The executable rebuilt from evaluate.cpp failed:\n{rebuilt_run.stderr}"
    assert_correct_report(os.path.join(source_run_dir, "report.txt"))

    harness_cpp = os.path.join(work, "feature_harness.cpp")
    harness_exe = os.path.join(work, "feature_harness")
    with open(harness_cpp, "w") as f:
        f.write(r'''#include <iostream>
#include <iomanip>
#include <string>
#define main evaluate_program_main
#include "/home/user/evaluate.cpp"
#undef main
int main() {
    std::string text;
    while (std::getline(std::cin, text)) {
        std::cout << std::setprecision(17) << compute_feature(text) << "\n";
    }
    return 0;
}
''')
    harness_compile = subprocess.run(
        ["g++", "-std=c++14", harness_cpp, "-o", harness_exe],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert harness_compile.returncode == 0, \
        f"Could not test compute_feature from evaluate.cpp:\n{harness_compile.stderr}"

    assert os.path.isfile(EXE_PATH), \
        f"Executable {EXE_PATH} does not exist. Did you compile the script?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "The evaluate artifact is not a compiled native executable."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    submitted_run = subprocess.run(
        [EXE_PATH], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert submitted_run.returncode == 0, \
        f"Running /home/user/evaluate failed:\n{submitted_run.stderr}"

    return {"harness": harness_exe, "rebuilt_report": os.path.join(source_run_dir, "report.txt")}


def test_compute_feature(build_and_run_submission):
    cases = [
        "", "a", "B", "AEIOU", "xyz", "Hello World", "beautiful day",
        "12345!", "A quick BROWN fox", "uUuU", " vowels and spaces "
    ]
    alphabet = string.ascii_letters + string.digits + " !?.,-_"
    rng = random.SystemRandom()
    for _ in range(40):
        cases.append("".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 100))))

    result = subprocess.run(
        [build_and_run_submission["harness"]],
        input="\n".join(cases) + "\n",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, f"compute_feature test harness failed:\n{result.stderr}"
    outputs = result.stdout.splitlines()
    assert len(outputs) == len(cases), \
        f"Expected {len(cases)} feature results, got {len(outputs)}."

    for text, raw in zip(cases, outputs):
        try:
            actual = float(raw)
        except ValueError:
            pytest.fail(f"compute_feature produced a non-numeric result for {text!r}: {raw!r}")
        expected = 0.0 if not text else sum(c.lower() in "aeiou" for c in text) / len(text)
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12), \
            f"compute_feature({text!r}) returned {actual}, expected {expected}"


def test_rebuilt_source_report(build_and_run_submission):
    assert_correct_report(build_and_run_submission["rebuilt_report"])


def test_executable_exists():
    """Test that the evaluate executable was compiled."""
    exe_path = "/home/user/evaluate"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist. Did you compile the script?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def test_report_exists():
    """Test that report.txt was successfully created."""
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"File {report_path} was not created. Did you fix the file writing bug and run the executable?"


def test_report_content():
    """Test that report.txt contains the correct results."""
    report_path = "/home/user/report.txt"
    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {report_path} is empty."

    threshold_match = re.search(r"Best Threshold:\s*0\.1", content)
    assert threshold_match, f"Could not find 'Best Threshold: 0.1' in {report_path}. Found:\n{content}"

    accuracy_match = re.search(r"Accuracy:\s*1(\.0*)?", content)
    assert accuracy_match, f"Could not find 'Accuracy: 1' (or 1.0) in {report_path}. Found:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
