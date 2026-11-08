#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import json
import random
import shutil
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/fitter_project"
EMPIRICAL = "/home/user/empirical.csv"
RESULT = "/home/user/kl_result.txt"


def test_project_directory_exists():
    assert os.path.isdir(PROJECT), "Directory /home/user/fitter_project does not exist."


def test_cmake_lists_exists():
    assert os.path.isfile(os.path.join(PROJECT, "CMakeLists.txt")), "CMakeLists.txt is missing in /home/user/fitter_project."


def test_cpp_source_exists():
    files = os.listdir(PROJECT)
    cpp_files = [f for f in files if f.endswith(".cpp") or f.endswith(".cc") or f.endswith(".cxx")]
    assert len(cpp_files) > 0, "No C++ source files found in /home/user/fitter_project."


def test_executable_exists():
    # Executable could be in the project dir or a build subdirectory
    found = False
    for root, dirs, files in os.walk(PROJECT):
        if "model_fitter" in files:
            found = True
            break
    assert found, "Executable 'model_fitter' not found in /home/user/fitter_project or its subdirectories."


def test_cmake_requires_cxx11_or_later():
    with open(os.path.join(PROJECT, "CMakeLists.txt"), "r", errors="replace") as f:
        cmake = f.read().lower()
    standards = re.findall(r"cxx_standard[^0-9]*(11|14|17|20|23|26)", cmake)
    features = re.findall(r"cxx_std_(11|14|17|20|23|26)", cmake)
    flags = re.findall(r"(?:c\+\+|gnu\+\+)(11|14|17|20|23|26)", cmake)
    assert standards or features or flags, "CMakeLists.txt does not require C++11 or later."


def test_source_contains_iterative_root_finding():
    sources = []
    for name in os.listdir(PROJECT):
        if name.endswith((".cpp", ".cc", ".cxx")):
            with open(os.path.join(PROJECT, name), "r", errors="replace") as f:
                sources.append(f.read())
    source = "\n".join(sources)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//.*", "", source)
    assert re.search(r"\b(?:std::)?exp(?:l)?\s*\(", source), "C++ source does not evaluate the exponential equation."
    assert re.search(r"\b(?:for|while)\s*\(", source), "C++ source does not contain an iterative numerical method."
    assert re.search(r"(?<![A-Za-z0-9_])15(?:\.0*)?(?![A-Za-z0-9_])", source), "C++ source does not implement the equation lambda*exp(lambda)=15."


@pytest.fixture(scope="session")
def empirical_guard():
    with open(EMPIRICAL, "rb") as f:
        original = f.read()
    try:
        yield
    finally:
        with open(EMPIRICAL, "wb") as f:
            f.write(original)


@pytest.fixture(scope="session")
def built_executable():
    build_dir = tempfile.mkdtemp(prefix="fitter-verifier-build-")
    try:
        configured = subprocess.run(
            ["cmake", "-S", PROJECT, "-B", build_dir, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert configured.returncode == 0, "CMake configuration failed:\n" + configured.stdout

        built = subprocess.run(
            ["cmake", "--build", build_dir, "--target", "model_fitter", "--clean-first"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
        )
        assert built.returncode == 0, "Building CMake target model_fitter failed:\n" + built.stdout

        commands_path = os.path.join(build_dir, "compile_commands.json")
        assert os.path.isfile(commands_path), "CMake did not produce compile commands for the C++ program."
        with open(commands_path, "r", errors="replace") as f:
            commands = json.load(f)
        project_real = os.path.realpath(PROJECT) + os.sep
        compiled_cpp = [
            entry for entry in commands
            if os.path.realpath(entry.get("file", "")).startswith(project_real)
            and entry.get("file", "").endswith((".cpp", ".cc", ".cxx"))
        ]
        assert compiled_cpp, "The CMake build did not compile a project C++ source file."

        candidates = []
        for root, dirs, files in os.walk(build_dir):
            if "model_fitter" in files:
                candidates.append(os.path.join(root, "model_fitter"))
        candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
        assert candidates, "The model_fitter target did not create an executable named model_fitter."
        executable = candidates[0]
        with open(executable, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The built model_fitter is not a native compiled executable."
        yield executable
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def write_empirical(probabilities):
    rendered = [format(p, ".17g") for p in probabilities]
    with open(EMPIRICAL, "w") as f:
        f.write("k,p\n")
        for k, value in enumerate(rendered):
            f.write(f"{k},{value}\n")
    return [float(value) for value in rendered]


def expected_kl(probabilities):
    lam = 2.0
    for _ in range(30):
        f_val = lam * math.exp(lam) - 15
        f_prime = math.exp(lam) + lam * math.exp(lam)
        lam -= f_val / f_prime
    q_unnorm = [math.exp(-lam) * (lam ** k) / math.factorial(k) for k in range(5)]
    total = sum(q_unnorm)
    q = [value / total for value in q_unnorm]
    return f"{sum(probabilities[k] * math.log(probabilities[k] / q[k]) for k in range(5)):.6f}"


def execute_and_read(executable):
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    run = subprocess.run(
        [executable], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert run.returncode == 0, f"model_fitter exited with {run.returncode}: {run.stderr}"
    assert os.path.isfile(RESULT), "Executing model_fitter did not create /home/user/kl_result.txt."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{6}", content), "KL result is not a single value formatted to exactly 6 decimal places."
    return content


def test_kl_result(built_executable, empirical_guard):
    P = write_empirical([0.10, 0.30, 0.40, 0.15, 0.05])
    content = execute_and_read(built_executable)

    # Recompute the expected value to be principled
    # 1. Root finding for x * exp(x) = 15
    lam = 2.0
    for _ in range(20):
        f_val = lam * math.exp(lam) - 15
        f_prime = math.exp(lam) + lam * math.exp(lam)
        lam = lam - f_val / f_prime

    # 2. Compute Q
    Q_unnorm = [math.exp(-lam) * (lam**k) / math.factorial(k) for k in range(5)]
    S = sum(Q_unnorm)
    Q = [q / S for q in Q_unnorm]

    # 3. Compute KL Divergence
    kl = sum(P[k] * math.log(P[k] / Q[k]) for k in range(5))
    expected_output = f"{kl:.6f}"

    assert content == expected_output, f"Expected KL divergence {expected_output}, but got {content}."


def test_executable_reads_and_processes_empirical_data(built_executable, empirical_guard):
    rng = random.SystemRandom()
    for _ in range(4):
        weights = [rng.randint(1, 1000) for _ in range(5)]
        total = sum(weights)
        probabilities = write_empirical([weight / total for weight in weights])
        expected = expected_kl(probabilities)
        actual = execute_and_read(built_executable)
        assert actual == expected, f"For generated empirical data, expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
