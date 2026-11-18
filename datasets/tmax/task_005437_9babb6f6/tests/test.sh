#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/filter"
SOURCE = "/home/user/filter.cpp"
EIGEN_INCLUDE = "/app/vendor/eigen"


def run_checked(executable, path, expected):
    result = subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=5
    )
    expected_code = 0 if expected == "ACCEPT" else 1
    assert result.returncode == expected_code, (
        f"{executable} returned {result.returncode} for {path}; "
        f"expected {expected_code}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"{executable} printed {result.stdout!r} for {path}; expected {expected!r}"
    )


def expected_for_tokens(tokens):
    values = [float(token) for token in tokens]
    if any(math.isnan(value) for value in values):
        return "REJECT"
    norm = math.sqrt(sum(value * value for value in values))
    return "REJECT" if norm > 50.0 else "ACCEPT"


def test_eigen_fixed():
    math_functions_path = "/app/vendor/eigen/Eigen/src/Core/MathFunctions.h"
    assert os.path.isfile(math_functions_path), f"{math_functions_path} is missing"
    with open(math_functions_path, "r") as f:
        content = f.read()
    assert "Deliberate perturbation" not in content, "Vendored package not fixed: perturbation still present in MathFunctions.h"


def test_eigen_compiles_nan_check(tmp_path):
    source = tmp_path / "eigen_nan_smoke.cpp"
    output = tmp_path / "eigen_nan_smoke"
    source.write_text(
        "#include <Eigen/Dense>\n"
        "#include <limits>\n"
        "int main() {\n"
        "  Eigen::VectorXf v(2);\n"
        "  v << 1.0f, std::numeric_limits<float>::quiet_NaN();\n"
        "  return v.array().isNaN().any() ? 0 : 1;\n"
        "}\n"
    )
    build = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", "-I" + EIGEN_INCLUDE, str(source), "-o", str(output)],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Fixed Eigen does not compile for NaN checking:\n{build.stderr}"
    result = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Eigen NaN check did not detect a quiet NaN"


def test_executable_exists():
    executable = EXECUTABLE
    assert os.path.isfile(executable), f"Executable {executable} not found"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable"


def test_clean_corpus():
    executable = EXECUTABLE
    clean_files = glob.glob("/home/user/corpora/clean/*")
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []
    for f in clean_files:
        result = subprocess.run([executable, f], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    executable = EXECUTABLE
    evil_files = glob.glob("/home/user/corpora/evil/*")
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []
    for f in evil_files:
        result = subprocess.run([executable, f], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_files)}"


@pytest.fixture(scope="session")
def compiled_source(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} not found"
    source_text = open(SOURCE, "r").read()
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source_text, flags=re.S)
    assert re.search(r"#\s*include\s*[<\"]Eigen/", without_comments), (
        "filter.cpp must include the vendored Eigen headers"
    )
    assert re.search(r"\bEigen\s*::", without_comments), (
        "filter.cpp must use Eigen for the embedding implementation"
    )

    build_dir = tmp_path_factory.mktemp("source_build")
    output = build_dir / ("filter_" + uuid.uuid4().hex)
    build = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", "-O2", "-I" + EIGEN_INCLUDE, SOURCE, "-o", str(output)],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, (
        "filter.cpp does not compile against the fixed vendored Eigen library:\n"
        + build.stderr
    )
    return str(output)


def test_generated_vectors(compiled_source):
    rng = random.SystemRandom()
    cases = [
        ["0"],
        ["30", "40"],
        ["-30", "-40"],
        ["30", "40", "0.25"],
        ["0.5", "NaN", "-0.5"],
        ["nan"],
        ["1", "2", "3", "NAN", "4"],
        ["inf", "0"],
        ["-inf", "1"],
    ]

    for length in [2, 7, 31, 128]:
        for target_norm in [rng.uniform(0.1, 45.0), rng.uniform(55.0, 180.0)]:
            raw = [rng.uniform(-1.0, 1.0) for _ in range(length)]
            raw_norm = math.sqrt(sum(x * x for x in raw))
            values = [x * target_norm / raw_norm for x in raw]
            cases.append([format(x, ".9g") for x in values])

        values = [format(rng.uniform(-4.0, 4.0), ".9g") for _ in range(length)]
        values[rng.randrange(length)] = rng.choice(["NaN", "nan", "NAN"])
        cases.append(values)

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="embedding_validation_") as directory:
        generated = []
        for tokens in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".vec")
            with open(path, "w") as f:
                f.write(" ".join(tokens) + "\n")
            generated.append((path, expected_for_tokens(tokens)))

        assert any(expected == "ACCEPT" for _, expected in generated)
        assert any(expected == "REJECT" for _, expected in generated)
        for executable in (EXECUTABLE, compiled_source):
            for path, expected in generated:
                run_checked(executable, path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
