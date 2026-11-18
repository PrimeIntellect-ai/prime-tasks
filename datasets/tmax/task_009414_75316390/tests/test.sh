#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

CPP_PATH = "/home/user/mc_volume.cpp"
EXE_PATH = "/home/user/mc_volume"
PDB_PATH = "/home/user/protein.pdb"
RESULT_PATH = "/home/user/result.txt"

TRUTH_CODE = r'''
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <omp.h>
#include <random>
#include <iomanip>

struct Atom { float x, y, z, r; };

int main() {
    std::vector<Atom> atoms;
    std::ifstream in("/home/user/protein.pdb");
    std::string line;
    while(std::getline(in, line)) {
        if(line.substr(0,4) == "ATOM") {
            float x = std::stof(line.substr(30, 8));
            float y = std::stof(line.substr(38, 8));
            float z = std::stof(line.substr(46, 8));
            atoms.push_back({x, y, z, 1.5f});
        }
    }

    int num_samples = 1000000;
    float box_size = 20.0f;
    float box_volume = box_size * box_size * box_size;

    int hits = 0;
    float vol_per_sample = box_volume / num_samples;

    #pragma omp parallel for reduction(+:hits)
    for(int i = 0; i < num_samples; i++) {
        std::mt19937 gen(42 + i);
        std::uniform_real_distribution<float> dist(0.0f, box_size);
        float px = dist(gen);
        float py = dist(gen);
        float pz = dist(gen);

        bool hit = false;
        for(const auto& atom : atoms) {
            float dx = px - atom.x;
            float dy = py - atom.y;
            float dz = pz - atom.z;
            if(dx*dx + dy*dy + dz*dz < atom.r * atom.r) {
                hit = true;
                break;
            }
        }
        if(hit) {
            hits++;
        }
    }

    float total_volume = hits * vol_per_sample;
    std::cout << std::fixed << std::setprecision(6) << total_volume << std::endl;
    return 0;
}
'''


def run_program(path, threads):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_DYNAMIC"] = "FALSE"
    completed = subprocess.run(
        [path], check=True, capture_output=True, text=True,
        env=env, timeout=90
    )
    assert completed.stderr == "", f"{path} wrote unexpected stderr: {completed.stderr!r}"
    output = completed.stdout.strip()
    assert re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)", output), \
        f"{path} did not emit exactly one floating-point value: {completed.stdout!r}"
    return output


@pytest.fixture(scope="session")
def compiled_tools():
    with tempfile.TemporaryDirectory() as tmpdir:
        truth_src = os.path.join(tmpdir, "truth.cpp")
        truth_exe = os.path.join(tmpdir, "truth_exe")
        rebuilt_exe = os.path.join(tmpdir, "student_rebuilt")

        with open(truth_src, "w") as f:
            f.write(TRUTH_CODE)

        subprocess.run(
            ["g++", "-O3", "-fopenmp", truth_src, "-o", truth_exe],
            check=True, capture_output=True, text=True
        )
        subprocess.run(
            ["g++", "-O3", "-fopenmp", CPP_PATH, "-o", rebuilt_exe],
            check=True, capture_output=True, text=True
        )
        yield truth_exe, rebuilt_exe


def get_expected_volume(truth_exe):
    return run_program(truth_exe, 3)


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} is missing. Did you compile the code?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."


def test_cpp_modifications():
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} is missing."
    with open(CPP_PATH, "r") as f:
        content = f.read()

    assert "reduction(+:total_volume)" not in content, \
        "The code still uses floating-point reduction for total_volume, which is non-deterministic."
    assert re.search(r"^\s*#\s*pragma\s+omp\b[^\n]*\bparallel\b", content, re.MULTILINE), \
        "The modified source no longer contains OpenMP parallelism."


def test_result_and_executable_are_correct_and_deterministic(compiled_tools):
    truth_exe, _ = compiled_tools
    expected = get_expected_volume(truth_exe)

    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} is missing. Did you save the output?"
    with open(RESULT_PATH, "r") as f:
        student_result = f.read().strip()
    assert student_result == expected, \
        f"Result in {RESULT_PATH} ({student_result}) does not match the deterministic expected volume ({expected})."

    outputs = [run_program(EXE_PATH, threads) for threads in (1, 2, 4, 4)]
    assert all(output == expected for output in outputs), \
        f"The submitted executable is incorrect or non-deterministic across runs/thread counts: {outputs}; expected {expected}."
    assert student_result == outputs[0], \
        "result.txt is not the output produced by the submitted executable."


def test_artifacts_on_additional_input(compiled_tools):
    truth_exe, rebuilt_exe = compiled_tools
    with open(PDB_PATH, "rb") as f:
        original_pdb = f.read()

    alternate_pdb = (
        "ATOM      1  N   ALA A   1       3.125   5.750   7.375  1.00  0.00           N\n"
        "ATOM      2  CA  ALA A   1       8.500  12.250   4.625  1.00  0.00           C\n"
        "ATOM      3  C   ALA A   1      15.375  14.125  16.500  1.00  0.00           C\n"
        "ATOM      4  O   ALA A   1      11.750   3.500  13.875  1.00  0.00           O\n"
    ).encode()

    try:
        with open(PDB_PATH, "wb") as f:
            f.write(alternate_pdb)

        expected = get_expected_volume(truth_exe)
        installed_outputs = [run_program(EXE_PATH, threads) for threads in (1, 4)]
        rebuilt_outputs = [run_program(rebuilt_exe, threads) for threads in (2, 4)]

        assert all(output == expected for output in installed_outputs), \
            f"The submitted executable does not implement the required computation: {installed_outputs}; expected {expected}."
        assert all(output == expected for output in rebuilt_outputs), \
            f"Compiling the submitted source does not produce the required deterministic computation: {rebuilt_outputs}; expected {expected}."
    finally:
        with open(PDB_PATH, "wb") as f:
            f.write(original_pdb)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
