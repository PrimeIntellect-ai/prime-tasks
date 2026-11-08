#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

REF_CPP_CODE = r'''
#include <iostream>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <iomanip>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int seed = std::atoi(argv[1]);
    std::srand(seed);

    int N = 10000;
    std::vector<double> data(N);
    for (int i = 0; i < N; ++i) {
        data[i] = (std::rand() % 1000) / 100.0;
    }

    double x = 0.0;
    double learning_rate = 0.01;

    for (int iter = 0; iter < 5000; ++iter) {
        double gradient = 0.0;
        for (int i = 0; i < N; ++i) {
            gradient += (x - data[i]);
        }
        gradient /= N;

        if (std::abs(gradient) <= 1e-5) {
            break;
        }

        x = x - learning_rate * gradient;
    }

    std::cout << std::fixed << std::setprecision(6) << x << std::endl;
    return 0;
}
'''

@pytest.fixture(scope="session")
def built_programs(tmp_path_factory):
    tmpdir = tmp_path_factory.mktemp("build")
    ref_cpp = tmpdir / "ref_sim.cpp"
    ref_bin = tmpdir / "ref_sim"
    submitted_bin = tmpdir / "submitted_sim"
    ref_cpp.write_text(REF_CPP_CODE)

    compile_ref = subprocess.run(
        ["g++", "-O2", str(ref_cpp), "-o", str(ref_bin)],
        capture_output=True, text=True
    )
    assert compile_ref.returncode == 0, f"Failed to compile reference C++ code: {compile_ref.stderr}"

    compile_submitted = subprocess.run(
        ["g++", "-O2", "-fopenmp", "/home/user/sim.cpp", "-o", str(submitted_bin)],
        capture_output=True, text=True
    )
    assert compile_submitted.returncode == 0, f"Failed to compile /home/user/sim.cpp: {compile_submitted.stderr}"

    return str(ref_bin), str(submitted_bin)


def run_program(binary, seed, threads=None):
    env = os.environ.copy()
    if threads is not None:
        env["OMP_NUM_THREADS"] = str(threads)
        env["OMP_DYNAMIC"] = "FALSE"
    result = subprocess.run(
        [binary, str(seed)], capture_output=True, text=True,
        env=env, timeout=30
    )
    assert result.returncode == 0, f"{binary} failed for seed {seed}: {result.stderr}"
    output = result.stdout.strip()
    assert re.fullmatch(r"-?\d+\.\d{6}", output), \
        f"{binary} produced invalid output for seed {seed}: {result.stdout!r}"
    return output


def test_training_data_exists():
    """Verify that the training_data.txt file exists."""
    assert os.path.isfile("/home/user/training_data.txt"), "/home/user/training_data.txt does not exist."


def test_training_data_contents(built_programs):
    """Verify that the training data contains the correct deterministic results."""
    ref_bin, _ = built_programs
    seeds = [10, 20, 30, 40, 50]
    expected_outputs = [run_program(ref_bin, seed) for seed in seeds]

    with open("/home/user/training_data.txt", "r") as f:
        agent_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(agent_lines) == len(seeds), f"Expected {len(seeds)} lines in training_data.txt, found {len(agent_lines)}"
    for i, (expected, actual) in enumerate(zip(expected_outputs, agent_lines)):
        assert actual == expected, f"Output mismatch for seed {seeds[i]}: expected {expected}, got {actual}"


def test_sim_cpp_modifications():
    """Verify that the simulation code was modified correctly."""
    sim_cpp_path = "/home/user/sim.cpp"
    assert os.path.isfile(sim_cpp_path), f"The file {sim_cpp_path} does not exist."

    with open(sim_cpp_path, "r") as f:
        content = f.read()

    assert "#pragma omp atomic" not in content, "The non-deterministic '#pragma omp atomic' directive was not removed."
    assert "iter < 100" not in content, "The fixed iteration loop condition 'iter < 100' was not removed."
    assert "1e-5" in content or "0.00001" in content, "Convergence threshold 1e-5 is missing from the code."
    assert "5000" in content, "Maximum iteration bound of 5000 is missing from the code."


def test_requested_binary_exists_and_is_executable():
    sim_bin = "/home/user/sim"
    assert os.path.isfile(sim_bin), f"The compiled binary {sim_bin} does not exist."
    assert os.access(sim_bin, os.X_OK), f"The compiled binary {sim_bin} is not executable."
    with open(sim_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{sim_bin} is not a compiled ELF binary."


def test_submitted_simulation_behavior_and_determinism(built_programs):
    ref_bin, rebuilt_bin = built_programs
    rng = secrets.SystemRandom()
    hidden_seeds = []
    while len(hidden_seeds) < 2:
        seed = rng.randrange(1, 2**31 - 1)
        if seed not in hidden_seeds and seed not in (10, 20, 30, 40, 50):
            hidden_seeds.append(seed)

    for seed in hidden_seeds:
        expected = run_program(ref_bin, seed)

        rebuilt_outputs = [run_program(rebuilt_bin, seed, threads) for threads in (1, 4)]
        assert rebuilt_outputs[0] == rebuilt_outputs[1], \
            f"Recompiled sim.cpp is non-deterministic across thread counts for seed {seed}: {rebuilt_outputs}"
        assert rebuilt_outputs[0] == expected, \
            f"Recompiled sim.cpp is incorrect for seed {seed}: expected {expected}, got {rebuilt_outputs[0]}"

        installed_outputs = [run_program("/home/user/sim", seed, threads) for threads in (1, 4)]
        assert installed_outputs[0] == installed_outputs[1], \
            f"/home/user/sim is non-deterministic across thread counts for seed {seed}: {installed_outputs}"
        assert installed_outputs[0] == expected, \
            f"/home/user/sim is incorrect for seed {seed}: expected {expected}, got {installed_outputs[0]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
