#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

CANONICAL_SOURCE = r'''#include <iostream>
#include <random>
#include <cstdlib>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    double beta = std::stod(argv[1]);
    int N = std::stoi(argv[2]);
    int seed = std::stoi(argv[3]);

    std::mt19937 gen(seed);
    std::uniform_real_distribution<> dis(0.0, 1.0);

    int I = 10;
    int S = N - I;

    for (int t = 0; t < 30; ++t) {
        int new_infections = 0;
        for(int i=0; i<S; ++i) {
            if (dis(gen) < beta * I / N) {
                new_infections++;
            }
        }
        S -= new_infections;
        I += new_infections;
    }
    std::cout << I << std::endl;
    return 0;
}
'''


def compile_source(source, directory, name):
    src = os.path.join(directory, name + ".cpp")
    binary = os.path.join(directory, name)
    with open(src, "w") as f:
        f.write(source)
    comp = subprocess.run(
        ["g++", "-O3", "-std=c++11", src, "-o", binary],
        capture_output=True,
        text=True,
    )
    assert comp.returncode == 0, f"Test suite failed to compile sim.cpp: {comp.stderr}"
    return binary


def read_original_source():
    src_path = "/home/user/sim_src/sim.cpp"
    assert os.path.isfile(src_path), f"Source file missing at {src_path}"
    with open(src_path, "r") as f:
        source = f.read()
    assert source == CANONICAL_SOURCE, "The supplied simulator source was modified"
    return source


def test_sim_bin_compiled():
    bin_path = "/home/user/sim_bin"
    assert os.path.isfile(bin_path), f"Executable not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"File at {bin_path} is not executable"
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sim_bin is not a compiled ELF executable"


def test_sim_bin_matches_supplied_simulator():
    bin_path = "/home/user/sim_bin"
    assert os.path.isfile(bin_path), f"Executable not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"File at {bin_path} is not executable"
    read_original_source()

    cases = [
        (0.1, 1000, 1),
        (0.137, 1000, 19),
        (0.2, 1000, 73),
        (0.2719, 1000, 42),
        (0.3333, 1000, 100),
        (0.41, 1000, 7),
        (0.5, 1000, 88),
        (0.26, 250, 31),
        (0.34, 1500, 67),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        oracle_bin = compile_source(CANONICAL_SOURCE, tmpdir, "oracle_sim")
        for beta, population, seed in cases:
            args = [str(beta), str(population), str(seed)]
            expected = subprocess.run(
                [oracle_bin] + args,
                capture_output=True,
                text=True,
                timeout=10,
            )
            actual = subprocess.run(
                [bin_path] + args,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert expected.returncode == 0
            assert actual.returncode == 0, f"sim_bin failed for arguments {args}: {actual.stderr}"
            assert actual.stdout.strip() == expected.stdout.strip(), (
                f"sim_bin output differs from the supplied simulator for arguments {args}"
            )


def test_best_beta_content():
    txt_path = "/home/user/best_beta.txt"
    assert os.path.isfile(txt_path), f"Result file not found at {txt_path}"

    with open(txt_path, "r") as f:
        content = f.read().strip()

    assert content != "", "best_beta.txt is empty"

    # Snapshot and validate the agent-visible source before compiling it, so it
    # cannot serve as a mutable oracle for the expected answer.
    source = read_original_source()

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_bin = compile_source(source, tmpdir, "sim")

        def evaluate_beta(beta):
            total_infections = 0
            for seed in range(1, 101):
                res = subprocess.run(
                    [tmp_bin, str(beta), "1000", str(seed)],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert res.returncode == 0, f"Simulator failed for seed {seed}: {res.stderr}"
                total_infections += int(res.stdout.strip())
            mean_infections = total_infections / 100.0
            return mean_infections - 634.0

        # Bisection method to find the root.
        a, b = 0.1, 0.5
        fa = evaluate_beta(a)
        fb = evaluate_beta(b)

        assert fa * fb < 0, "Root is not bracketed in [0.1, 0.5]"

        tol = 1e-6
        while (b - a) / 2.0 > tol:
            mid = (a + b) / 2.0
            fmid = evaluate_beta(mid)
            if fmid == 0:
                a = b = mid
                break
            elif fa * fmid < 0:
                b = mid
                fb = fmid
            else:
                a = mid
                fa = fmid

        expected_beta = (a + b) / 2.0
        expected_str = f"{expected_beta:.4f}"

    assert content == expected_str, f"Expected beta to be {expected_str}, but got {content} in best_beta.txt"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
